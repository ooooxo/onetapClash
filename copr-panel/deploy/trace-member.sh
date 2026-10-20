#!/usr/bin/env bash
# 实时看某个会员的每条连接从哪台服务器、哪个协议出去(查"地区不可用"、出口国家来回跳)。Ctrl-C 结束。
# 用法: bash trace-member.sh <s-ui 会员名> [域名正则]
#       bash trace-member.sh aa 'meta|facebook|fbcdn|instagram|muse'      # 只看 Muse/Meta
#       CONFIGS="config.copr.env" bash trace-member.sh jf openai          # 只看一台
# 需要: 本地 config*.env 里的 SSH_HOST 能直连;订阅别名(如 test)要填它对应的 s-ui 会员名(aa)。
set -euo pipefail
cd "$(dirname "$0")"
CONFIGS="${CONFIGS:-config.copr.env config.vpn-am.env}"
MEMBER="${1:?用法: bash trace-member.sh <会员名> [域名正则]}"
PATTERN="${2:-.}"
source ./_common.sh

# 每台服务器一个 journalctl -f;sing-box 日志格式: inbound/<协议>[<入站名>] [<会员>] inbound [packet ]connection to <目标>
for cfg in $CONFIGS; do
  ( load_config_env "$cfg"; : "${SSH_HOST:?$cfg 缺 SSH_HOST}"
    ssh "$SSH_HOST" "journalctl -u s-ui -f -n 0 -o cat --no-pager" |
      sed -nuE "s/.*inbound\/([a-z0-9]+)\[[^]]*\] \[$MEMBER\] inbound (packet )?connection to (.*)$/\1 \2\3/p" |
      grep --line-buffered -iE "$PATTERN" |
      while read -r proto rest; do printf '%s  %-8s %-10s %s\n' "$(date +%T)" "${SSH_HOST}" "$proto" "$rest"; done
  ) &
done
trap 'kill 0' INT TERM EXIT
wait
