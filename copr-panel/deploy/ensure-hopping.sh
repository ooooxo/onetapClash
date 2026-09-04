#!/usr/bin/env bash
# =============================================================================
# ensure-hopping.sh — Hysteria2 端口跳跃(幂等,可重跑)
#
#   为什么: 国内运营商对【固定 UDP 端口】做 QoS/限速是 hy2 掉速断流最常见的原因。
#           把一整段 UDP 端口 REDIRECT 到 hy2 的真实监听端口,客户端每隔几十秒换一个
#           源目标端口,单端口限速就套不住整条连接。服务端 sing-box 完全不用改。
#
#   怎么跑: sudo bash ensure-hopping.sh
#   参数:
# =============================================================================
HY2_PORT="${HY2_PORT:-443}"                 # hy2 真实监听端口(重定向目标)
HY2_HOP_PORTS="${HY2_HOP_PORTS:-20000-25000}"   # 对外开放的跳跃端口段
HOP_ENABLE="${HOP_ENABLE:-yes}"

set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
ok(){ echo -e "\033[32m[OK]\033[0m $*"; }

lc(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [[ "$(lc "$HOP_ENABLE")" == "no" ]]; then
  echo "[skip] HOP_ENABLE=no"; exit 0
fi
[[ "$HY2_HOP_PORTS" =~ ^([0-9]+)-([0-9]+)$ ]] || { echo "HY2_HOP_PORTS 需形如 20000-25000"; exit 1; }
LO="${BASH_REMATCH[1]}"; HI="${BASH_REMATCH[2]}"
(( LO > 0 && HI > LO && HI < 65536 )) || { echo "端口段不合法: $HY2_HOP_PORTS"; exit 1; }
(( HY2_PORT < LO || HY2_PORT > HI )) || { echo "hy2 端口 ${HY2_PORT} 不能落在跳跃段内(会自环)"; exit 1; }

# 规则应用脚本:开机、以及每分钟看门狗都会调它。
# 必须幂等 —— ufw reload / harden.sh 的 `ufw --force reset` 会清掉 nat 链,靠重复应用自愈。
cat > /usr/local/bin/onetap-hopping <<EOF
#!/usr/bin/env bash
# Hysteria2 端口跳跃:把 UDP ${LO}-${HI} 全部重定向到 ${HY2_PORT}。幂等。
set -u
iptables -t nat -C PREROUTING -p udp --dport ${LO}:${HI} -j REDIRECT --to-ports ${HY2_PORT} 2>/dev/null \\
  || iptables -t nat -A PREROUTING -p udp --dport ${LO}:${HI} -j REDIRECT --to-ports ${HY2_PORT}
EOF
chmod +x /usr/local/bin/onetap-hopping
/usr/local/bin/onetap-hopping

cat > /etc/systemd/system/onetap-hopping.service <<'EOF'
[Unit]
Description=onetapclash hysteria2 port hopping (nat redirect)
After=network-online.target ufw.service
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/onetap-hopping
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable onetap-hopping.service >/dev/null 2>&1
ok "nat 重定向已生效:UDP ${LO}-${HI} → ${HY2_PORT}"

command -v ufw >/dev/null && ufw allow "${LO}:${HI}/udp" >/dev/null 2>&1 \
  && ok "ufw 放行 ${LO}:${HI}/udp"

echo
iptables -t nat -S PREROUTING | sed 's/^/  /'
echo
ok "客户端侧由 converter 在订阅里下发 ports/hop-interval,用户刷新订阅即生效"
