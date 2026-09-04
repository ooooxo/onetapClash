#!/usr/bin/env bash
# =============================================================================
# ensure-sui.sh — 无人值守装好/配好 s-ui(幂等,可重跑)
#   干什么: ① 没装就静默装官方 s-ui ② 设管理员账号密码
#           ③ 设面板端口/路径/域名、订阅端口/路径、时区
#           ④ 把 webListen 清空 —— 这是「后端不可达」的元凶,见下方注释
#   怎么跑: sudo bash ensure-sui.sh          (读同目录 config.env)
# 参数:
# =============================================================================
DOMAIN="${DOMAIN:-}"
SUI_USER="${SUI_USER:-}"
SUI_PASS="${SUI_PASS:-}"
SUI_PORT="${SUI_PORT:-2095}"
SUI_BASE="${SUI_BASE:-/app/}"
SUI_SUB_PORT="${SUI_SUB_PORT:-2096}"
SUI_SUB_PATH="${SUI_SUB_PATH:-/sub/}"
TIME_LOCATION="${TIME_LOCATION:-Asia/Shanghai}"

set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "需要 root"; exit 1; }
DOMAIN="${DOMAIN:?需要 DOMAIN}"
[[ -n "$SUI_USER" && -n "$SUI_PASS" ]] || { echo "需要 SUI_USER / SUI_PASS"; exit 1; }
log(){ echo -e "\033[36m[*]\033[0m $*"; }
ok(){  echo -e "\033[32m[OK]\033[0m $*"; }

SUI_BIN=/usr/local/s-ui/sui
DB=/usr/local/s-ui/db/s-ui.db

# ── 1) 安装(官方脚本;已装则复用,绝不重装免得丢节点/会员)──────────────────
# 注意:不要用 `systemctl list-unit-files | grep -q` 判断 —— grep -q 命中即关管道,
# systemctl 收 SIGPIPE(141),在 set -o pipefail 下会被误判成"没装"。
if systemctl cat s-ui >/dev/null 2>&1 || [[ -x "$SUI_BIN" ]]; then
  ok "s-ui 已存在,复用(不动现有节点/会员)"
else
  log "安装 s-ui(官方脚本,无人值守)..."
  # 官方脚本装完会交互问端口/账号;喂空行走默认,随后我们自己用 CLI 精确设置
  yes '' | bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) >/dev/null 2>&1 || true
  [[ -x "$SUI_BIN" ]] || { echo "s-ui 安装失败"; exit 1; }
  ok "s-ui 安装完成"
fi

# ── 2) 账号 + 端口/路径(CLI 支持的部分)─────────────────────────────────────
"$SUI_BIN" admin   -username "$SUI_USER" -password "$SUI_PASS" >/dev/null 2>&1 || true
"$SUI_BIN" setting -port "$SUI_PORT" -path "$SUI_BASE" \
                   -subPort "$SUI_SUB_PORT" -subPath "$SUI_SUB_PATH" >/dev/null 2>&1 || true
ok "s-ui 账号/端口已设置(面板 ${SUI_PORT}${SUI_BASE} · 订阅 ${SUI_SUB_PORT}${SUI_SUB_PATH})"

# ── 3) webListen / webDomain / 时区(CLI 没有对应开关,只能改 settings 表)────
#
# ⚠️ 这一步是整个项目最容易踩的坑:
#    s-ui 的 webListen 一旦被设成域名(面板里填了「面板域名」就会),它就【只】绑那个
#    域名解析到的公网 IP。而 nginx 是反代到 127.0.0.1:<端口> 的 —— 于是 nginx 连不上,
#    Vue 面板一律报「后端不可达」,但 s-ui 本身明明活得好好的,极难排查。
#    留空 = 监听所有接口,127.0.0.1 和公网都通;webDomain 仍然守住 Host,安全性不变。
#
systemctl stop s-ui 2>/dev/null || true
sqlite3 "$DB" "
  INSERT INTO settings(key,value) SELECT 'webListen','' WHERE NOT EXISTS(SELECT 1 FROM settings WHERE key='webListen');
  UPDATE settings SET value=''                 WHERE key='webListen';
  INSERT INTO settings(key,value) SELECT 'webDomain','${DOMAIN}' WHERE NOT EXISTS(SELECT 1 FROM settings WHERE key='webDomain');
  UPDATE settings SET value='${DOMAIN}'        WHERE key='webDomain';
  UPDATE settings SET value='${TIME_LOCATION}' WHERE key='timeLocation';
"
systemctl start s-ui
ok "webListen 已清空(监听全部接口),webDomain=${DOMAIN},时区=${TIME_LOCATION}"

# ── 4) 自检:nginx 走的就是这条路,这里不通面板就一定报「后端不可达」──────────
for i in $(seq 1 15); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "Host: ${DOMAIN}" \
          "http://127.0.0.1:${SUI_PORT}${SUI_BASE}" || true)"
  [[ "$code" =~ ^(200|307|302)$ ]] && { ok "回环自检通过 127.0.0.1:${SUI_PORT} → HTTP ${code}"; exit 0; }
  sleep 1
done
echo "[ERR] 127.0.0.1:${SUI_PORT} 不通(最后一次 HTTP ${code:-000}) —— 面板会报「后端不可达」"
journalctl -u s-ui -n 20 --no-pager || true
exit 1
