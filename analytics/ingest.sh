#!/bin/bash
# claude-statusline analytics: ingest JSONL transcripts into SQLite
# Usage: ingest.sh <projects_dir> <db_path>
# Designed to run in background from statusline.sh — fast, idempotent, non-blocking.
set -f

projects_dir="${1:-$HOME/.claude/projects}"
db_path="${2:-$HOME/.claude/statusline/analytics.db}"
lock_file="/tmp/claude/statusline-ingest.lock"
schema_file="$(cd "$(dirname "$0")" && pwd)/schema.sql"

# Acquire lock (non-blocking)
if [ -f "$lock_file" ]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
    # Stale lock (>120s) — remove it
    [ "$lock_age" -gt 120 ] && rm -f "$lock_file" || exit 0
fi
echo $$ > "$lock_file"
trap 'rm -f "$lock_file"' EXIT

# Ensure DB exists with schema
mkdir -p "$(dirname "$db_path")"
if [ ! -f "$db_path" ]; then
    sqlite3 "$db_path" < "$schema_file"
fi

# Get last ingestion epoch (0 = first run, ingest everything)
last_epoch=$(sqlite3 "$db_path" "SELECT value FROM ingestion_state WHERE key='last_ingest_epoch'" 2>/dev/null)
[ -z "$last_epoch" ] && last_epoch=0

current_epoch=$(date +%s)

# Find JSONL files modified since last ingestion
find_args=()
if [ "$last_epoch" -gt 0 ]; then
    # Add 1s buffer to avoid missing edge cases
    ref_epoch=$(( last_epoch - 1 ))
    # Create a reference file with the target timestamp
    ref_file="/tmp/claude/ingest-ref-$$"
    touch -t "$(date -r "$ref_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$ref_epoch" +%Y%m%d%H%M.%S 2>/dev/null)" "$ref_file" 2>/dev/null
    if [ -f "$ref_file" ]; then
        find_args=(-newer "$ref_file")
    fi
fi

# Extract assistant entries and compute cost, output as SQL INSERT statements
sql_file="/tmp/claude/ingest-batch-$$.sql"
echo "BEGIN TRANSACTION;" > "$sql_file"

find "$projects_dir" -name "*.jsonl" -type f "${find_args[@]}" 2>/dev/null | while read -r f; do
    jq -r '
        select(.type == "assistant" and (.message.id // null) != null and (.message.model // null) != null) |
        [
            (.message.id // ""),
            (.sessionId // ""),
            (.message.model // ""),
            (.timestamp // ""),
            (.cwd // ""),
            (.message.usage.input_tokens // 0),
            (.message.usage.output_tokens // 0),
            (.message.usage.cache_creation_input_tokens // 0),
            (.message.usage.cache_read_input_tokens // 0)
        ] | @tsv
    ' "$f" 2>/dev/null
done | awk -F'\t' '
{
    mid=$1; sid=$2; model=$3; ts=$4; cwd=$5
    in_t=$6+0; out_t=$7+0; cc_t=$8+0; cr_t=$9+0

    # Skip synthetic/empty entries
    if (mid == "" || model == "" || model == "<synthetic>") next
    if (in_t == 0 && out_t == 0 && cc_t == 0 && cr_t == 0) next

    # Pricing (USD per million tokens)
    if (model ~ /haiku-4/)             { pi=1;    po=5;   pcc=1.25;  pcr=0.10 }
    else if (model ~ /haiku/)          { pi=0.80; po=4;   pcc=1;     pcr=0.08 }
    else if (model ~ /sonnet/)         { pi=3;    po=15;  pcc=3.75;  pcr=0.30 }
    else if (model ~ /opus-4-(5|6|7)/) { pi=5;    po=25;  pcc=6.25;  pcr=0.50 }
    else if (model ~ /opus/)           { pi=15;   po=75;  pcc=18.75; pcr=1.50 }
    else                               { pi=3;    po=15;  pcc=3.75;  pcr=0.30 }

    billable_in = in_t - cr_t
    if (billable_in < 0) billable_in = 0
    cost = (billable_in*pi + out_t*po + cc_t*pcc + cr_t*pcr) / 1000000

    # Escape single quotes in strings
    gsub(/'\''/, "'\'''\''", mid)
    gsub(/'\''/, "'\'''\''", sid)
    gsub(/'\''/, "'\'''\''", model)
    gsub(/'\''/, "'\'''\''", ts)
    gsub(/'\''/, "'\'''\''", cwd)

    printf "INSERT OR IGNORE INTO requests(message_id,session_id,model,timestamp,cwd,input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens,cost_usd) VALUES('\''%s'\'','\''%s'\'','\''%s'\'','\''%s'\'','\''%s'\'',%d,%d,%d,%d,%.6f);\n", mid, sid, model, ts, cwd, in_t, out_t, cc_t, cr_t, cost
}' >> "$sql_file"

echo "INSERT OR REPLACE INTO ingestion_state(key,value) VALUES('last_ingest_epoch','$current_epoch');" >> "$sql_file"
echo "COMMIT;" >> "$sql_file"

# Execute batch insert
sqlite3 "$db_path" < "$sql_file" 2>/dev/null

# Cleanup
rm -f "$sql_file" "$ref_file" 2>/dev/null
