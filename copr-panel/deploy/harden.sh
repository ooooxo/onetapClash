#!/usr/bin/env bash
# =============================================================================
# harden.sh — 服务器基础安全加固(幂等,可重跑)
#   干什么: fail2ban(SSH 封禁)+ ufw(只放行必要端口)+ sshd 收紧(开公钥登录)+ 自动安全更新
#   怎么跑: sudo bash harden.sh
#   需要什么: root、Debian/Ubuntu、/root/.ssh/authorized_keys 里已有你的公钥
# 参数集中在这里,改值不用读正文(config.env 里同名变量优先):
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
OPEN_TCP="${OPEN_TCP:-80,443}"             # ufw 放行的 TCP 端口(逗号分隔);sshd 实际端口总会自动放行
OPEN_UDP="${OPEN_UDP:-}"                   # 节点用的 UDP 端口(hy2/tuic),逗号分隔
F2B_MAXRETRY="${F2B_MAXRETRY:-4}"
F2B_FINDTIME="${F2B_FINDTIME:-30m}"
F2B_BANTIME="${F2B_BANTIME:-1d}"
F2B_IGNOREIP="${F2B_IGNOREIP:-127.0.0.1/8 ::1}"   # 追加你的固定 IP,避免自锁
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-no}"  # yes = 关掉密码登录(确认密钥能登再开)

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){  echo -e "\033[32m[OK]\033[0m $*"; }

export DEBIAN_FRONTEND=noninteractive
log "安装 fail2ban / ufw..."
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq -o DPkg::Lock::Timeout=300 fail2ban ufw rsyslog >/dev/null

# ── sshd:开公钥登录(密码是否保留由 DISABLE_PASSWORD_AUTH 决定)─────────────
# 写 sshd_config.d 里最先加载的 drop-in:sshd 取【第一次出现】的值,直接改 sshd_config
# 会被 Include 进来的 50-cloud-init.conf(PasswordAuthentication yes)抢先,改了等于没改。
log "配置 sshd..."
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config \
  || { echo "sshd_config 没有 Include sshd_config.d/*.conf,drop-in 不会生效"; exit 1; }
if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  [[ -s /root/.ssh/authorized_keys ]] || { echo "拒绝关闭密码登录:/root/.ssh/authorized_keys 为空,会锁死自己"; exit 1; }
fi
mkdir -p /etc/ssh/sshd_config.d
{
  echo "# onetapclash harden.sh 生成,重跑会覆盖"
  echo "PubkeyAuthentication yes"
  echo "MaxAuthTries 4"
  if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
    echo "PermitRootLogin prohibit-password"
  fi
} > /etc/ssh/sshd_config.d/00-onetap.conf
sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd
# 以 sshd 实际生效的值为准,不信自己写了什么
if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  # 不用 grep -q:它命中即退出,sshd -T 收 SIGPIPE,pipefail 下整条判成失败
  sshd -T | grep -x 'passwordauthentication no' >/dev/null || { echo "密码登录没关掉(被别的配置覆盖),检查 sshd -T"; exit 1; }
fi
# sshd 真正监听的端口(不信配置里填的):填错也不会把自己关在 ufw 外面
SSH_PORTS="$(sshd -T | awk '$1=="port"{print $2}' | sort -u | paste -sd, -)"
ok "sshd 已重启(公钥登录开,端口 ${SSH_PORTS})"

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
port     = ${SSH_PORTS}
filter   = sshd
mode     = aggressive
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd >/dev/null 2>&1 && ok "fail2ban sshd jail 生效" || { echo "fail2ban 异常"; journalctl -u fail2ban -n 20 --no-pager; exit 1; }

# ── ufw ─────────────────────────────────────────────────────────────────────
# 只增不减,不 reset:重跑 / 单独跑时不会把 s-ui 里另开的节点、端口跳跃段、手加的规则冲掉
log "配置 ufw..."
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
IFS=',' read -ra _t <<< "${SSH_PORTS},${OPEN_TCP}"
for p in "${_t[@]}"; do [[ -n "$p" ]] && ufw allow "${p}/tcp" >/dev/null; done
if [[ -n "$OPEN_UDP" ]]; then
  IFS=',' read -ra _u <<< "$OPEN_UDP"
  for p in "${_u[@]}"; do [[ -n "$p" ]] && ufw allow "${p}/udp" >/dev/null; done
fi
ufw --force enable >/dev/null
ok "ufw 已启用"
ufw status numbered

# ── 自动安全更新:只装发行版安全补丁,不自动重启 ─────────────────────────────
log "配置自动安全更新..."
apt-get install -y -qq -o DPkg::Lock::Timeout=300 unattended-upgrades >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
ok "unattended-upgrades 已开(每日安全补丁)"

echo
ok "加固完成。SSH 端口 ${SSH_PORTS};密码登录: $([[ "$DISABLE_PASSWORD_AUTH" == "yes" ]] && echo 已关闭 || echo 仍开启)"
