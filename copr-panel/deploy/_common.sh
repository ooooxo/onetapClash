#!/usr/bin/env bash
# _common.sh — 各 ensure-*.sh / bootstrap.sh 共用的小工具。用 source 引入,不单独执行。
#
# load_config_env [路径]
#   把 config.env 当作【默认值】读进来:**环境里已经显式传进来的变量优先,不被覆盖**。
#   这点很关键 —— 早先写成 `set -a; source config.env`,会无条件覆盖调用方传的环境变量,
#   于是 `HY2_TAG=xxx bash ensure-nodes.sh` 完全不生效(被 config.env 里的值盖掉),
#   bootstrap.sh 逐项传参也等于白传。
#   行尾注释按 shell 规则去掉:「空白 + #」之后都是注释(`HY2_PORT=443  # UDP` → 443);
#   值里不跟在空白后的 # 保留(`PASS=a#b`);带 # 或空格的值用引号包起来(`PASS="a #b"`)。
load_config_env() {
  local f="${1:-config.env}"
  [[ -f "$f" ]] || return 0
  local line k v
  local re_dq='^"([^"]*)"' re_sq="^'([^']*)'"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                       # 容忍 CRLF
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    k="${line%%=*}"; v="${line#*=}"
    k="${k//[[:space:]]/}"
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n "${!k:-}" ]] && continue             # 环境里已有值 → 环境优先
    if [[ "$v" =~ $re_dq || "$v" =~ $re_sq ]]; then
      v="${BASH_REMATCH[1]}"                   # 引号内原样保留(含 # 和空格)
    else
      v="${v%%[[:space:]]#*}"                  # 去行尾注释(`KEY=   # 注释` → 空值)
      v="${v#"${v%%[![:space:]]*}"}"           # 去前导空白
      v="${v%"${v##*[![:space:]]}"}"           # 去尾随空白
    fi
    printf -v "$k" '%s' "$v"
    export "${k?}"
  done < "$f"
}
