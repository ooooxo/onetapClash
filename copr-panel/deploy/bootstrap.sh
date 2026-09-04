#!/usr/bin/env bash
# =============================================================================
#  onetapclash 一键部署 —— 跑完就能用,你只需要再手动加会员。
#
#  用法:  sudo bash bootstrap.sh                # 全量:从零到可用
#          sudo bash bootstrap.sh --update       # 只更新面板/converter/nginx(日常发版)
#          sudo bash bootstrap.sh --panel-only   # 只更新面板静态包 + nginx
#          (读同目录 config.env;缺的关键值会交互问,无 TTY 时用默认值)
#
#  跑完你会得到:
#    s-ui 后端(账号已设、监听已修对)+ Let's Encrypt 证书 + Hysteria2 与
#    VLESS-Reality 两个能用的节点 + converter 订阅(防泄漏/大陆分流)+
#    Vue 面板(HTTPS 同源反代)+ fail2ban/ufw + 开机自启与崩溃自愈。
#
#  幂等:每一步都可重跑,已存在的复用,不会重装 s-ui、不会覆盖已有节点/会员。
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' N='\033[0m'
log(){ echo -e "${C}[*]${N} $*"; }
ok(){  echo -e "${G}[OK]${N} $*"; }
warn(){ echo -e "${Y}[!]${N} $*"; }
die(){ echo -e "${R}[ERR]${N} $*" >&2; exit 1; }
lc(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请用 root 运行: sudo bash bootstrap.sh"

. ./_common.sh
load_config_env config.env

MODE=full
case "${1:-}" in
  --update)     MODE=update ;;
  --panel-only) MODE=panel ;;
  "")           ;;
  *)            die "未知参数: $1(可用:--update / --panel-only)" ;;
esac
# ── 参数(config.env 可覆盖;这里是唯一的默认值来源)─────────────────────────
CONV_DIR="${CONV_DIR:-/opt/sui-converter}"
CONV_ADDR="${CONV_ADDR:-127.0.0.1:25501}"
CERT_MODE="${CERT_MODE:-le}"
DOMAIN="${DOMAIN:-}"; TLS_CERT="${TLS_CERT:-}"; TLS_KEY="${TLS_KEY:-}"; TLS_PORT="${TLS_PORT:-443}"
CONV_ADMIN_SECRET="${CONV_ADMIN_SECRET:-}"
PANEL="${PANEL:-yes}"
PANEL_DIR="${PANEL_DIR:-/opt/copr-panel/web}"
PANEL_PATH="${PANEL_PATH:-/panel/}"
SUI_USER="${SUI_USER:-}"; SUI_PASS="${SUI_PASS:-}"
SUI_PORT="${SUI_PORT:-2095}"; SUI_BASE="${SUI_BASE:-/app/}"
SUI_SUB_PORT="${SUI_SUB_PORT:-2096}"; SUI_SUB_PATH="${SUI_SUB_PATH:-/sub/}"
SUI_ADDR="${SUI_ADDR:-127.0.0.1:${SUI_PORT}}"
SUI_SUB_BASE="${SUI_SUB_BASE:-http://127.0.0.1:${SUI_SUB_PORT}${SUI_SUB_PATH}}"
HY2_TAG="${HY2_TAG:-quick}"; HY2_PORT="${HY2_PORT:-443}"
REALITY_TAG="${REALITY_TAG:-reality}"; REALITY_PORT="${REALITY_PORT:-8443}"
REALITY_DEST="${REALITY_DEST:-www.apple.com}"; WANT_REALITY="${WANT_REALITY:-yes}"
# 线路稳定/速率(见 ensure-hopping.sh 与 converter 顶部注释)
HOP_ENABLE="${HOP_ENABLE:-yes}"
HY2_HOP_PORTS="${HY2_HOP_PORTS:-20000-25000}"   # UDP 端口段,全部重定向到 HY2_PORT
HY2_HOP_INTERVAL="${HY2_HOP_INTERVAL:-30}"
# Brutal 固定速率:两个都填才启用,否则用 BBR。
# 这里【不做自动实测】—— Brutal 要的是「客户端↔服务器」的实际吞吐(比如广东→东京),
# 而在服务器上只能测到「服务器出口」(东京→东京可以跑到 500Mbps),两者毫无关系。
# 按服务器出口设 Brutal 会严重高估;Brutal 不退让,高估=持续丢包,比不开还糟。
# 正确做法:用客户端实测的稳定速率的 ~80% 填在这里。
HY2_UP_MBPS="${HY2_UP_MBPS:-}"
HY2_DOWN_MBPS="${HY2_DOWN_MBPS:-}"
HY2_OBFS="${HY2_OBFS:-yes}"        # salamander 混淆,默认开
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"
HARDEN="${HARDEN:-yes}"            # fail2ban + ufw + sshd 公钥登录
SSH_PORT="${SSH_PORT:-22}"

_ask(){  # _ask VAR "提示" "默认" [secret];已有值不问;无 TTY 用默认
  local var="$1" msg="$2" def="${3:-}" secret="${4:-}" input
  [[ -n "${!var:-}" ]] && return
  if [[ ! -t 0 ]]; then printf -v "$var" '%s' "$def"; return; fi
  if [[ -n "$secret" ]]; then read -rsp "  ${msg}${def:+ [$def]}: " input; echo
  else read -rp "  ${msg}${def:+ [$def]}: " input; fi
  [[ -z "$input" ]] && input="$def"
  printf -v "$var" '%s' "$input"
}

_prompt_config(){
  echo -e "${C}=== 部署参数(回车=默认)===${N}"
  _ask DOMAIN   "对外域名(必须已解析到本机)" ""
  [[ -n "$DOMAIN" ]] || die "域名必填"
  # s-ui 账号密码是必需的:后面要用它调 API 自动开节点
  # 只有全量部署才需要 s-ui 账号密码(要用它调 API 装节点);更新模式不碰 s-ui
  if [[ "$MODE" == "full" ]]; then
    _ask SUI_USER "s-ui 管理员账号" "admin"
    _ask SUI_PASS "s-ui 管理员密码(新装则按此设定)" "" secret
    [[ -n "$SUI_PASS" ]] || die "密码必填(自动开节点要用它调 s-ui API)"
  fi
  TLS_CERT="${TLS_CERT:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
  TLS_KEY="${TLS_KEY:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"
  [[ -n "$CONV_ADMIN_SECRET" ]] || CONV_ADMIN_SECRET="$(openssl rand -hex 24)"
}

TS="$(date +%Y%m%d-%H%M%S)"; BK="/root/copr-bootstrap-backup/$TS"; mkdir -p "$BK"

_deps(){
  log "安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq curl wget jq unzip nginx certbot gettext-base \
    python3 python3-venv python3-pip sqlite3 ufw fail2ban >/dev/null 2>&1 || true
  ok "依赖就绪"
}

# ── s-ui:装 + 配(账号/端口/webListen)——细节全在 ensure-sui.sh ──────────────
_sui(){
  DOMAIN="$DOMAIN" SUI_USER="$SUI_USER" SUI_PASS="$SUI_PASS" SUI_PORT="$SUI_PORT" \
  SUI_BASE="$SUI_BASE" SUI_SUB_PORT="$SUI_SUB_PORT" SUI_SUB_PATH="$SUI_SUB_PATH" \
    bash ensure-sui.sh || die "s-ui 准备失败"
}

# ── 证书(webroot;已有受管证书则续期复用)───────────────────────────────────
_certs(){
  [[ "$CERT_MODE" == "le" ]] || { warn "CERT_MODE=$CERT_MODE,跳过 LE"; return; }
  mkdir -p /var/www/certbot/.well-known/acme-challenge
  cat > /etc/nginx/sites-available/acme-bootstrap <<EOF
server { listen 80; listen [::]:80; server_name ${DOMAIN};
  location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; } location / { return 404; } }
EOF
  ln -sf /etc/nginx/sites-available/acme-bootstrap /etc/nginx/sites-enabled/acme-bootstrap
  # 旧站点必须先摘掉:它引用的证书此刻可能不存在(首次签发/证书被删),
  # 留着会让 nginx -t 失败 → nginx 起不来 → webroot 验证拿不到 token → 签发失败。
  # _nginx 紧接着会重新生成并启用,不会丢配置。
  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/copr.conf /etc/nginx/sites-enabled/copr-sub.conf
  nginx -t >/dev/null 2>&1 && { systemctl reload nginx 2>/dev/null || systemctl restart nginx; } || systemctl restart nginx || true
  log "申请/续期 Let's Encrypt 证书..."
  certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring -q \
    || warn "LE 申请失败(检查 TCP80 公网可达 / DNS / 云安全组)"
  [[ -f "$TLS_CERT" ]] && ok "证书就绪: $TLS_CERT" || warn "无证书,后续只能 HTTP,且 hy2 节点开不了"
}

# ── converter(订阅转换 + 分流/防泄漏注入)──────────────────────────────────
_converter(){
  log "部署 converter(保留 users.json / rules.json)..."
  # 没开端口跳跃就不要往订阅里写 ports,否则客户端会往没放行的端口段发包
  HOP_PORTS_EFF=""; [[ "$(lc "$HOP_ENABLE")" != "no" ]] && HOP_PORTS_EFF="$HY2_HOP_PORTS"
  mkdir -p "$CONV_DIR"
  for f in converter.py users.json rules.json; do
    [[ -f "$CONV_DIR/$f" ]] && cp "$CONV_DIR/$f" "$BK/"
  done
  cp ../sui-converter/converter.py       "$CONV_DIR/converter.py"
  cp ../sui-converter/rules.default.json "$CONV_DIR/rules.default.json"
  if ! "$CONV_DIR/venv/bin/python" -c "import flask,requests,yaml" >/dev/null 2>&1; then
    log "重建 converter venv..."
    rm -rf "$CONV_DIR/venv"; python3 -m venv "$CONV_DIR/venv"
    "$CONV_DIR/venv/bin/pip" install -q -U pip flask requests pyyaml
  fi
  "$CONV_DIR/venv/bin/python" -m py_compile "$CONV_DIR/converter.py" || die "converter.py 语法失败"
  cat > /etc/systemd/system/sui-converter.service <<EOF
[Unit]
Description=onetapclash sui-converter
After=network.target
[Service]
Environment=ADMIN_SECRET=${CONV_ADMIN_SECRET}
Environment=USERS_FILE=${CONV_DIR}/users.json
Environment=RULES_FILE=${CONV_DIR}/rules.json
Environment=SUI_SUB_BASE=${SUI_SUB_BASE}
Environment=HY2_HOP_PORTS=${HOP_PORTS_EFF}
Environment=HY2_HOP_INTERVAL=${HY2_HOP_INTERVAL}
Environment=HY2_UP_MBPS=${HY2_UP_MBPS}
Environment=HY2_DOWN_MBPS=${HY2_DOWN_MBPS}
ExecStart=${CONV_DIR}/venv/bin/python ${CONV_DIR}/converter.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
  [[ -f "$CONV_DIR/users.json" ]] || echo '{}' > "$CONV_DIR/users.json"
  systemctl daemon-reload
  systemctl enable sui-converter >/dev/null 2>&1 || true
  systemctl restart sui-converter; sleep 1
  systemctl is-active --quiet sui-converter && ok "converter 运行中" \
    || { warn "converter 异常"; journalctl -u sui-converter -n 20 --no-pager; }
}

# ── Vue 面板(预编译 dist 随仓库带,服务器免 node)───────────────────────────
_panel(){
  [[ "$(lc "$PANEL")" == "no" ]] && { warn "PANEL=no,跳过面板"; return; }
  local src; src="$(pwd)/webdist"
  [[ -f "$src/index.html" ]] || { warn "缺预编译面板 $src → 只上订阅"; PANEL="no"; return; }
  log "部署 Vue 面板..."
  mkdir -p "$PANEL_DIR"; rm -rf "${PANEL_DIR:?}/"* 2>/dev/null || true
  cp -r "$src/." "$PANEL_DIR/"; chown -R root:root "$PANEL_DIR"
  ok "Vue 面板就位: $PANEL_DIR"
}

_nginx(){
  log "配置 nginx..."
  rm -f /etc/nginx/sites-enabled/acme-bootstrap /etc/nginx/sites-enabled/default
  mkdir -p /var/www/certbot
  local have_tls=0; [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] && have_tls=1
  if [[ "$(lc "$PANEL")" != "no" && -f "$PANEL_DIR/index.html" && $have_tls == 1 ]]; then
    [[ -f nginx-copr-tls.conf.template ]] || die "缺 nginx-copr-tls.conf.template"
    export DOMAIN PANEL_PATH PANEL_DIR SUI_ADDR SUI_BASE CONV_ADDR CONV_ADMIN_SECRET TLS_PORT TLS_CERT TLS_KEY
    envsubst '$DOMAIN $PANEL_PATH $PANEL_DIR $SUI_ADDR $SUI_BASE $CONV_ADDR $CONV_ADMIN_SECRET $TLS_PORT $TLS_CERT $TLS_KEY' \
      < nginx-copr-tls.conf.template > /etc/nginx/sites-available/copr.conf
    rm -f /etc/nginx/sites-enabled/copr-sub.conf
    ln -sf /etc/nginx/sites-available/copr.conf /etc/nginx/sites-enabled/copr.conf
  else
    warn "无面板/无证书 → 仅订阅前端(HTTP)"
    rm -f /etc/nginx/sites-enabled/copr.conf
    cat > /etc/nginx/sites-available/copr-sub.conf <<EOF
server {
  listen 80; listen [::]:80; server_name ${DOMAIN};
  location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; }
  location /get/  { proxy_pass http://${CONV_ADDR}; proxy_set_header Host \$host; }
  location /health { proxy_pass http://${CONV_ADDR}; }
  location /      { return 404; }
}
EOF
    ln -sf /etc/nginx/sites-available/copr-sub.conf /etc/nginx/sites-enabled/copr-sub.conf
  fi
  nginx -t && { systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx; ok "nginx 就绪"; } || die "nginx 校验失败"
}

# ── 端口跳跃:抗运营商对固定 UDP 端口的 QoS ──────────────────────────────────
_hopping(){
  HY2_PORT="$HY2_PORT" HY2_HOP_PORTS="$HY2_HOP_PORTS" HOP_ENABLE="$HOP_ENABLE" \
    bash ensure-hopping.sh || warn "端口跳跃配置失败"
}

# ── 自动开节点:没有入站 = 会员链接必死,这步是「一键可用」的关键 ─────────────
_nodes(){
  [[ -f "$TLS_CERT" ]] || { warn "没有证书,跳过自动开节点"; return; }
  DOMAIN="$DOMAIN" SUI_ADDR="$SUI_ADDR" SUI_BASE="$SUI_BASE" SUI_USER="$SUI_USER" SUI_PASS="$SUI_PASS" \
  HY2_TAG="$HY2_TAG" HY2_PORT="$HY2_PORT" REALITY_TAG="$REALITY_TAG" REALITY_PORT="$REALITY_PORT" \
  REALITY_DEST="$REALITY_DEST" WANT_REALITY="$WANT_REALITY" TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" \
  HY2_OBFS="$HY2_OBFS" HY2_OBFS_PASSWORD="$HY2_OBFS_PASSWORD" \
  HY2_UP_MBPS="$HY2_UP_MBPS" HY2_DOWN_MBPS="$HY2_DOWN_MBPS" \
    bash ensure-nodes.sh || warn "自动开节点失败,可稍后单独重跑 ensure-nodes.sh"
}

# ── 回填 converter 用户映射(有会员时)──────────────────────────────────────
_seed_users(){
  local db=/usr/local/s-ui/db/s-ui.db users_json="$CONV_DIR/users.json"
  [[ -f "$db" ]] || return
  [[ -f "$users_json" ]] && cp "$users_json" "$BK/users.json.pre"
  local map
  map="$(sqlite3 "$db" "select name from clients where enable=1;" 2>/dev/null \
    | jq -R -s --arg base "${SUI_SUB_BASE%/}/" '
        split("\n") | map(select(length>0))
        | reduce .[] as $n ({}; . + { ($n): { url: ($base + $n) } })' 2>/dev/null || true)"
  # converter 现在会自动回源 s-ui 原生订阅,users.json 只是给自定义映射用;空了也不影响
  [[ -n "$map" && "$map" != "null" ]] && { echo "$map" > "$users_json"; ok "users.json 回填 $(echo "$map" | jq 'length') 人"; }
  [[ -f "$users_json" ]] || echo '{}' > "$users_json"
}

_services(){ CONV_ADDR="$CONV_ADDR" SUI_ADDR="$SUI_ADDR" bash ensure-services.sh || warn "自启/自愈配置失败"; }

_harden(){
  [[ "$(lc "$HARDEN")" == "no" ]] && { warn "HARDEN=no,跳过安全加固"; return; }
  # 不放行 SUI_PORT / SUI_SUB_PORT:s-ui 原生面板没有 TLS,明文暴露=管理员密码裸奔。
  # 它已由 nginx 经 HTTPS 反代到 ${SUI_BASE};订阅也走 443 的 /get/。本机回环不受防火墙限制。
  local utcp="${SSH_PORT},80,${TLS_PORT}" uudp=""
  case "$(lc "$WANT_REALITY")" in no|0|false) :;; *) utcp="${utcp},${REALITY_PORT}";; esac
  uudp="${HY2_PORT}"
  SSH_PORT="$SSH_PORT" OPEN_TCP="$utcp" OPEN_UDP="$uudp" \
  DISABLE_PASSWORD_AUTH=no bash harden.sh || warn "加固失败"
}

_selfcheck(){
  echo ""; log "自检"
  local bad=0
  systemctl is-active --quiet s-ui          && ok "s-ui 运行中"      || { warn "s-ui 未运行"; bad=1; }
  systemctl is-active --quiet sui-converter && ok "converter 运行中" || { warn "converter 未运行"; bad=1; }
  systemctl is-active --quiet nginx         && ok "nginx 运行中"     || { warn "nginx 未运行"; bad=1; }
  curl -sf "http://${CONV_ADDR}/health" >/dev/null && ok "converter /health OK" || { warn "converter /health 失败"; bad=1; }
  # 这条最关键:nginx 就是这样访问 s-ui 的,不通 = 面板报「后端不可达」
  local code; code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Host: ${DOMAIN}" "http://${SUI_ADDR}${SUI_BASE}" || true)"
  [[ "$code" =~ ^(200|307|302)$ ]] && ok "s-ui 回环可达(HTTP $code)" || { warn "s-ui 回环不可达(HTTP ${code:-000})→ 面板会报后端不可达"; bad=1; }
  local n; n="$(sqlite3 /usr/local/s-ui/db/s-ui.db 'select count(*) from inbounds;' 2>/dev/null || echo 0)"
  [[ "$n" -gt 0 ]] && ok "入站节点 $n 个" || { warn "没有入站节点 —— 新建会员会拿到不可用链接"; bad=1; }
  return $bad
}

main(){
  _prompt_config
  # 日常发版只动我们自己的三块,不碰 s-ui / 证书 / 防火墙 / 节点
  if [[ "$MODE" == "panel" ]]; then
    _panel; _nginx; ok "面板已更新"; return
  fi
  if [[ "$MODE" == "update" ]]; then
    HOP_PORTS_EFF=""; [[ "$(lc "$HOP_ENABLE")" != "no" ]] && HOP_PORTS_EFF="$HY2_HOP_PORTS"
    _converter; _panel; _nginx; _selfcheck || warn "自检有告警"; ok "更新完成"; return
  fi
  _deps
  _sui
  _certs
  _converter
  _panel
  _nginx
  _harden     # 必须在 _nodes 之前:harden.sh 会 ufw --force reset,放在后面会冲掉节点端口
  _nodes
  _hopping
  _seed_users
  _services
  _selfcheck || warn "自检有告警,见上"
  local div="────────────────────────────────────────────────────────"
  local ps=""; [[ "$TLS_PORT" != "443" ]] && ps=":${TLS_PORT}"
  echo ""; echo -e "${C}${div}${N}"
  echo -e "  ${G}▍面板(浏览器打开,登录=s-ui 账号密码):${N} https://${DOMAIN}${ps}${PANEL_PATH}"
  echo -e "  ${G}▍s-ui 原面板(深水区):${N} http://${DOMAIN}:${SUI_PORT}${SUI_BASE}"
  echo -e "  ${G}▍订阅地址:${N} https://${DOMAIN}${ps}/get/<会员名>"
  echo -e "  ${G}▍converter 管理密钥(请保存):${N} ${CONV_ADMIN_SECRET}"
  echo -e "  ${G}▍下一步:${N} 打开面板 →「会员」→ 新增会员,把订阅地址发给他即可。"
  echo -e "${C}${div}${N}"
  echo -e "  备份目录: $BK"
}
main "$@"
