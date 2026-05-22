#!/bin/bash
# Install Claude Code statusline (two-line: model/context/session $/duration | 5h/7d/today $/today tokens)
# Also installs the third-party provider-plugin system (see PROVIDERS.md).
# Based on https://github.com/daniel3303/ClaudeCodeStatusLine — see NOTICE.
set -e

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/Tght1211/claude-statusline/main}"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
TARGET_DIR="$HOME/.claude/statusline"
SETTINGS="$HOME/.claude/settings.json"
SKILL_DIR="$HOME/.claude/skills/statusline-provider"

# Reference provider plugins shipped with the installer.
REFERENCE_PROVIDERS="idealab-mo"

command -v jq >/dev/null 2>&1 || { echo "Error: jq not found. Install with: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl not found."; exit 1; }

mkdir -p "$TARGET_DIR" "$TARGET_DIR/bin" "$TARGET_DIR/providers"

# fetch_file <repo-relative-path> <destination> — copy from a local checkout
# when available, otherwise download from the repo.
fetch_file() {
    local rel="$1" dest="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$rel" ]; then
        cp "$SCRIPT_DIR/$rel" "$dest"
    else
        curl -fsSL "$REPO_RAW/$rel" -o "$dest"
    fi
}

fetch_file statusline.sh "$TARGET_DIR/statusline.sh"
chmod +x "$TARGET_DIR/statusline.sh"
echo "Installed: $TARGET_DIR/statusline.sh"

fetch_file bin/statusline-provider "$TARGET_DIR/bin/statusline-provider"
chmod +x "$TARGET_DIR/bin/statusline-provider"
echo "Installed: $TARGET_DIR/bin/statusline-provider"

fetch_file PROVIDERS.md "$TARGET_DIR/PROVIDERS.md" 2>/dev/null || true

# Provider plugins: refresh code files, but never clobber a user's config.json.
for pid in $REFERENCE_PROVIDERS; do
    mkdir -p "$TARGET_DIR/providers/$pid"
    fetch_file "providers/$pid/manifest.json"       "$TARGET_DIR/providers/$pid/manifest.json"
    fetch_file "providers/$pid/fetch.sh"            "$TARGET_DIR/providers/$pid/fetch.sh"
    fetch_file "providers/$pid/config.example.json" "$TARGET_DIR/providers/$pid/config.example.json"
    chmod +x "$TARGET_DIR/providers/$pid/fetch.sh"
    echo "Installed provider: $pid"
done

# Provider-development skill (so Claude Code can scaffold new providers).
mkdir -p "$SKILL_DIR"
fetch_file ".claude/skills/statusline-provider/SKILL.md" "$SKILL_DIR/SKILL.md" 2>/dev/null \
    && echo "Installed skill: statusline-provider" || true

mkdir -p "$HOME/.claude"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

tmp=$(mktemp)
jq '.statusLine = {"type":"command","command":"bash ~/.claude/statusline/statusline.sh","padding":0}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Updated: $SETTINGS"

echo
echo "Done. Restart Claude Code to see the new statusline."
echo
echo "管理第三方供应商插件:"
echo "  $TARGET_DIR/bin/statusline-provider list"
echo "可把它加入 PATH 方便调用，例如在 ~/.zshrc 里:"
echo "  alias statusline-provider='$TARGET_DIR/bin/statusline-provider'"
