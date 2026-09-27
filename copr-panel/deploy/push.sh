#!/usr/bin/env bash
# 本地构建面板 + 同步到服务器 + 远程跑 bootstrap.sh --update。可复用:全靠 config.env。
# 用法: bash push.sh            (全量:面板+converter+nginx)
#       bash push.sh --panel-only   (只更新面板静态包)
#       CONFIG=config.copr.env bash push.sh   (发到另一台:选用的配置会作为那台的 config.env 上传)
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${CONFIG:-config.env}"
[[ -f "$CONFIG" ]] || { echo "缺 $CONFIG"; exit 1; }
# 不直接 source:config 里 `F2B_IGNOREIP=a b` 这种不带引号的空格值会被当成命令执行
source ./_common.sh; load_config_env "$CONFIG"
: "${SSH_HOST:?}"; PANEL_PATH="${PANEL_PATH:-/panel/}"   # 与 bootstrap.sh 默认一致
# bash 3.2(macOS)下空数组 + set -u 会报 unbound,展开处用 ${arr[@]+...} 守卫
SSHOPT=(); [[ -n "${SSH_KEY:-}" ]] && SSHOPT=(-i "$SSH_KEY")

# 直接构建到 deploy/webdist:服务器上 bootstrap 的 _panel 部署的就是它(建到 web/dist 会被旧包覆盖)
echo "[*] 构建面板(base=${PANEL_PATH})→ deploy/webdist ..."
( cd ../web && npm run build -- --base "${PANEL_PATH}" --outDir ../deploy/webdist --emptyOutDir )

echo "[*] 同步 deploy + converter + 面板包 到 ${SSH_HOST}..."
ssh ${SSHOPT[@]+"${SSHOPT[@]}"} "$SSH_HOST" "mkdir -p /root/copr-panel-src"
# 本地所有 config*.env 都不整目录同步(别的服务器的配置含密钥),只把选中的那份作为远端 config.env 上传
rsync -az -e "ssh ${SSHOPT[*]-}" ../ "$SSH_HOST:/root/copr-panel-src/" \
  --exclude web/node_modules --exclude web/dist --exclude .git --exclude 'deploy/config*.env'
rsync -az -e "ssh ${SSHOPT[*]-}" "$CONFIG" "$SSH_HOST:/root/copr-panel-src/deploy/config.env"

echo "[*] 远程安装..."
ssh ${SSHOPT[@]+"${SSHOPT[@]}"} "$SSH_HOST" "cd /root/copr-panel-src/deploy && sudo bash bootstrap.sh ${1:---update}"
echo "[OK] 部署完成。"
