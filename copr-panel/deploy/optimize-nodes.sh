#!/usr/bin/env bash
# 阶段 3:优化当前节点。分两类——
#   A) 安全项(本脚本自动):qdisc fq + 缓冲/BBR sysctl,不重启 sing-box、不断连。
#   B) s-ui 侧(需重载 sing-box,闪断):HY2 解速 + VLESS 转真 Reality,走面板/runbook。
# 用法: sudo bash optimize-nodes.sh
set -euo pipefail
SUIDB=/usr/local/s-ui/db/s-ui.db
TS="$(date +%Y%m%d-%H%M%S)"; BK="/root/copr-panel-backup/$TS"; mkdir -p "$BK"
log(){ echo -e "\033[36m[*]\033[0m $*"; }; ok(){ echo -e "\033[32m[OK]\033[0m $*"; }

# ── A) sysctl:fq(BBR 最佳拍档,治 Reality 卡顿的丢包)+ 大缓冲 ──────────────
log "写入 sysctl(fq / bbr / 缓冲)..."
cat > /etc/sysctl.d/99-copr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
EOF
sysctl --system >/dev/null
# 当前网卡即时切 fq(不断连)
IFACE="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)"
[[ -n "$IFACE" ]] && tc qdisc replace dev "$IFACE" root fq 2>/dev/null || true
ok "qdisc=$(sysctl -n net.core.default_qdisc) cc=$(sysctl -n net.ipv4.tcp_congestion_control) — 非破坏,已生效"

# ── B) s-ui 侧改动的 runbook(不自动改 DB,避免 out_json 手改出错)──────────
[[ -f "$SUIDB" ]] && cp "$SUIDB" "$BK/s-ui.db.bak" && ok "已备份 s-ui DB → $BK"
cat <<'RUN'

━━━ s-ui 侧节点优化(需重载 sing-box = 在线用户短暂重连,挑低峰)━━━
用新面板(或 s-ui 原面板)改,让 s-ui 自己重生成配置,别手改 DB:

1) Hysteria2「快速节点」解速(修 10MB/s):
   编辑该入站 → 打开「忽略客户端带宽(ignore_client_bandwidth)」→ 保存。
   → 服务器用 BBR 无视客户端低带宽,配合已生效的大缓冲,吃满带宽。

2) VLESS「安全节点」转真 Reality(修流媒体卡顿 + 提安全)⚠️破坏性:
   编辑该入站 → TLS 从「自签(tls_id=1)」改为「Reality(tls_id=2)」
   → 顺手把 Reality 握手端口 444 改回 443。保存。
   → 用户需重拉一次订阅(converter 会自动带上 reality 参数)。改前通知。

两步都会让 s-ui reload sing-box(闪断一次)。做完观察 journalctl -u s-ui。
回滚:导入 $BK/s-ui.db.bak 或面板改回原值。
RUN
