#!/usr/bin/env bash
# =============================================================================
# factory-reset.sh — 把本机恢复成「没装过 onetapclash」的状态
#
#   ⚠️ 破坏性:会删掉 s-ui(含所有节点与会员)、converter、面板、证书、防火墙规则。
#      跑之前先备份;脚本自己也会备份一份到 /root/onetap-fullbackup-<时间戳>。
#
#   用途: ① 验证 bootstrap.sh 的全新安装路径 ② 想推倒重来
#   怎么跑: sudo bash factory-reset.sh --yes
#   还原:  sudo bash factory-reset.sh --restore <备份目录>
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){  echo -e "\033[32m[OK]\033[0m $*"; }

_backup(){
  local bk="/root/onetap-fullbackup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bk"
  [[ -d /usr/local/s-ui/db ]] && cp -a /usr/local/s-ui/db "$bk/sui-db"
  for f in users.json rules.json; do
    [[ -f "/opt/sui-converter/$f" ]] && cp -a "/opt/sui-converter/$f" "$bk/"
  done
  [[ -d /etc/letsencrypt ]] && tar czf "$bk/letsencrypt.tgz" -C /etc letsencrypt
  [[ -f config.env ]] && cp config.env "$bk/"
  echo "$bk" > /root/.last-fullbackup
  ok "已备份 → $bk"
}

_restore(){
  local bk="${1:?用法: factory-reset.sh --restore <备份目录>}"
  [[ -d "$bk" ]] || { echo "备份目录不存在: $bk"; exit 1; }
  log "还原 $bk ..."
  systemctl stop s-ui sui-converter 2>/dev/null || true
  [[ -d "$bk/sui-db" ]] && { mkdir -p /usr/local/s-ui; cp -a "$bk/sui-db/." /usr/local/s-ui/db/; }
  [[ -f "$bk/letsencrypt.tgz" ]] && tar xzf "$bk/letsencrypt.tgz" -C /etc
  for f in users.json rules.json; do
    [[ -f "$bk/$f" ]] && cp -a "$bk/$f" /opt/sui-converter/ 2>/dev/null || true
  done
  systemctl start s-ui sui-converter 2>/dev/null || true
  ok "已还原。建议再跑一次 bootstrap.sh 让 nginx/防火墙对齐。"
}

_wipe(){
  _backup
  log "停止并移除服务..."
  systemctl stop s-ui sui-converter nginx 2>/dev/null || true
  systemctl disable s-ui sui-converter onetap-healthcheck.timer onetap-hopping 2>/dev/null || true
  rm -rf /usr/local/s-ui /opt/sui-converter /opt/copr-panel
  rm -f  /etc/systemd/system/s-ui.service /etc/systemd/system/sui-converter.service
  rm -f  /etc/systemd/system/onetap-*.service /etc/systemd/system/onetap-*.timer
  rm -f  /etc/systemd/system/*.service.d/10-autorestart.conf
  rm -f  /usr/local/bin/onetap-healthcheck /usr/local/bin/onetap-hopping /usr/bin/s-ui
  rm -f  /etc/letsencrypt/renewal-hooks/deploy/10-reload-onetap.sh
  rm -rf /etc/letsencrypt /etc/onetap
  rm -f  /etc/nginx/sites-enabled/* /etc/nginx/sites-available/copr* /etc/nginx/sites-available/acme-bootstrap
  rm -f  /etc/sysctl.d/99-onetap.conf
  log "清防火墙..."
  iptables -t nat -F PREROUTING 2>/dev/null || true
  ufw --force reset >/dev/null 2>&1 || true
  ufw --force disable >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl start nginx 2>/dev/null || true
  ok "已恢复到未安装状态。现在可以跑: sudo bash bootstrap.sh"
}

case "${1:-}" in
  --yes)     _wipe ;;
  --restore) _restore "${2:-}" ;;
  *) cat <<EOF
用法:
  sudo bash factory-reset.sh --yes                  # 清空(会先自动备份)
  sudo bash factory-reset.sh --restore <备份目录>    # 从备份还原

⚠️  --yes 会删除 s-ui(含全部节点与会员)、converter、面板、证书、防火墙规则。
    当前备份目录记录在 /root/.last-fullbackup
EOF
     exit 1 ;;
esac
