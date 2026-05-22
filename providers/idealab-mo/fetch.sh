#!/bin/bash
# claude-statusline provider plugin: idealab-mo (阿里 IdeaLab MO计划)
#
# Contract (see PROVIDERS.md):
#   - stdin            : the Claude Code status JSON
#   - env STATUSLINE_PROVIDER_DIR    : this plugin's directory
#   - env STATUSLINE_PROVIDER_CONFIG : path to config.json
#   - stdout           : a JSON object {"segments":[...]} or {"error":"..."}
#
# config.json fields:
#   cookie   (required) — browser Cookie header for idealab.alibaba-inc.com
#   teamCode (optional) — defaults to "API_TEAM_CODE_99"
set -f

dir="${STATUSLINE_PROVIDER_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
config="${STATUSLINE_PROVIDER_CONFIG:-$dir/config.json}"

# Emit a structured error and exit cleanly so the statusline can render it.
err() { jq -cn --arg m "$1" '{error:$m}'; exit 0; }

command -v jq   >/dev/null 2>&1 || err "缺少 jq"
command -v curl >/dev/null 2>&1 || err "缺少 curl"
[ -f "$config" ] || err "MO计划: 未配置 config.json"

cookie=$(jq -r '.cookie // empty' "$config" 2>/dev/null)
team=$(jq -r '.teamCode // "API_TEAM_CODE_99"' "$config" 2>/dev/null)
[ -n "$cookie" ] || err "MO计划: config.json 缺少 cookie"

resp=$(curl -s --max-time 10 \
    'https://idealab.alibaba-inc.com/api/ailab/ak/teamapi/getOrCreate' \
    -H 'accept: application/json' \
    -H 'content-type: application/json;charset=UTF-8' \
    -H 'origin: https://idealab.alibaba-inc.com' \
    -H 'referer: https://idealab.alibaba-inc.com/' \
    -b "$cookie" \
    --data-raw "{\"teamCode\":\"$team\"}" 2>/dev/null)

[ -n "$resp" ] || err "MO计划: 请求无响应"
ok=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)
[ "$ok" = "true" ] || err "MO计划: 登录态失效，请更新 cookie"

# Map the team-API quota fields to statusline segments.
echo "$resp" | jq -c '.data | {
  segments: [
    { label: "次数", used: (.cycleUsedCount // 0),  limit: (.cycleCallLimit // 0) },
    { label: "额度", used: (.cycleUsedAmount // 0), limit: (.cycleAmountLimit // 0),
      unit: "¥", decimals: 2 }
  ]
}'
