#!/usr/bin/env bash
# update_quote.sh — picks a random quote, injects it into index.html, commits & pushes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Pick a random quote and inject directly into index.html
python3 - <<'PYEOF'
import json, random, re

with open("quotes.json", encoding="utf-8") as f:
    quotes = json.load(f)

pick = random.choice(quotes)
quote_text = pick["quote"].replace("'", "&#39;").replace('"', '&quot;')
author_text = pick["author"].replace("'", "&#39;").replace('"', '&quot;')

with open("index.html", encoding="utf-8") as f:
    html = f.read()

# Replace between markers
html = re.sub(
    r'(<!-- QUOTE_TEXT_START -->).*?(<!-- QUOTE_TEXT_END -->)',
    f'<!-- QUOTE_TEXT_START -->\n    <p class="quote-text" id="quoteText">{quote_text}</p>\n    <!-- QUOTE_TEXT_END -->',
    html, flags=re.DOTALL
)
html = re.sub(
    r'(<!-- QUOTE_AUTHOR_START -->).*?(<!-- QUOTE_AUTHOR_END -->)',
    f'<!-- QUOTE_AUTHOR_START -->\n    <p class="quote-author" id="quoteAuthor">{author_text}</p>\n    <!-- QUOTE_AUTHOR_END -->',
    html, flags=re.DOTALL
)

with open("index.html", "w", encoding="utf-8") as f:
    f.write(html)

# Also write current-quote.json for reference
with open("current-quote.json", "w", encoding="utf-8") as f:
    json.dump(pick, f, indent=2, ensure_ascii=False)

print(f"Quote set: \"{pick['quote'][:60]}...\" — {pick['author']}")
PYEOF

# Git commit and push (pull --rebase first to avoid divergence rejections)
git add index.html current-quote.json
git commit -m "chore: quote update — $(date '+%Y-%m-%d %H:%M')"
git pull --rebase origin main
git push origin main

echo "✅ Done — quote updated and pushed to GitHub."
