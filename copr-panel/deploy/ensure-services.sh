#!/usr/bin/env bash
# =============================================================================
# ensure-services.sh — 保证一切自动起来、挂了自动拉回来(幂等,可重跑)
#   干什么: ① 全部服务开机自启 ② 崩溃无限重启(drop-in,不改发行版原 unit)
#           ③ 证书续期后自动 reload nginx + 重启 s-ui(sing-box 只在启动时读证书)
#           ④ 每分钟健康检查:端口没监听就重启对应服务
#   怎么跑: sudo bash ensure-services.sh
# 参数:
# =============================================================================
CONV_ADDR="${CONV_ADDR:-127.0.0.1:25501}"
SUI_ADDR="${SUI_ADDR:-127.0.0.1:2095}"
SERVICES="${SERVICES:-s-ui sui-converter nginx fail2ban}"

set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
ok(){ echo -e "\033[32m[OK]\033[0m $*"; }

# ── 1) 开机自启 + 崩溃重启 ───────────────────────────────────────────────────
for svc in $SERVICES; do
  systemctl cat "$svc" >/dev/null 2>&1 || { echo "[skip] 无 $svc"; continue; }
  systemctl enable "$svc" >/dev/null 2>&1 || true
  mkdir -p "/etc/systemd/system/${svc}.service.d"
  # StartLimitIntervalSec=0 关掉"短时间内重启太多次就放弃"——代理服务宁可一直重试
  cat > "/etc/systemd/system/${svc}.service.d/10-autorestart.conf" <<EOF
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=5s
EOF
  ok "$svc:开机自启 + 崩溃 5s 重启"
done
systemctl daemon-reload

# ── 2) 证书续期钩子:sing-box 只在启动时读证书文件,续期后必须重启才生效 ──────
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/10-reload-onetap.sh <<'EOF'
#!/usr/bin/env bash
# certbot 续期成功后自动跑:nginx 热重载,s-ui 重启(sing-box 只在启动时读证书)
systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
systemctl restart s-ui 2>/dev/null || true
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/10-reload-onetap.sh
systemctl enable --now certbot.timer >/dev/null 2>&1 || true
ok "证书续期钩子就位(续期后自动 reload nginx + restart s-ui)"

# ── 3) 网络调优:fq + BBR + 大缓冲(非破坏,不断连)──────────────────────────
cat > /etc/sysctl.d/99-onetap.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
EOF
sysctl --system >/dev/null 2>&1 || true
# 当前网卡立即切 fq,不等重启
IFACE="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)"
[[ -n "$IFACE" ]] && tc qdisc replace dev "$IFACE" root fq 2>/dev/null || true
ok "网络调优:qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null) cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"

# ── 4) 健康看门狗:端口没监听 = 服务其实是死的,systemd 看不出来 ──────────────
cat > /usr/local/bin/onetap-healthcheck <<EOF
#!/usr/bin/env bash
# 端口不通就重启对应服务。进程活着但端口没起(sing-box 配置炸了)systemd 察觉不到。
set -u
curl -sf --max-time 5 "http://${CONV_ADDR}/health" >/dev/null || systemctl restart sui-converter
# 端口跳跃的 nat 规则会被 ufw reload / reset 冲掉,这里每分钟幂等重放一次
[ -x /usr/local/bin/onetap-hopping ] && /usr/local/bin/onetap-hopping
curl -so /dev/null --max-time 5 "http://${SUI_ADDR}/" || systemctl restart s-ui
systemctl is-active --quiet nginx || systemctl restart nginx
EOF
chmod +x /usr/local/bin/onetap-healthcheck
cat > /etc/systemd/system/onetap-healthcheck.service <<'EOF'
[Unit]
Description=onetapclash health check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/onetap-healthcheck
EOF
cat > /etc/systemd/system/onetap-healthcheck.timer <<'EOF'
[Unit]
Description=onetapclash health check every minute
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now onetap-healthcheck.timer >/dev/null 2>&1
ok "看门狗已启用(每分钟检查端口,不通就重启)"

echo
systemctl list-unit-files --no-pager --no-legend $(for s in $SERVICES; do echo "$s.service"; done) 2>/dev/null | sed 's/^/  /'
