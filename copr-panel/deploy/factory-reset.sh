#!/usr/bin/env bash
# =============================================================================
# factory-reset.sh — 把本机恢复成「没装过 onetapclash」的状态
#
#   ⚠️ 破坏性:会删掉 s-ui(含所有节点与会员)、converter、面板、防火墙规则。
#      证书保留:Let's Encrypt 同域名每周最多签 5 张,反复重置验证很快就签不出来。
#      跑之前先备份;脚本自己也会备份一份到 /root/onetap-fullbackup-<时间戳>。
#
#   用途: ① 验证 bootstrap.sh 的全新安装路径 ② 想推倒重来
#   怎么跑: sudo bash factory-reset.sh --yes
#   还原:  sudo bash factory-reset.sh --restore <备份目录>
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
CONV_DIR="${CONV_DIR:-/opt/sui-converter}"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){  echo -e "\033[32m[OK]\033[0m $*"; }

_backup(){
  local bk="/root/onetap-fullbackup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bk"
  [[ -d /usr/local/s-ui/db ]] && cp -a /usr/local/s-ui/db "$bk/sui-db"
  local f
  for f in users.json rules.json; do
    [[ -f "$CONV_DIR/$f" ]] && cp -a "$CONV_DIR/$f" "$bk/"
  done
  [[ -d /etc/letsencrypt ]] && tar czf "$bk/letsencrypt.tgz" -C /etc letsencrypt
  [[ -f config.env ]] && cp config.env "$bk/"
  echo "$bk" > /root/.last-fullbackup
  BACKUP_DIR="$bk"
  ok "已备份 → $bk"
}

_restore(){
  local bk="${1:?用法: factory-reset.sh --restore <备份目录>}"
  [[ -d "$bk" ]] || { echo "备份目录不存在: $bk"; exit 1; }
  log "还原 $bk ..."
  systemctl stop s-ui sui-converter 2>/dev/null || true
  # _wipe 删掉了整个目录,还原前得先建回来;cp 失败必须报错,不能说「已还原」
  if [[ -d "$bk/sui-db" ]]; then mkdir -p /usr/local/s-ui/db; cp -a "$bk/sui-db/." /usr/local/s-ui/db/; fi
  if [[ -f "$bk/letsencrypt.tgz" ]]; then tar xzf "$bk/letsencrypt.tgz" -C /etc; fi
  mkdir -p "$CONV_DIR"
  local f
  for f in users.json rules.json; do
    if [[ -f "$bk/$f" ]]; then cp -a "$bk/$f" "$CONV_DIR/"; fi
  done
  systemctl start s-ui sui-converter 2>/dev/null || true
  ok "已还原。建议再跑一次 bootstrap.sh 让 nginx/防火墙对齐。"
}

_wipe(){
  # 先停再备份:s-ui 运行中拷 SQLite 可能拷到写了一半的库
  log "停止服务..."
  systemctl stop s-ui sui-converter nginx 2>/dev/null || true
  _backup
  log "撤端口跳跃规则(v4/v6,只删我们加的,不清整条链)..."
  HOP_ENABLE=no bash ensure-hopping.sh
  log "移除服务..."
  systemctl disable s-ui sui-converter onetap-healthcheck.timer 2>/dev/null || true
  rm -rf /usr/local/s-ui "$CONV_DIR" /opt/copr-panel
  rm -f  /etc/systemd/system/s-ui.service /etc/systemd/system/sui-converter.service
  rm -f  /etc/systemd/system/onetap-*.service /etc/systemd/system/onetap-*.timer
  rm -f  /etc/systemd/system/*.service.d/10-autorestart.conf
  rm -f  /usr/local/bin/onetap-healthcheck /usr/bin/s-ui
  rm -f  /etc/letsencrypt/renewal-hooks/deploy/10-reload-onetap.sh
  rm -rf /etc/onetap
  rm -f  /etc/nginx/sites-enabled/* /etc/nginx/sites-available/copr* /etc/nginx/sites-available/acme-bootstrap
  rm -f  /etc/sysctl.d/99-onetap.conf
  log "清防火墙..."
  ufw --force reset >/dev/null 2>&1 || true
  ufw --force disable >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl start nginx 2>/dev/null || true
  ok "已恢复到未安装状态(证书保留)。备份在 $BACKUP_DIR。现在可以跑: sudo bash bootstrap.sh"
}

case "${1:-}" in
  --yes)     _wipe ;;
  --restore) _restore "${2:-}" ;;
  *) cat <<EOF
用法:
  sudo bash factory-reset.sh --yes                  # 清空(会先自动备份)
  sudo bash factory-reset.sh --restore <备份目录>    # 从备份还原

⚠️  --yes 会删除 s-ui(含全部节点与会员)、converter、面板、防火墙规则(证书保留)。
    当前备份目录记录在 /root/.last-fullbackup
EOF
     exit 1 ;;
esac
