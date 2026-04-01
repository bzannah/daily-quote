#!/usr/bin/env bash
# update_quote.sh — picks a random quote, writes current-quote.json, commits & pushes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

QUOTES_FILE="$SCRIPT_DIR/quotes.json"
OUTPUT_FILE="$SCRIPT_DIR/current-quote.json"

# Pick a random quote using Python (always available on macOS)
python3 - <<'PYEOF'
import json, random, sys
with open("quotes.json") as f:
    quotes = json.load(f)
pick = random.choice(quotes)
with open("current-quote.json", "w") as f:
    json.dump(pick, f, indent=2, ensure_ascii=False)
print(f"Selected: {pick['author']}")
PYEOF

# Git commit and push
git add current-quote.json
git commit -m "chore: daily quote update — $(date '+%Y-%m-%d %H:%M')"
git push origin main

echo "Done — quote updated and pushed."
