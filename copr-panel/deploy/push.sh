#!/usr/bin/env bash
# 本地构建面板 + 同步到服务器 + 远程跑 install.sh。可复用:全靠 config.env。
# 用法: bash push.sh            (全量:面板+converter+nginx)
#       bash push.sh --panel-only
set -euo pipefail
cd "$(dirname "$0")"
[[ -f config.env ]] || { echo "缺 config.env"; exit 1; }
set -a; source config.env; set +a
: "${SSH_HOST:?}" "${PANEL_DIR:?}" "${PANEL_PATH:?}"
# bash 3.2(macOS)下空数组 + set -u 会报 unbound,展开处用 ${arr[@]+...} 守卫
SSHOPT=(); [[ -n "${SSH_KEY:-}" ]] && SSHOPT=(-i "$SSH_KEY")

echo "[*] 构建面板(base=${PANEL_PATH})..."
( cd ../web && npm run build -- --base "${PANEL_PATH}" )

echo "[*] 同步 dist + deploy + converter 到 ${SSH_HOST}..."
ssh ${SSHOPT[@]+"${SSHOPT[@]}"} "$SSH_HOST" "mkdir -p ${PANEL_DIR} /root/copr-panel-src"
rsync -az --delete -e "ssh ${SSHOPT[*]-}" ../web/dist/ "$SSH_HOST:${PANEL_DIR}/"
rsync -az -e "ssh ${SSHOPT[*]-}" ../ "$SSH_HOST:/root/copr-panel-src/" \
  --exclude web/node_modules --exclude web/dist --exclude .git

echo "[*] 远程安装..."
ssh ${SSHOPT[@]+"${SSHOPT[@]}"} "$SSH_HOST" "cd /root/copr-panel-src/deploy && sudo bash install.sh ${1:-}"
echo "[OK] 部署完成。"
