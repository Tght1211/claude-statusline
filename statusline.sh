#!/bin/bash
# Source: https://github.com/daniel3303/ClaudeCodeStatusLine
# Single line: Model | tokens | %used | %remain | think | 5h bar @reset | 7d bar @reset | extra

set -f  # disable globbing
VERSION="1.5.0"

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ANSI colors matching oh-my-posh theme
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
purple='\033[38;2;167;139;250m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'

# Format token counts (e.g., 50k / 200k)
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {v=sprintf(\"%.1f\",$num/1000000)+0; if(v==int(v)) printf \"%dm\",v; else printf \"%.1fm\",v}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

# Format number with commas (e.g., 134,938)
format_commas() {
    printf "%'d" "$1"
}

# Return color escape based on usage percentage
# Usage: usage_color <pct>
usage_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then echo "$red"
    elif [ "$pct" -ge 70 ]; then echo "$orange"
    elif [ "$pct" -ge 50 ]; then echo "$yellow"
    else echo "$green"
    fi
}

# Render a unicode progress bar with per-cell threshold coloring.
# Filled cells are tinted green (≤50%), yellow (≤70%), orange (≤90%), red (>90%);
# empty cells are dim. Usage: make_bar <pct> <width>
make_bar() {
    local pct=$1
    local width=${2:-10}
    [ -z "$pct" ] && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    local filled=$(( pct * width / 100 ))
    local bar=""
    local i cell_pct
    for ((i=0; i<width; i++)); do
        if [ "$i" -lt "$filled" ]; then
            cell_pct=$(( (i + 1) * 100 / width ))
            if [ "$cell_pct" -gt 90 ]; then
                bar+="${red}█${reset}"
            elif [ "$cell_pct" -gt 70 ]; then
                bar+="${orange}█${reset}"
            elif [ "$cell_pct" -gt 50 ]; then
                bar+="${yellow}█${reset}"
            else
                bar+="${green}█${reset}"
            fi
        else
            bar+="${dim}░${reset}"
        fi
    done
    printf "%s" "$bar"
}

# Render one provider usage segment as "label bar pct% used/limit".
# When <limit> is empty/zero, renders just "label used" (no bar).
# Usage: render_segment <label> <used> <limit> <unit> <unitPos> <decimals>
render_segment() {
    local label="$1" used="$2" limit="$3" unit="$4" upos="$5" dec="$6"
    [ -z "$dec" ] && dec=0
    [ "$upos" = "suffix" ] || upos="prefix"
    local used_d
    used_d=$(LC_NUMERIC=C awk -v v="$used" -v d="$dec" 'BEGIN{printf "%.*f", d, v+0}')
    local fmt_used
    if [ "$upos" = "suffix" ]; then fmt_used="${used_d}${unit}"; else fmt_used="${unit}${used_d}"; fi
    if [ -n "$limit" ] && [ "$limit" != "null" ] && LC_NUMERIC=C awk -v l="$limit" 'BEGIN{exit !((l+0)>0)}'; then
        local limit_d pct color bar fmt_limit
        limit_d=$(LC_NUMERIC=C awk -v v="$limit" -v d="$dec" 'BEGIN{printf "%.*f", d, v+0}')
        pct=$(LC_NUMERIC=C awk -v u="$used" -v l="$limit" 'BEGIN{p=(u/l)*100; if(p>100)p=100; if(p<0)p=0; printf "%d", p}')
        color=$(usage_color "$pct")
        bar=$(make_bar "$pct" 10)
        if [ "$upos" = "suffix" ]; then fmt_limit="${limit_d}${unit}"; else fmt_limit="${unit}${limit_d}"; fi
        printf '%s' "${white}${label}${reset} ${bar} ${color}${pct}%${reset} ${dim}${fmt_used}/${fmt_limit}${reset}"
    else
        printf '%s' "${white}${label}${reset} ${dim}${fmt_used}${reset}"
    fi
}

# Format milliseconds to compact duration (e.g. 45s, 3m, 1h20m)
format_duration() {
    local ms=$1
    { [ -z "$ms" ] || [ "$ms" = "null" ]; } && { printf "0s"; return; }
    local secs=$(( ms / 1000 ))
    if [ "$secs" -lt 60 ]; then
        printf "%ds" "$secs"
    elif [ "$secs" -lt 3600 ]; then
        printf "%dm" $(( secs / 60 ))
    else
        printf "%dh%dm" $(( secs / 3600 )) $(( (secs % 3600) / 60 ))
    fi
}

# Format USD with two decimals
format_cost() {
    awk -v c="$1" 'BEGIN { printf "%.2f", c+0 }'
}

# Compact countdown from now to epoch (e.g. 45m, 2h30m, 5d6h)
format_countdown() {
    local target=$1
    { [ -z "$target" ] || [ "$target" = "null" ] || [ "$target" = "0" ]; } && return
    local now=$(date +%s)
    local diff=$(( target - now ))
    if [ "$diff" -le 0 ]; then
        printf "0m"
    elif [ "$diff" -lt 3600 ]; then
        printf "%dm" $(( diff / 60 ))
    elif [ "$diff" -lt 86400 ]; then
        printf "%dh%dm" $(( diff / 3600 )) $(( (diff % 3600) / 60 ))
    else
        printf "%dd%dh" $(( diff / 86400 )) $(( (diff % 86400) / 3600 ))
    fi
}

# Resolve config directory: CLAUDE_CONFIG_DIR (set by alias) or default ~/.claude
claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Return 0 (true) if $1 > $2 using semantic versioning
version_gt() {
    local a="${1#v}" b="${2#v}"
    local IFS='.'
    read -r a1 a2 a3 <<< "$a"
    read -r b1 b2 b3 <<< "$b"
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
    b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
    [ "$a1" -gt "$b1" ] 2>/dev/null && return 0
    [ "$a1" -lt "$b1" ] 2>/dev/null && return 1
    [ "$a2" -gt "$b2" ] 2>/dev/null && return 0
    [ "$a2" -lt "$b2" ] 2>/dev/null && return 1
    [ "$a3" -gt "$b3" ] 2>/dev/null && return 0
    return 1
}
# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
model_name=$(echo "$model_name" | sed 's/ *(\([0-9.]*[kKmM]*\) context)/ \1/')  # "(1M context)" → "1M"

# Apply model name mapping from provider manifests (e.g. "custom-30f27891" → "Opus 4.7")
_providers_dir="$claude_config_dir/statusline/providers"
if [ -d "$_providers_dir" ]; then
    _mapped=$(find -L "$_providers_dir" -maxdepth 2 -name manifest.json -exec jq -r --arg m "$model_name" '.modelMap[$m] // empty' {} \; 2>/dev/null | grep -m1 .)
    [ -n "$_mapped" ] && model_name="$_mapped"
fi

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Token usage
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi
pct_remain=$(( 100 - pct_used ))

used_comma=$(format_commas $current)
remain_comma=$(format_commas $(( size - current )))

# Session cost & duration from Claude Code's status JSON
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
session_dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
session_cost_fmt=$(format_cost "$session_cost")
session_dur_fmt=$(format_duration "$session_dur_ms")

# ===== Build output =====
# Line 1: model | context | session $ | session duration
out=""
out+="${blue}${model_name}${reset}"
out+=" ${dim}|${reset} ${orange}${used_tokens}/${total_tokens}${reset} ${dim}(${reset}${green}${pct_used}%${reset}${dim})${reset}"
out+=" ${dim}|${reset} ${dim}本次${reset} ${green}\$${session_cost_fmt}${reset}"
out+=" ${dim}|${reset} ${dim}用时${reset} ${cyan}${session_dur_fmt}${reset}"

# ===== Cross-platform OAuth token resolution (from statusline.sh) =====
# Tries credential sources in order: env var → macOS Keychain → Linux creds file → GNOME Keyring
get_oauth_token() {
    local token=""

    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    # 2. macOS Keychain (Claude Code appends a SHA256 hash of CLAUDE_CONFIG_DIR to the service name)
    if command -v security >/dev/null 2>&1; then
        local keychain_svc="Claude Code-credentials"
        if [ -n "$CLAUDE_CONFIG_DIR" ]; then
            local dir_hash
            dir_hash=$(echo -n "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)
            keychain_svc="Claude Code-credentials-${dir_hash}"
        fi
        local blob
        blob=$(security find-generic-password -s "$keychain_svc" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # 3. Linux credentials file
    local creds_file="${claude_config_dir}/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

# ===== Third-party Anthropic provider detection =====
# When ANTHROPIC_BASE_URL points away from Anthropic, the official 5h/7d OAuth
# usage endpoint no longer applies. In that case we skip it and instead try a
# provider plugin under $providers_dir (see PROVIDERS.md). Setting
# STATUSLINE_PROVIDER forces a specific plugin regardless of the base URL.
providers_dir="$claude_config_dir/statusline/providers"
provider_base="${ANTHROPIC_BASE_URL:-}"
if [ -z "$provider_base" ] && [ -f "$claude_config_dir/settings.json" ]; then
    provider_base=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$claude_config_dir/settings.json" 2>/dev/null)
fi
third_party=false
if [ -n "$provider_base" ]; then
    case "$provider_base" in
        *anthropic.com*) third_party=false ;;
        *) third_party=true ;;
    esac
fi
[ -n "$STATUSLINE_PROVIDER" ] && third_party=true

# macOS ships no `timeout`; fall back to gtimeout, or run without one (provider
# fetch scripts bound their own network calls with curl --max-time anyway).
statusline_timeout=""
if command -v timeout >/dev/null 2>&1; then statusline_timeout="timeout"
elif command -v gtimeout >/dev/null 2>&1; then statusline_timeout="gtimeout"
fi
run_with_timeout() {
    local secs="$1"; shift
    if [ -n "$statusline_timeout" ]; then "$statusline_timeout" "$secs" "$@"
    else "$@"; fi
}

# ===== LINE 2 & 3: Usage limits with progress bars =====
# First, try to use rate_limits data provided directly by Claude Code in the JSON input.
# This is the most reliable source — no OAuth token or API call required.
builtin_five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
builtin_five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
builtin_seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
builtin_seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

use_builtin=false
if [ -n "$builtin_five_hour_pct" ] || [ -n "$builtin_seven_day_pct" ]; then
    use_builtin=true
fi

# Cache setup — shared across all Claude Code instances to avoid rate limits
claude_config_dir_hash=$(echo -n "$claude_config_dir" | shasum -a 256 2>/dev/null || echo -n "$claude_config_dir" | sha256sum 2>/dev/null)
claude_config_dir_hash=$(echo "$claude_config_dir_hash" | cut -c1-8)
cache_file="/tmp/claude/statusline-usage-cache-${claude_config_dir_hash}.json"
cache_max_age=60  # seconds between API calls
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

# Always load cache — used as primary source for API path, and as fallback when builtin reports zero
if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
    fi
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

# When builtin values are all zero AND reset timestamps are missing, it likely indicates
# an API failure on Claude's side — fall through to cached data instead of displaying
# misleading 0%. Genuine zero responses (after a billing reset) still include valid
# resets_at timestamps, so we trust those.
effective_builtin=false
if $use_builtin; then
    # Trust builtin if any percentage is non-zero
    if { [ -n "$builtin_five_hour_pct" ] && [ "$(printf '%.0f' "$builtin_five_hour_pct" 2>/dev/null)" != "0" ]; } || \
       { [ -n "$builtin_seven_day_pct" ] && [ "$(printf '%.0f' "$builtin_seven_day_pct" 2>/dev/null)" != "0" ]; }; then
        effective_builtin=true
    fi
    # Also trust if reset timestamps are present — genuine zero responses include valid reset times
    if ! $effective_builtin; then
        if { [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ] && [ "$builtin_five_hour_reset" != "0" ]; } || \
           { [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ] && [ "$builtin_seven_day_reset" != "0" ]; }; then
            effective_builtin=true
        fi
    fi
fi

# Refresh API cache when stale — runs regardless of builtin rate_limits because
# extra_usage is only exposed through the OAuth usage endpoint (not stdin JSON).
# Throttled to cache_max_age and stampede-locked via touch for shared panes.
if ! $third_party && $needs_refresh; then
    touch "$cache_file"  # stampede lock: prevent parallel panes from fetching simultaneously
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 10 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        # Only cache valid usage responses (not error/rate-limit JSON)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    # Remove the stampede sentinel if the fetch failed to produce valid JSON —
    # otherwise an empty cache file would suppress retries for a full cache_max_age window.
    [ -f "$cache_file" ] && [ ! -s "$cache_file" ] && rm -f "$cache_file"
fi

# Cross-platform ISO to epoch conversion
# Converts ISO 8601 timestamp (e.g. "2025-06-15T12:30:00Z" or "2025-06-15T12:30:00.123+00:00") to epoch seconds.
# Properly handles UTC timestamps and converts to local time.
iso_to_epoch() {
    local iso_str="$1"

    # Try GNU date first (Linux) — handles ISO 8601 format automatically
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    # BSD date (macOS) - handle various ISO 8601 formats
    local stripped="${iso_str%%.*}"          # Remove fractional seconds (.123456)
    stripped="${stripped%%Z}"                 # Remove trailing Z
    stripped="${stripped%%+*}"               # Remove timezone offset (+00:00)
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"  # Remove negative timezone offset

    # Check if timestamp is UTC (has Z or +00:00 or -00:00)
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        # For UTC timestamps, parse with timezone set to UTC
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# Format ISO reset time to compact local time
# Usage: format_reset_time <iso_string> <style: time|datetime|date>
format_reset_time() {
    local iso_str="$1"
    local style="$2"
    { [ -z "$iso_str" ] || [ "$iso_str" = "null" ]; } && return

    # Parse ISO datetime and convert to local time (cross-platform)
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    # Format based on style
    # Try GNU date first (Linux), then BSD date (macOS)
    # Previous implementation piped BSD date through sed/tr, which always returned
    # exit code 0 from the last pipe stage, preventing the GNU date fallback from
    # ever executing on Linux.
    local formatted=""
    case "$style" in
        time)
            formatted=$(date -d "@$epoch" +"%H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null)
            ;;
        datetime)
            formatted=$(date -d "@$epoch" +"%-m/%-d %H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%-m/%-d %H:%M" 2>/dev/null)
            ;;
        *)
            formatted=$(date -d "@$epoch" +"%b %-d" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            ;;
    esac
    [ -n "$formatted" ] && echo "$formatted"
}

sep=" ${dim}|${reset} "

# Render extra_usage segment from API usage data (not available via stdin rate_limits).
# Appends to the global $out. No-op when data is missing or is_enabled is false.
render_extra_usage() {
    local data="$1"
    [ -z "$data" ] && return
    local enabled
    enabled=$(echo "$data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
    [ "$enabled" != "true" ] && return

    local pct used limit
    pct=$(echo "$data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    used=$(echo "$data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
    limit=$(echo "$data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')

    if [ -n "$used" ] && [ -n "$limit" ] && [[ "$used" != *'$'* ]] && [[ "$limit" != *'$'* ]]; then
        local color
        color=$(usage_color "$pct")
        out+="${sep}${white}extra${reset} ${color}\$${used}/\$${limit}${reset}"
    else
        out+="${sep}${white}extra${reset} ${green}enabled${reset}"
    fi
}

# Resolve and run the matching third-party provider plugin, appending its usage
# segments to $out. Provider output is cached (TTL from the plugin manifest),
# stampede-locked like the OAuth usage cache. Returns 0 when something was
# appended, 1 when no provider matched or the plugin yielded nothing.
render_third_party_usage() {
    local id="" manifest pid pat matched
    if [ -n "$STATUSLINE_PROVIDER" ]; then
        id="$STATUSLINE_PROVIDER"
    elif [ -d "$providers_dir" ]; then
        # set -f is on, so glob the providers dir via find rather than */
        while IFS= read -r manifest; do
            [ -f "$manifest" ] || continue
            pid=$(jq -r '.id // empty' "$manifest" 2>/dev/null)
            [ -n "$pid" ] || continue
            matched=false
            while IFS= read -r pat; do
                [ -n "$pat" ] || continue
                case "$provider_base" in
                    *"$pat"*) matched=true; break ;;
                esac
            done < <(jq -r '.match[]? // empty' "$manifest" 2>/dev/null)
            if $matched; then id="$pid"; break; fi
        done < <(find -L "$providers_dir" -mindepth 2 -maxdepth 2 -name manifest.json 2>/dev/null)
    fi
    [ -z "$id" ] && return 1

    local mdir="$providers_dir/$id"
    manifest="$mdir/manifest.json"
    [ -f "$manifest" ] || return 1
    local fetch ttl
    fetch=$(jq -r '.fetch // "fetch.sh"' "$manifest" 2>/dev/null)
    ttl=$(jq -r '.cacheTtl // 120' "$manifest" 2>/dev/null)
    [ -n "$ttl" ] && [ "$ttl" -gt 0 ] 2>/dev/null || ttl=120
    [ -f "$mdir/$fetch" ] || return 1

    # Provider output cache — shared across panes, throttled to the plugin TTL
    local pcache="/tmp/claude/statusline-provider-${id}-${claude_config_dir_hash}.json"
    local pdata="" pneed=true pm pn
    if [ -f "$pcache" ] && [ -s "$pcache" ]; then
        pm=$(stat -c %Y "$pcache" 2>/dev/null || stat -f %m "$pcache" 2>/dev/null)
        pn=$(date +%s)
        [ $(( pn - pm )) -lt "$ttl" ] && pneed=false
        pdata=$(cat "$pcache" 2>/dev/null)
    fi
    if $pneed; then
        touch "$pcache"
        local fresh
        fresh=$(STATUSLINE_PROVIDER_DIR="$mdir" \
                STATUSLINE_PROVIDER_CONFIG="$mdir/config.json" \
                STATUSLINE_PROVIDER_BASE="$provider_base" \
                run_with_timeout 12 bash "$mdir/$fetch" <<< "$input" 2>/dev/null)
        if [ -n "$fresh" ] && echo "$fresh" | jq -e . >/dev/null 2>&1; then
            pdata="$fresh"
            echo "$fresh" > "$pcache"
        fi
        [ -f "$pcache" ] && [ ! -s "$pcache" ] && rm -f "$pcache"
    fi

    [ -z "$pdata" ] && return 1
    local perr
    perr=$(echo "$pdata" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$perr" ]; then
        out+="${dim}${perr}${reset}"
        return 0
    fi
    local n i lbl used lim unit upos dec
    n=$(echo "$pdata" | jq '.segments | length' 2>/dev/null)
    [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null || return 1
    for ((i=0; i<n; i++)); do
        lbl=$(echo "$pdata" | jq -r ".segments[$i].label // \"\"")
        used=$(echo "$pdata" | jq -r ".segments[$i].used // 0")
        lim=$(echo "$pdata" | jq -r ".segments[$i].limit // empty")
        unit=$(echo "$pdata" | jq -r ".segments[$i].unit // \"\"")
        upos=$(echo "$pdata" | jq -r ".segments[$i].unitPos // \"prefix\"")
        dec=$(echo "$pdata" | jq -r ".segments[$i].decimals // 0")
        [ "$i" -gt 0 ] && out+="$sep"
        out+=$(render_segment "$lbl" "$used" "$lim" "$unit" "$upos" "$dec")
    done
    return 0
}

# Line 2 starts on a new line
out+="\n"

line2_filled=false
if $third_party; then
    # ---- Third-party provider: no official 5h/7d; try a provider plugin ----
    render_third_party_usage && line2_filled=true
elif $effective_builtin; then
    # ---- Use rate_limits data provided directly by Claude Code in JSON input ----
    if [ -n "$builtin_five_hour_pct" ]; then
        five_hour_pct=$(printf "%.0f" "$builtin_five_hour_pct")
        five_hour_color=$(usage_color "$five_hour_pct")
        five_hour_bar=$(make_bar "$five_hour_pct" 10)
        out+="${white}5h${reset} ${five_hour_bar} ${five_hour_color}${five_hour_pct}%${reset}"
        if [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ]; then
            five_hour_cd=$(format_countdown "$builtin_five_hour_reset")
            [ -n "$five_hour_cd" ] && out+=" ${dim}↻${five_hour_cd}${reset}"
        fi
    else
        out+="${white}5h${reset} ${dim}-${reset}"
    fi

    if [ -n "$builtin_seven_day_pct" ]; then
        seven_day_pct=$(printf "%.0f" "$builtin_seven_day_pct")
        seven_day_color=$(usage_color "$seven_day_pct")
        seven_day_bar=$(make_bar "$seven_day_pct" 10)
        out+="${sep}${white}7d${reset} ${seven_day_bar} ${seven_day_color}${seven_day_pct}%${reset}"
        if [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ]; then
            seven_day_cd=$(format_countdown "$builtin_seven_day_reset")
            [ -n "$seven_day_cd" ] && out+=" ${dim}↻${seven_day_cd}${reset}"
        fi
    else
        out+="${sep}${white}7d${reset} ${dim}-${reset}"
    fi

    # Cache builtin values so they're available as fallback when API is unavailable.
    _fh_reset_json="null"
    if [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ] && [ "$builtin_five_hour_reset" != "0" ]; then
        _fh_iso=$(date -u -r "$builtin_five_hour_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -d "@$builtin_five_hour_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        [ -n "$_fh_iso" ] && _fh_reset_json="\"$_fh_iso\""
    fi
    _sd_reset_json="null"
    if [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ] && [ "$builtin_seven_day_reset" != "0" ]; then
        _sd_iso=$(date -u -r "$builtin_seven_day_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -d "@$builtin_seven_day_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        [ -n "$_sd_iso" ] && _sd_reset_json="\"$_sd_iso\""
    fi
    printf '{"five_hour":{"utilization":%s,"resets_at":%s},"seven_day":{"utilization":%s,"resets_at":%s}}' \
        "${builtin_five_hour_pct:-0}" "$_fh_reset_json" \
        "${builtin_seven_day_pct:-0}" "$_sd_reset_json" > "$cache_file" 2>/dev/null
    line2_filled=true
elif [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
    # ---- Fall back: API-fetched usage data ----
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso" 2>/dev/null)
    five_hour_cd=$(format_countdown "$five_hour_reset_epoch")
    five_hour_color=$(usage_color "$five_hour_pct")
    five_hour_bar=$(make_bar "$five_hour_pct" 10)
    out+="${white}5h${reset} ${five_hour_bar} ${five_hour_color}${five_hour_pct}%${reset}"
    [ -n "$five_hour_cd" ] && out+=" ${dim}↻${five_hour_cd}${reset}"

    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso" 2>/dev/null)
    seven_day_cd=$(format_countdown "$seven_day_reset_epoch")
    seven_day_color=$(usage_color "$seven_day_pct")
    seven_day_bar=$(make_bar "$seven_day_pct" 10)
    out+="${sep}${white}7d${reset} ${seven_day_bar} ${seven_day_color}${seven_day_pct}%${reset}"
    [ -n "$seven_day_cd" ] && out+=" ${dim}↻${seven_day_cd}${reset}"
    line2_filled=true
else
    out+="${white}5h${reset} ${dim}-${reset}"
    out+="${sep}${white}7d${reset} ${dim}-${reset}"
    line2_filled=true
fi

# ===== Today's totals (cost & tokens) — aggregated from local transcripts =====
projects_dir="$claude_config_dir/projects"
daily_cache_file="/tmp/claude/statusline-daily-cache-${claude_config_dir_hash}.json"
daily_cache_max_age=60
daily_today=$(date +%Y-%m-%d)
daily_cost=0
daily_tokens=0
daily_needs_refresh=true

if [ -f "$daily_cache_file" ] && [ -s "$daily_cache_file" ]; then
    cached_date=$(jq -r '.date // empty' "$daily_cache_file" 2>/dev/null)
    if [ "$cached_date" = "$daily_today" ]; then
        d_mtime=$(stat -f %m "$daily_cache_file" 2>/dev/null || stat -c %Y "$daily_cache_file" 2>/dev/null)
        d_now=$(date +%s)
        d_age=$(( d_now - d_mtime ))
        if [ "$d_age" -lt "$daily_cache_max_age" ]; then
            daily_needs_refresh=false
            daily_cost=$(jq -r '.cost // 0' "$daily_cache_file" 2>/dev/null)
            daily_tokens=$(jq -r '.tokens // 0' "$daily_cache_file" 2>/dev/null)
        fi
    fi
fi

if $daily_needs_refresh && [ -d "$projects_dir" ]; then
    today_start=$(date -j -v0H -v0M -v0S +%s 2>/dev/null || date -d "today 00:00" +%s)
    daily_data=$(find "$projects_dir" -name "*.jsonl" -type f 2>/dev/null | while read -r f; do
        f_mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
        [ -n "$f_mtime" ] && [ "$f_mtime" -ge "$today_start" ] && cat "$f"
    done | jq -r --argjson start "$today_start" '
        select(.type == "assistant" and (.timestamp // null) != null) |
        (.timestamp | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+(?=[+-])"; "") | fromdateiso8601? // 0) as $ts |
        select($ts >= $start) |
        [
            (.message.id // ""),
            (.message.model // ""),
            (.message.usage.input_tokens // 0),
            (.message.usage.output_tokens // 0),
            (.message.usage.cache_creation_input_tokens // 0),
            (.message.usage.cache_read_input_tokens // 0)
        ] | @tsv
    ' 2>/dev/null | awk -F'\t' '
        {
            mid=$1; model=$2; in_t=$3; out_t=$4; cc_t=$5; cr_t=$6
            # 跨源去重：同一 message.id 仅计一次（参考 cc-switch session_usage 去重）
            if (mid != "" && seen[mid]++) next
            # 价格表对齐 cc-switch schema.rs::seed_model_pricing
            # 顺序很重要：先匹配带版本号的新模型，再回退到旧版
            if (model ~ /haiku-4/)            { pi=1;    po=5;   pcc=1.25;  pcr=0.10 }
            else if (model ~ /haiku/)         { pi=0.80; po=4;   pcc=1;     pcr=0.08 }
            else if (model ~ /sonnet/)        { pi=3;    po=15;  pcc=3.75;  pcr=0.30 }
            else if (model ~ /opus-4-(5|6|7)/){ pi=5;    po=25;  pcc=6.25;  pcr=0.50 }
            else if (model ~ /opus/)          { pi=15;   po=75;  pcc=18.75; pcr=1.50 }
            else                              { pi=3;    po=15;  pcc=3.75;  pcr=0.30 }
            # 防御：某些代理把 cache_read 计入 input_tokens（参考 cc-switch calculator.rs）
            billable_in = in_t - cr_t; if (billable_in < 0) billable_in = 0
            tokens += in_t + out_t + cc_t + cr_t
            cost += (billable_in*pi + out_t*po + cc_t*pcc + cr_t*pcr) / 1000000
        }
        END { printf "%.4f\t%d", cost+0, tokens+0 }
    ')
    daily_cost=$(printf "%s" "$daily_data" | awk -F'\t' '{print $1+0}')
    daily_tokens=$(printf "%s" "$daily_data" | awk -F'\t' '{print $2+0}')
    [ -z "$daily_cost" ] && daily_cost=0
    [ -z "$daily_tokens" ] && daily_tokens=0
    printf '{"date":"%s","cost":%s,"tokens":%s}' "$daily_today" "$daily_cost" "$daily_tokens" > "$daily_cache_file" 2>/dev/null

    # Background analytics ingestion (non-blocking, best-effort)
    _ingest="$claude_config_dir/statusline/analytics/ingest.sh"
    if [ -f "$_ingest" ] && command -v sqlite3 >/dev/null 2>&1; then
        bash "$_ingest" "$projects_dir" "$claude_config_dir/statusline/analytics.db" &>/dev/null &
        disown 2>/dev/null
    fi
fi

daily_cost_fmt=$(format_cost "$daily_cost")
daily_tokens_fmt=$(format_tokens "$daily_tokens")
$line2_filled && out+="$sep"
out+="${dim}今日${reset} ${green}\$${daily_cost_fmt}${reset} ${dim}/${reset} ${orange}${daily_tokens_fmt}${reset} ${dim}词元${reset}"

# ===== Update check against this fork's releases (cached, 24h TTL) =====
# Checks Tght1211/claude-statusline, not upstream daniel3303 — acting on the
# upstream hint would overwrite this fork.
version_cache_file="/tmp/claude/statusline-version-cache.json"
version_cache_max_age=86400  # 24 hours

version_needs_refresh=true
version_data=""

if [ -f "$version_cache_file" ]; then
    vc_mtime=$(stat -c %Y "$version_cache_file" 2>/dev/null || stat -f %m "$version_cache_file" 2>/dev/null)
    vc_now=$(date +%s)
    vc_age=$(( vc_now - vc_mtime ))
    if [ "$vc_age" -lt "$version_cache_max_age" ]; then
        version_needs_refresh=false
    fi
    version_data=$(cat "$version_cache_file" 2>/dev/null)
fi

if $version_needs_refresh; then
    touch "$version_cache_file" 2>/dev/null
    vc_response=$(curl -s --max-time 5 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/Tght1211/claude-statusline/releases/latest" 2>/dev/null)
    if [ -n "$vc_response" ] && echo "$vc_response" | jq -e '.tag_name' >/dev/null 2>&1; then
        version_data="$vc_response"
        echo "$vc_response" > "$version_cache_file"
    elif [ ! -s "$version_cache_file" ]; then
        # Fetch failed and the cache has no usable content — drop the empty
        # stampede lock so the next render retries instead of the fresh mtime
        # suppressing update checks for the full 24h TTL.
        rm -f "$version_cache_file" 2>/dev/null
    fi
fi

update_line=""
if [ -n "$version_data" ]; then
    latest_tag=$(echo "$version_data" | jq -r '.tag_name // empty')
    if [ -n "$latest_tag" ] && version_gt "$latest_tag" "$VERSION"; then
        update_line="\n${dim}Update available: ${latest_tag} → curl -fsSL https://raw.githubusercontent.com/Tght1211/claude-statusline/main/statusline.sh -o ~/.claude/statusline/statusline.sh${reset}"
    fi
fi

# Output
printf "%b" "$out$update_line"

exit 0
