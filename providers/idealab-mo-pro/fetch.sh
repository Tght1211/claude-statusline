#!/bin/bash
# claude-statusline provider plugin: idealab-mo-pro (阿里 AI Studio MO计划-高阶)
#
# Contract (see PROVIDERS.md):
#   - stdin            : the Claude Code status JSON
#   - env STATUSLINE_PROVIDER_DIR    : this plugin's directory
#   - env STATUSLINE_PROVIDER_CONFIG : path to config.json
#   - stdout           : a JSON object {"segments":[...]} or {"error":"..."}
#
# config.json fields:
#   cookie   (required) — browser Cookie header for aistudio.alibaba-inc.com
#   teamCode (optional) — defaults to "API_TEAM_CODE_107"
set -f

dir="${STATUSLINE_PROVIDER_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
config="${STATUSLINE_PROVIDER_CONFIG:-$dir/config.json}"

err() { jq -cn --arg m "$1" '{error:$m}'; exit 0; }

command -v jq   >/dev/null 2>&1 || err "缺少 jq"
command -v curl >/dev/null 2>&1 || err "缺少 curl"
[ -f "$config" ] || err "MO计划-高阶: 未配置 config.json — 运行 statusline-provider setup idealab-mo-pro"

cookie=$(jq -r '.cookie // empty' "$config" 2>/dev/null)
team=$(jq -r '.teamCode // "API_TEAM_CODE_107"' "$config" 2>/dev/null)
losvc_key=$(jq -r '.losvcKey // empty' "$config" 2>/dev/null)
[ -n "$cookie" ] || err "MO计划-高阶: config.json 缺少 cookie"

refresh_security_tokens() {
    local key="$1" base_cookie="$2"
    [ -n "$key" ] || { echo "$base_cookie"; return; }
    local st
    st=$(curl -s --max-time 3 \
        'https://losvc.alibaba-inc.com:64556/api/securitytoken' \
        -H 'Content-Type: text/plain;charset=UTF-8' \
        -H 'Origin: https://aistudio.alibaba-inc.com' \
        --data-raw "{\"data\":\"$key\"}" 2>/dev/null) || { echo "$base_cookie"; return; }
    local ok
    ok=$(echo "$st" | jq -r '.result // 0' 2>/dev/null)
    [ "$ok" = "200" ] || { echo "$base_cookie"; return; }
    local new_wua new_sign new_umt
    new_wua=$(echo "$st" | jq -r '.x_mini_wua // empty' 2>/dev/null)
    new_sign=$(echo "$st" | jq -r '.x_sign // empty' 2>/dev/null)
    new_umt=$(echo "$st" | jq -r '.x_umt // empty' 2>/dev/null)
    [ -n "$new_wua" ] || { echo "$base_cookie"; return; }
    local out="$base_cookie"
    out=$(echo "$out" | sed "s/x_mini_wua=[^;]*/x_mini_wua=$new_wua/")
    out=$(echo "$out" | sed "s/x_sign=[^;]*/x_sign=$new_sign/")
    out=$(echo "$out" | sed "s/x_umt=[^;]*/x_umt=$new_umt/")
    echo "$out"
}

cookie=$(refresh_security_tokens "$losvc_key" "$cookie")

resp=$(curl -s --max-time 10 \
    'https://aistudio.alibaba-inc.com/api/ailab/ak/teamapi/getOrCreate' \
    -H 'accept: application/json' \
    -H 'content-type: application/json;charset=UTF-8' \
    -H 'origin: https://aistudio.alibaba-inc.com' \
    -H 'referer: https://aistudio.alibaba-inc.com/' \
    -b "$cookie" \
    --data-raw "{\"teamCode\":\"$team\"}" 2>/dev/null)

[ -n "$resp" ] || err "MO计划-高阶: 请求无响应"
ok=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)
[ "$ok" = "true" ] || err "MO计划-高阶: 登录态失效，请更新 cookie"

echo "$resp" | jq -c '.data | {
  segments: [
    { label: "次数", used: (.cycleUsedCount // 0),  limit: (.cycleCallLimit // 0) },
    { label: "额度", used: (.cycleUsedAmount // 0), limit: (.cycleAmountLimit // 0),
      unit: "¥", decimals: 2 }
  ]
}'
