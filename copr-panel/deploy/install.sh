#!/usr/bin/env bash
# copr-panel 安装器 —— 幂等、可复用、每步先备份。在服务器上以 root 运行。
# 用法: sudo bash install.sh            (读同目录 config.env)
#       sudo bash install.sh --panel-only  (只更新面板,不碰 converter)
set -euo pipefail
cd "$(dirname "$0")"

[[ -f config.env ]] || { echo "缺 config.env(复制 config.env.example 并填写)"; exit 1; }
set -a; source config.env; set +a
: "${DOMAIN:?}" "${PANEL_DIR:?}" "${PANEL_PATH:?}" "${SUI_ADDR:?}" "${SUI_BASE:?}" "${CONV_DIR:?}" "${CONV_ADDR:?}" "${CONV_ADMIN_SECRET:?}"
export DOMAIN PANEL_DIR PANEL_PATH SUI_ADDR SUI_BASE CONV_DIR CONV_ADDR CONV_ADMIN_SECRET
PANEL_ONLY=0; [[ "${1:-}" == "--panel-only" ]] && PANEL_ONLY=1
TS="$(date +%Y%m%d-%H%M%S)"; BK="/root/copr-panel-backup/$TS"; mkdir -p "$BK"
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){ echo -e "\033[32m[OK]\033[0m $*"; }

# ── 1) 面板静态包(dist 由 push.sh 已上传到 PANEL_DIR)──────────────────────
[[ -f "$PANEL_DIR/index.html" ]] || { echo "PANEL_DIR 无 index.html,请先 push.sh 上传 dist"; exit 1; }
chown -R root:root "$PANEL_DIR"   # tar 可能带来外部 uid,归一化,保证 nginx 可读
ok "面板静态包就位: $PANEL_DIR"

if [[ "$PANEL_ONLY" == "0" ]]; then
  # ── 2) converter(壳层 2.0)—— 保留 users.json / rules.json ───────────────
  log "部署 converter(保留用户与规则)..."
  mkdir -p "$CONV_DIR"
  [[ -f "$CONV_DIR/converter.py" ]] && cp "$CONV_DIR/converter.py" "$BK/converter.py.bak"
  [[ -f "$CONV_DIR/users.json" ]] && cp "$CONV_DIR/users.json" "$BK/users.json.bak"
  [[ -f "$CONV_DIR/rules.json" ]] && cp "$CONV_DIR/rules.json" "$BK/rules.json.bak"
  cp ../sui-converter/converter.py "$CONV_DIR/converter.py"
  cp ../sui-converter/rules.default.json "$CONV_DIR/rules.default.json"
  # venv + 依赖
  apt-get install -y -qq python3 python3-venv >/dev/null 2>&1 || true
  # venv 不存在或依赖缺失(如系统 python 升级后损坏)→ 重建
  if ! "$CONV_DIR/venv/bin/python" -c "import flask,requests,yaml" >/dev/null 2>&1; then
    log "重建 converter venv..."
    rm -rf "$CONV_DIR/venv"; python3 -m venv "$CONV_DIR/venv"
    "$CONV_DIR/venv/bin/pip" install -q -U pip flask requests pyyaml
  fi
  "$CONV_DIR/venv/bin/python" -m py_compile "$CONV_DIR/converter.py" || { echo "converter.py 语法失败"; exit 1; }
  # systemd
  envsubst < sui-converter.service.template > /etc/systemd/system/sui-converter.service
  systemctl daemon-reload
  ok "converter 就绪"
fi

# ── 3) nginx(备份旧站点,生成统一 conf,校验后 reload)──────────────────────
log "配置 nginx(单一登录=s-ui,converter admin 走 auth_request 会话鉴权)..."
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
[[ -f /etc/nginx/sites-enabled/sub_converter.conf ]] && cp /etc/nginx/sites-enabled/sub_converter.conf "$BK/"
for f in /etc/nginx/sites-enabled/copr.conf; do [[ -f "$f" ]] && cp "$f" "$BK/"; done
TPL=nginx-copr.conf.template
VARS='$DOMAIN $PANEL_DIR $PANEL_PATH $SUI_ADDR $SUI_BASE $CONV_ADDR $CONV_ADMIN_SECRET'
if [[ -n "${TLS_CERT:-}" && -f "${TLS_CERT:-/nonexist}" ]]; then
  TPL=nginx-copr-tls.conf.template; VARS="$VARS \$TLS_PORT \$TLS_CERT \$TLS_KEY"
  mkdir -p /var/www/certbot
  command -v ufw >/dev/null && ufw allow "${TLS_PORT}/tcp" >/dev/null 2>&1 || true
  ok "TLS 模板:HTTPS :${TLS_PORT}(记得云安全组放行 ${TLS_PORT}/tcp)"
fi
envsubst "$VARS" < "$TPL" > /etc/nginx/sites-available/copr.conf
ln -sf /etc/nginx/sites-available/copr.conf /etc/nginx/sites-enabled/copr.conf
# 旧 sub_converter.conf 已被统一 conf 取代(含 /get /admin),禁用避免 server_name 冲突
[[ -f /etc/nginx/sites-enabled/sub_converter.conf ]] && rm -f /etc/nginx/sites-enabled/sub_converter.conf
nginx -t
systemctl reload nginx
ok "nginx 已 reload"

# ── 4) 启动 converter(仅重启 Flask,不碰 sing-box)──────────────────────────
if [[ "$PANEL_ONLY" == "0" ]]; then
  systemctl enable sui-converter >/dev/null 2>&1 || true
  systemctl restart sui-converter
  sleep 1
  systemctl is-active --quiet sui-converter && ok "sui-converter 运行中" || { echo "converter 异常"; journalctl -u sui-converter -n 20 --no-pager; }
  curl -sf "http://${CONV_ADDR}/health" >/dev/null && ok "converter 健康检查通过" || echo "健康检查失败"
fi

echo ""; ok "完成。备份在 $BK"
echo "  面板:   http://${DOMAIN}${PANEL_PATH}"
echo "  订阅:   http://${DOMAIN}/get/<user>  (地址不变)"
echo "  回滚:   见 $BK 内 .bak,systemctl reload nginx / restart sui-converter"
