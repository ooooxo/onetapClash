#!/usr/bin/env bash
# =============================================================================
# ensure-services.sh — 保证一切自动起来、挂了自动拉回来(幂等,可重跑)
#   干什么: ① 全部服务开机自启 ② 崩溃无限重启(drop-in,不改发行版原 unit)
#           ③ 证书续期后自动 reload nginx + 重启 s-ui(sing-box 只在启动时读证书)
#           ④ 每分钟健康检查:端口没监听就重启对应服务
#   怎么跑: sudo bash ensure-services.sh
# 参数:
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
# 必须先读 config.env 再写默认值:load_config_env 不覆盖已有值,
# 反过来的话默认值先占位,单独跑脚本时 config.env 整个被无视。
load_config_env config.env
CONV_ADDR="${CONV_ADDR:-127.0.0.1:25501}"
SUI_ADDR="${SUI_ADDR:-127.0.0.1:${SUI_PORT:-2095}}"
SERVICES="${SERVICES:-s-ui sui-converter nginx fail2ban}"
SWAP_MB="${SWAP_MB:-1024}"                  # 没有 swap 时建的 swapfile 大小;0 = 不建

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
vm.swappiness = 10
EOF
sysctl --system >/dev/null 2>&1 || true
# 当前网卡立即切 fq,不等重启
IFACE="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)"
[[ -n "$IFACE" ]] && tc qdisc replace dev "$IFACE" root fq 2>/dev/null || true
ok "网络调优:qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null) cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"

# ── 3.5) swap:1G 内存的小机没有 swap,s-ui(内嵌 sing-box)内存一冲高就被 OOM 杀,
#    全部节点跟着断(实际发生过)。有 swap 就不动。
#    swap 是优化不是必需:LXC/OpenVZ 不许 swapon,不能因此让后面的看门狗装不上。
if [[ -z "$(swapon --noheadings)" && "$SWAP_MB" -gt 0 ]]; then
  [[ -f /swapfile ]] || { fallocate -l "${SWAP_MB}M" /swapfile; chmod 600 /swapfile; }
  # 上次中断在 fallocate 之后会留下没格式化的文件,每次都 swapon 失败 → 补 mkswap
  blkid -t TYPE=swap /swapfile >/dev/null 2>&1 || mkswap /swapfile >/dev/null
  if swapon /swapfile; then
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    echo "[!] swapon 失败(容器虚拟化不支持?),跳过 swap"
  fi
fi
ok "swap:$(free -m | awk '/^Swap:/{print $2}')MB"

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
