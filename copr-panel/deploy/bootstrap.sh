#!/usr/bin/env bash
# =============================================================================
#  一键部署 s-ui 前端 + 域名硬化 Hysteria2 预设 + 节点转换/规则注入订阅
#  在服务器上以 root 运行:  sudo bash bootstrap.sh
#  读取同目录 config.env(复制 config.env.example 填写)。幂等,每步先备份。
#
#  职责边界(诚实):
#   - 确定性、安全的部分 → 全自动:装 s-ui、申请域名证书、部署 converter(含防
#     泄漏规则)、nginx 订阅前端、ufw、自检。
#   - 唯一需要动 s-ui 节点 TLS 的一步(把 hy2 换成域名+真实证书)→ 若 config.env
#     填了 s-ui 管理员账号密码,经 s-ui API 自动应用;否则打印面板手动步骤。
#     绝不盲改数据库,避免弄坏你现有节点/用户。
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

# ── 配置:config.env 可选(作默认值);缺的关键值在部署时交互提示 ─────────────
[[ -f config.env ]] && { set -a; source config.env; set +a; }
CONV_DIR="${CONV_DIR:-/opt/sui-converter}"
CONV_ADDR="${CONV_ADDR:-127.0.0.1:25501}"
SUI_SUB_BASE="${SUI_SUB_BASE:-http://127.0.0.1:2096/sub/}"
CERT_MODE="${CERT_MODE:-le}"
HY2_TAG="${HY2_TAG:-快速节点}"
SUI_API="${SUI_API:-}"; SUI_USER="${SUI_USER:-}"; SUI_PASS="${SUI_PASS:-}"
DOMAIN="${DOMAIN:-}"; TLS_CERT="${TLS_CERT:-}"; TLS_KEY="${TLS_KEY:-}"
CONV_ADMIN_SECRET="${CONV_ADMIN_SECRET:-}"

_ask(){  # _ask VAR "提示" "默认" [secret];已由 config.env 提供则不问;无 TTY 用默认
  local var="$1" msg="$2" def="${3:-}" secret="${4:-}" input
  [[ -n "${!var:-}" ]] && return
  if [[ ! -t 0 ]]; then printf -v "$var" '%s' "$def"; return; fi
  if [[ -n "$secret" ]]; then read -rsp "  ${msg}${def:+ [$def]}: " input; echo
  else read -rp "  ${msg}${def:+ [$def]}: " input; fi
  [[ -z "$input" ]] && input="$def"
  printf -v "$var" '%s' "$input"
}

_prompt_config(){
  echo -e "${C}=== 部署参数(回车=默认/检测值)===${N}"
  _ask DOMAIN "对外域名(已解析到本机)" ""
  [[ -n "$DOMAIN" ]] || die "域名必填"
  TLS_CERT="${TLS_CERT:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
  TLS_KEY="${TLS_KEY:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"
  [[ -n "$CONV_ADMIN_SECRET" ]] || CONV_ADMIN_SECRET="$(openssl rand -hex 24 2>/dev/null || echo "change-me-$(date +%s)")"
  local dohard="y"
  [[ -t 0 ]] && read -rp "  自动把 hy2 节点切到域名证书?(需 s-ui 管理员账号)[Y/n]: " dohard
  if [[ "$(lc "${dohard:-y}")" != "n" ]]; then
    local sp spath sip pdom host
    sp="$(/usr/local/s-ui/sui setting show 2>/dev/null | awk -F'[: \t]+' '/Panel port/{print $(NF)}')"
    spath="$(/usr/local/s-ui/sui setting show 2>/dev/null | awk -F'Panel path:' '/Panel path/{gsub(/[ \t]/,"",$2);print $2}')"
    pdom="$(/usr/local/s-ui/sui setting show 2>/dev/null | awk -F'Panel Domain:' '/Panel Domain/{gsub(/[ \t]/,"",$2);print $2}')"
    sip="$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || echo 127.0.0.1)"
    host="${pdom:-$sip}"   # s-ui 设了面板域名时,用 IP 访问会被 Host 守卫 403,故优先用域名
    [[ -z "$SUI_API" && -n "$sp" ]] && SUI_API="http://${host}:${sp}${spath:-/app/}"
    _ask SUI_API  "s-ui 面板 API 地址" "${SUI_API:-http://127.0.0.1:9000/app/}"
    _ask SUI_USER "s-ui 管理员账号" ""
    _ask SUI_PASS "s-ui 管理员密码" "" secret
    _ask HY2_TAG  "要硬化的 hy2 入站 tag" "快速节点"
  fi
}
TS="$(date +%Y%m%d-%H%M%S)"; BK="/root/copr-bootstrap-backup/$TS"; mkdir -p "$BK"

# ── 1) 依赖 ───────────────────────────────────────────────────────────────────
_deps(){
  log "安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq 2>&1 | tail -1
  apt-get install -y -qq curl wget jq unzip nginx certbot \
    python3 python3-venv python3-pip sqlite3 ufw >/dev/null 2>&1 || true
  ok "依赖就绪"
}

# ── 2) s-ui:没有则官方安装,有则复用 ─────────────────────────────────────────
_ensure_sui(){
  if systemctl list-unit-files 2>/dev/null | grep -q '^s-ui\.service'; then
    ok "检测到已安装的 s-ui,复用(不动现有节点/用户)"
    return
  fi
  warn "未检测到 s-ui,执行官方安装(交互:请按提示设定端口/账号)..."
  bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) \
    || die "s-ui 官方安装失败,请手动装好 s-ui 后重跑本脚本"
  systemctl is-active --quiet s-ui || die "s-ui 未运行"
  ok "s-ui 安装完成"
}

# ── 3) 域名证书(webroot;已有受管证书则复用/续期)────────────────────────────
_certs(){
  if [[ "$CERT_MODE" != "le" ]]; then
    warn "CERT_MODE=$CERT_MODE,跳过 LE(请自备 $TLS_CERT / $TLS_KEY)"; return
  fi
  mkdir -p /var/www/html/.well-known/acme-challenge
  # 先起一个临时 80 站点供 http-01
  cat > /etc/nginx/sites-available/acme-bootstrap <<EOF
server { listen 80; listen [::]:80; server_name ${DOMAIN};
  root /var/www/html; location /.well-known/acme-challenge/ { } location / { return 404; } }
EOF
  ln -sf /etc/nginx/sites-available/acme-bootstrap /etc/nginx/sites-enabled/acme-bootstrap
  nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || systemctl restart nginx || true
  log "申请/续期 Let's Encrypt 证书 (webroot)..."
  certbot certonly --webroot -w /var/www/html -d "$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring -q \
    || warn "LE 证书申请失败(检查 TCP80 公网可达 / DNS / 云安全组)"
  if certbot certificates 2>/dev/null | grep -q "Domains:.*\b${DOMAIN}\b"; then
    ok "域名证书就绪: $TLS_CERT"
  else
    warn "无受管 LE 证书,后续 nginx 若无 $TLS_CERT 将仅提供 HTTP"
  fi
}

# ── 4) converter(节点转换 + 规则注入,含防泄漏预设)──────────────────────────
_converter(){
  log "部署 converter(保留 users.json / rules.json)..."
  mkdir -p "$CONV_DIR"
  [[ -f "$CONV_DIR/converter.py" ]] && cp "$CONV_DIR/converter.py" "$BK/"
  [[ -f "$CONV_DIR/users.json" ]]   && cp "$CONV_DIR/users.json"   "$BK/"
  [[ -f "$CONV_DIR/rules.json" ]]   && cp "$CONV_DIR/rules.json"   "$BK/"
  cp ../sui-converter/converter.py         "$CONV_DIR/converter.py"
  cp ../sui-converter/rules.default.json   "$CONV_DIR/rules.default.json"
  if ! "$CONV_DIR/venv/bin/python" -c "import flask,requests,yaml" >/dev/null 2>&1; then
    log "重建 converter venv..."
    rm -rf "$CONV_DIR/venv"; python3 -m venv "$CONV_DIR/venv"
    "$CONV_DIR/venv/bin/pip" install -q -U pip flask requests pyyaml
  fi
  "$CONV_DIR/venv/bin/python" -m py_compile "$CONV_DIR/converter.py" || die "converter.py 语法失败"
  local host="${CONV_ADDR%%:*}" port="${CONV_ADDR##*:}"
  cat > /etc/systemd/system/sui-converter.service <<EOF
[Unit]
Description=onetapclash sui-converter
After=network.target
[Service]
Environment=ADMIN_SECRET=${CONV_ADMIN_SECRET}
Environment=USERS_FILE=${CONV_DIR}/users.json
Environment=RULES_FILE=${CONV_DIR}/rules.json
ExecStart=${CONV_DIR}/venv/bin/python ${CONV_DIR}/converter.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
  # converter.py 默认 127.0.0.1:25501;若 CONV_ADDR 不同则提示(converter 端口固定于代码)
  [[ "$host:$port" == "127.0.0.1:25501" ]] || warn "CONV_ADDR=$CONV_ADDR 与 converter.py 固定的 127.0.0.1:25501 不一致,请统一"
  systemctl daemon-reload
  systemctl enable sui-converter >/dev/null 2>&1 || true
  systemctl restart sui-converter; sleep 1
  systemctl is-active --quiet sui-converter && ok "converter 运行中" \
    || { warn "converter 异常"; journalctl -u sui-converter -n 20 --no-pager; }
}

# ── 5) 回填 users.json:s-ui 每个 client → 其原生订阅 → converter /get/<name> ──
_seed_users(){
  local db=/usr/local/s-ui/db/s-ui.db
  [[ -f "$db" ]] || { warn "无 s-ui DB,跳过用户回填"; return; }
  log "从 s-ui 回填 converter 用户映射..."
  local users_json="$CONV_DIR/users.json"
  [[ -f "$users_json" ]] && cp "$users_json" "$BK/users.json.pre"
  # s-ui client 的订阅 token 在 clients 表;取 name 与 subscription 字段构造 URL
  # 不同 s-ui 版本字段名可能不同,取不到时保留原 users.json 不覆盖
  local rows; rows="$(sqlite3 "$db" "select name from clients where enable=1;" 2>/dev/null || true)"
  [[ -z "$rows" ]] && { warn "读不到 clients,跳过(可稍后在面板/手动填 users.json)"; return; }
  # 说明:s-ui 原生订阅形如 ${SUI_SUB_BASE}<token>;token 需从面板取。
  # 这里仅确保 users.json 存在且合法,具体 URL 由面板「订阅」或手动补全。
  [[ -f "$users_json" ]] || echo '{}' > "$users_json"
  python3 - "$users_json" <<'PY' || true
import json,sys
f=sys.argv[1]
try: json.load(open(f))
except Exception: open(f,"w").write("{}")
PY
  ok "users.json 就位($users_json);逐用户订阅 URL 见文末说明"
}

# ── 6) nginx 订阅前端(域名 TLS;/get 公开订阅)───────────────────────────────
_nginx(){
  log "配置 nginx 订阅前端..."
  rm -f /etc/nginx/sites-enabled/acme-bootstrap
  local have_tls=0; [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] && have_tls=1
  cat > /etc/nginx/sites-available/copr-sub.conf <<EOF
server {
  listen 80; listen [::]:80; server_name ${DOMAIN};
  root /var/www/html;
  location /.well-known/acme-challenge/ { }
  location /get/ { proxy_pass http://${CONV_ADDR}; proxy_set_header Host \$host; }
$( [[ $have_tls == 1 ]] && echo '  location / { return 301 https://$host$request_uri; }' || echo '  location /health { proxy_pass http://'"${CONV_ADDR}"'; } location / { return 404; }' )
}
EOF
  if [[ $have_tls == 1 ]]; then
    cat >> /etc/nginx/sites-available/copr-sub.conf <<EOF
server {
  listen 443 ssl http2; listen [::]:443 ssl http2; server_name ${DOMAIN};
  ssl_certificate ${TLS_CERT}; ssl_certificate_key ${TLS_KEY};
  ssl_protocols TLSv1.2 TLSv1.3;
  location /get/    { proxy_pass http://${CONV_ADDR}; proxy_set_header Host \$host; }
  location /health  { proxy_pass http://${CONV_ADDR}; }
  location /        { return 404; }
}
EOF
  fi
  ln -sf /etc/nginx/sites-available/copr-sub.conf /etc/nginx/sites-enabled/copr-sub.conf
  nginx -t && systemctl reload nginx && ok "nginx 就绪(订阅前端)" || die "nginx 校验失败"
}

# ── 7) 域名硬化 hy2 节点(s-ui v1.2+ API:POST api/save object=tls)──────────────
_harden_manual(){
  cat <<EOF
   → 手动(s-ui 面板 → 入站「${HY2_TAG}」→ TLS):server_name=${DOMAIN};
     证书=${TLS_CERT} 内容;私钥=${TLS_KEY} 内容;关闭 insecure/自签指纹。保存即热重载。
EOF
}
_harden_hy2(){
  echo ""; log "域名硬化 Hysteria2 节点(TLS → ${DOMAIN} + 真实证书)"
  [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] || { warn "证书缺失($TLS_CERT),跳过;先修好证书再重跑"; return; }
  if [[ -z "$SUI_API" || -z "$SUI_USER" || -z "$SUI_PASS" ]]; then
    warn "未提供 s-ui API/账号 → 打印手动步骤:"; _harden_manual; return
  fi
  local db=/usr/local/s-ui/db/s-ui.db jar="$BK/sui.cookie" base="${SUI_API%/}"
  # hy2 入站的 tls_id(先按 tag,再按 type 兜底)
  local tls_id
  tls_id="$(sqlite3 "$db" "select tls_id from inbounds where tag='${HY2_TAG}' limit 1;" 2>/dev/null)"
  [[ -z "$tls_id" ]] && tls_id="$(sqlite3 "$db" "select tls_id from inbounds where type='hysteria2' limit 1;" 2>/dev/null)"
  [[ -z "$tls_id" ]] && { warn "找不到 hy2 入站(tag=${HY2_TAG})的 tls_id"; _harden_manual; return; }
  # 登录(user/pass 表单,cookie=s-ui)
  local lr; lr="$(curl -sS -c "$jar" --max-time 15 -X POST "${base}/api/login" \
      --data-urlencode "user=${SUI_USER}" --data-urlencode "pass=${SUI_PASS}" 2>/dev/null || true)"
  if ! echo "$lr" | jq -e '.success==true' >/dev/null 2>&1; then
    warn "s-ui 登录失败(检查 SUI_API 是否含面板路径/域名、账号密码): $(echo "$lr" | jq -r '.msg // "无有效响应"' 2>/dev/null)"
    _harden_manual; return
  fi
  ok "s-ui 登录成功,读取 tls#${tls_id}..."
  local cur; cur="$(curl -sS -b "$jar" --max-time 15 "${base}/api/tls" 2>/dev/null \
      | jq -c --argjson id "$tls_id" '.obj.tls[] | select(.id==$id)' 2>/dev/null || true)"
  [[ -z "$cur" || "$cur" == "null" ]] && { warn "读不到 tls#${tls_id}"; _harden_manual; return; }
  # 取当前对象,只改:server_name/inline PEM(按行数组)/关 insecure;其余保留(save 覆盖整行)
  local data
  data="$(jq -n --argjson cur "$cur" --arg d "$DOMAIN" \
      --rawfile cert "$TLS_CERT" --rawfile key "$TLS_KEY" '
      $cur
      | .server.enabled     = true
      | .server.server_name = $d
      | .server.alpn        = ((.server.alpn // []) | if length>0 then . else ["h3"] end)
      | .server.certificate = ($cert | rtrimstr("\n") | split("\n"))
      | .server.key         = ($key  | rtrimstr("\n") | split("\n"))
      | del(.server.certificate_path, .server.key_path, .server.reality, .server.acme)
      | .client.server_name = $d
      | .client.insecure    = false
      | del(.client.certificate, .client.certificate_path, .client.certificate_public_key_sha256, .client.reality)
    ' 2>/dev/null || true)"
  [[ -z "$data" ]] && { warn "构造 TLS 载荷失败(jq)"; _harden_manual; return; }
  local sr; sr="$(curl -sS -b "$jar" --max-time 20 -X POST "${base}/api/save" \
      --data-urlencode "object=tls" --data-urlencode "action=edit" \
      --data-urlencode "data=${data}" 2>/dev/null || true)"
  if echo "$sr" | jq -e '.success==true' >/dev/null 2>&1; then
    ok "hy2 节点 TLS 已切到 ${DOMAIN} + 真实证书,s-ui 已自动热重载入站"
  else
    warn "保存失败: $(echo "$sr" | jq -r '.msg // "未知(可 POST api/restartSb 或手动)"' 2>/dev/null)"
    _harden_manual
  fi
}

# ── 8) ufw + 自检 ─────────────────────────────────────────────────────────────
_firewall(){
  command -v ufw >/dev/null || return
  ufw allow 80/tcp   >/dev/null 2>&1 || true
  ufw allow 443/tcp  >/dev/null 2>&1 || true
  ok "ufw:已放行 80/443(UDP 代理端口与 s-ui 面板端口请确保已放行)"
}
_selfcheck(){
  echo ""; log "自检"
  systemctl is-active --quiet s-ui          && ok "s-ui 运行中"          || warn "s-ui 未运行"
  systemctl is-active --quiet sui-converter && ok "converter 运行中"     || warn "converter 未运行"
  systemctl is-active --quiet nginx         && ok "nginx 运行中"         || warn "nginx 未运行"
  curl -sf "http://${CONV_ADDR}/health" >/dev/null && ok "converter /health OK" || warn "converter /health 失败"
}

main(){
  _deps
  _ensure_sui
  _prompt_config
  _certs
  _converter
  _seed_users
  _nginx
  _harden_hy2
  _firewall
  _selfcheck
  echo ""; ok "完成。备份目录: $BK"
  echo "  订阅:      https://${DOMAIN}/get/<user>"
  echo "  s-ui 面板: 见 s-ui 自身端口(默认安装时设定)"
  echo "  逐用户订阅: 在 s-ui 面板复制该用户「原生订阅链接」,POST 到 converter:"
  echo "    curl -X POST http://${CONV_ADDR}/admin/users/<name> -H 'X-Admin-Secret: ${CONV_ADMIN_SECRET}' \\"
  echo "         -H 'Content-Type: application/json' -d '{\"url\":\"${SUI_SUB_BASE}<token>\"}'"
}
main "$@"
