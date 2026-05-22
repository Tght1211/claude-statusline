#!/bin/bash
# claude-statusline provider plugin: aone-cloud-cli (阿里 Aone Cloud CLI / ducky)
#
# Contract (see PROVIDERS.md):
#   - stdin            : the Claude Code status JSON
#   - env STATUSLINE_PROVIDER_DIR    : this plugin's directory
#   - env STATUSLINE_PROVIDER_CONFIG : path to config.json
#   - stdout           : a JSON object {"segments":[...]} or {"error":"..."}
#
# Auth: reads ANTHROPIC_AUTH_TOKEN from ~/.claude/settings.json (or config.json override)
set -f

dir="${STATUSLINE_PROVIDER_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
config="${STATUSLINE_PROVIDER_CONFIG:-$dir/config.json}"
claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

err() { jq -cn --arg m "$1" '{error:$m}'; exit 0; }

command -v jq   >/dev/null 2>&1 || err "缺少 jq"
command -v curl >/dev/null 2>&1 || err "缺少 curl"

token=""
if [ -f "$config" ]; then
    token=$(jq -r '.token // empty' "$config" 2>/dev/null)
fi
if [ -z "$token" ]; then
    token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$claude_config_dir/settings.json" 2>/dev/null)
fi
[ -n "$token" ] || err "Aone Cloud CLI: 未找到 ANTHROPIC_AUTH_TOKEN"

resp=$(curl -s --max-time 10 \
    'https://copilot.code.alibaba-inc.com/api/v2/user/tokenBalance?' \
    -H "authorization: Bearer $token" \
    -H 'content-type: application/json' 2>/dev/null)

[ -n "$resp" ] || err "Aone Cloud CLI: 请求无响应"
ok=$(echo "$resp" | jq -r '.success // false' 2>/dev/null)
[ "$ok" = "true" ] || err "Aone Cloud CLI: 认证失败，请检查 token"

echo "$resp" | jq -c '
  def scale_factor:
    if . >= 1000000000 then 1000000000
    elif . >= 1000000 then 1000000
    elif . >= 1000 then 1000
    else 1 end;
  def scale_unit:
    if . >= 1000000000 then "B"
    elif . >= 1000000 then "M"
    elif . >= 1000 then "K"
    else "" end;

  [.data[] | select(.modelName | test("opus|sonnet"; "i"))] |
  map(
    (if (.modelName | test("opus"; "i")) then "Opus"
     elif (.modelName | test("sonnet"; "i")) then "Sonnet"
     else .modelName end) as $short |
    (.totalTokensToday // 0) as $total |
    (.remainPercentToday // 100) as $dayPct |
    ($total | scale_factor) as $sf |
    ($total | scale_unit) as $unit |
    (($total * (100 - $dayPct) / 100) | floor) as $dayUsedRaw |
    (($dayUsedRaw / $sf * 10 | round) / 10) as $dayUsed |
    (($total / $sf * 10 | round) / 10) as $dayLimit |
    { label: ($short + "/日"), used: $dayUsed, limit: $dayLimit, unit: $unit, unitPos: "suffix", decimals: 1 }
  ) | { segments: . }'
