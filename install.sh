#!/bin/bash
# Install Claude Code statusline (two-line: model/context/session $/duration | 5h/7d/today $/today tokens)
# Based on https://github.com/daniel3303/ClaudeCodeStatusLine — see NOTICE.
set -e

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/Tght1211/claude-statusline/main}"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
TARGET_DIR="$HOME/.claude/statusline"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "Error: jq not found. Install with: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl not found."; exit 1; }

mkdir -p "$TARGET_DIR"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/statusline.sh" ]; then
    cp "$SCRIPT_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
    echo "Installed (local): $TARGET_DIR/statusline.sh"
else
    curl -fsSL "$REPO_RAW/statusline.sh" -o "$TARGET_DIR/statusline.sh"
    echo "Installed (downloaded): $TARGET_DIR/statusline.sh"
fi
chmod +x "$TARGET_DIR/statusline.sh"

mkdir -p "$HOME/.claude"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

tmp=$(mktemp)
jq '.statusLine = {"type":"command","command":"bash ~/.claude/statusline/statusline.sh","padding":0}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Updated: $SETTINGS"

echo
echo "Done. Restart Claude Code to see the new statusline."
