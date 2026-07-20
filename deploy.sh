#!/usr/bin/env bash
# =============================================================================
#  ⚠️ 此脚本已废弃。
#  它是早期的「独立 Hysteria2 安装器」,自己装 hy2 内核、不对接 s-ui,
#  与本项目现在的方向(s-ui 前端 + 旁挂 converter)相悖,且会误装内核。
#
#  请改用 s-ui 一键部署脚本:
#      sudo bash copr-panel/deploy/bootstrap.sh
#
#  它会:检测/复用 s-ui(不装内核)→ 申域名证书 → 部署 converter(转换+规则注入)
#  → 回填 users.json → (可选)经 s-ui API 把 hy2 硬化到域名证书 → 打印面板/订阅网址。
# =============================================================================
echo "此 deploy.sh 已废弃(独立 hy2,不对接 s-ui,会误装内核)。"
echo "请改用:  sudo bash copr-panel/deploy/bootstrap.sh"
exit 1
