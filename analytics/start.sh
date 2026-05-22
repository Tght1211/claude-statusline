#!/bin/bash
# Start the Claude Statusline Analytics server
set -e

cd "$(dirname "$0")"

DB="${ANALYTICS_DB:-$HOME/.claude/statusline/analytics.db}"

# Initialize DB if needed
if [ ! -f "$DB" ]; then
    mkdir -p "$(dirname "$DB")"
    sqlite3 "$DB" < schema.sql
    echo "Database initialized: $DB"
fi

# Run initial data ingestion (remove stale lock first)
rm -f /tmp/claude/statusline-ingest.lock
if [ -f ingest.sh ]; then
    echo "Running data ingestion..."
    bash ingest.sh "$HOME/.claude/projects" "$DB"
    count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM requests")
    echo "Database: $count requests"
fi

# Create venv if needed
if [ ! -d .venv ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install dependencies
pip install -q -r requirements.txt

# Start server
export ANALYTICS_DB="$DB"
export PROVIDERS_DIR="${PROVIDERS_DIR:-$HOME/.claude/statusline/providers}"
python3 app.py
