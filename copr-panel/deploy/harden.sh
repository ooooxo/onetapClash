#!/usr/bin/env bash
# =============================================================================
# harden.sh — 服务器基础安全加固(幂等,可重跑)
#   干什么: fail2ban(SSH 封禁)+ ufw(只放行必要端口)+ sshd 收紧(开公钥登录)
#   怎么跑: sudo bash harden.sh
#   需要什么: root、Debian/Ubuntu、/root/.ssh/authorized_keys 里已有你的公钥
# 参数集中在这里,改值不用读正文:
# =============================================================================
SSH_PORT="${SSH_PORT:-22}"
OPEN_TCP="${OPEN_TCP:-22,80,443}"          # ufw 放行的 TCP 端口(逗号分隔)
OPEN_UDP="${OPEN_UDP:-}"                   # 节点用的 UDP 端口(hy2/tuic),逗号分隔
F2B_MAXRETRY="${F2B_MAXRETRY:-4}"
F2B_FINDTIME="${F2B_FINDTIME:-30m}"
F2B_BANTIME="${F2B_BANTIME:-1d}"
F2B_IGNOREIP="${F2B_IGNOREIP:-127.0.0.1/8 ::1}"   # 追加你的固定 IP,避免自锁
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-no}"  # yes = 关掉密码登录(确认密钥能登再开)

set -euo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){  echo -e "\033[32m[OK]\033[0m $*"; }

export DEBIAN_FRONTEND=noninteractive
log "安装 fail2ban / ufw..."
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq fail2ban ufw rsyslog >/dev/null 2>&1

# ── sshd:开公钥登录(密码是否保留由 DISABLE_PASSWORD_AUTH 决定)─────────────
log "配置 sshd..."
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"
_set_ssh(){  # 键 值:有则替换,无则追加
  local k="$1" v="$2"
  if grep -qE "^[#[:space:]]*${k}[[:space:]]" /etc/ssh/sshd_config; then
    sed -i -E "s|^[#[:space:]]*${k}[[:space:]].*|${k} ${v}|" /etc/ssh/sshd_config
  else
    echo "${k} ${v}" >> /etc/ssh/sshd_config
  fi
}
_set_ssh PubkeyAuthentication yes
_set_ssh AuthorizedKeysFile ".ssh/authorized_keys"
_set_ssh MaxAuthTries 4
if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  [[ -s /root/.ssh/authorized_keys ]] || { echo "拒绝关闭密码登录:/root/.ssh/authorized_keys 为空,会锁死自己"; exit 1; }
  _set_ssh PasswordAuthentication no
  _set_ssh PermitRootLogin prohibit-password
fi
sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd
ok "sshd 已重启(PubkeyAuthentication yes)"

# ── fail2ban ────────────────────────────────────────────────────────────────
log "配置 fail2ban(sshd jail)..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip  = ${F2B_IGNOREIP}
bantime   = ${F2B_BANTIME}
findtime  = ${F2B_FINDTIME}
maxretry  = ${F2B_MAXRETRY}
backend   = systemd
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 4w

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
mode     = aggressive
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd >/dev/null 2>&1 && ok "fail2ban sshd jail 生效" || { echo "fail2ban 异常"; journalctl -u fail2ban -n 20 --no-pager; exit 1; }

# ── ufw ─────────────────────────────────────────────────────────────────────
log "配置 ufw..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
IFS=',' read -ra _t <<< "$OPEN_TCP"
for p in "${_t[@]}"; do [[ -n "$p" ]] && ufw allow "${p}/tcp" >/dev/null; done
if [[ -n "$OPEN_UDP" ]]; then
  IFS=',' read -ra _u <<< "$OPEN_UDP"
  for p in "${_u[@]}"; do [[ -n "$p" ]] && ufw allow "${p}/udp" >/dev/null; done
fi
ufw --force enable >/dev/null
ok "ufw 已启用"
ufw status numbered

echo
ok "加固完成。SSH 端口 ${SSH_PORT};密码登录: $([[ "$DISABLE_PASSWORD_AUTH" == "yes" ]] && echo 已关闭 || echo 仍开启)"
