#!/usr/bin/env bash
# update_quote.sh - picks a quote, opens a PR, approves it, merges it, and syncs main.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="${QUOTE_ENV_FILE:-$SCRIPT_DIR/.quote-env}"
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

BASE_BRANCH="${QUOTE_BASE_BRANCH:-main}"
MERGE_METHOD="${QUOTE_MERGE_METHOD:-merge}"
GITHUB_API_ROOT="${GITHUB_API_ROOT:-https://api.github.com}"
REMOTE_URL="$(git config --get remote.origin.url)"

AUTHOR_TOKEN="${QUOTE_GITHUB_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
REVIEW_TOKEN="${QUOTE_GITHUB_REVIEW_TOKEN:-${GITHUB_REVIEW_TOKEN:-}}"

token_from_remote() {
    local url="$1"
    local credentials token

    case "$url" in
        https://*@github.com/*)
            credentials="${url#https://}"
            credentials="${credentials%%@github.com/*}"
            token="${credentials#*:}"
            printf '%s\n' "$token"
            ;;
    esac
}

repo_slug_from_remote() {
    local url="$1"
    local slug

    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        printf '%s\n' "$GITHUB_REPOSITORY"
        return
    fi

    case "$url" in
        git@github.com:*)
            slug="${url#git@github.com:}"
            ;;
        https://*github.com/*)
            slug="${url#https://}"
            slug="${slug#*@github.com/}"
            slug="${slug#github.com/}"
            ;;
        *)
            slug=""
            ;;
    esac

    slug="${slug%.git}"
    printf '%s\n' "$slug"
}

if [ -z "$AUTHOR_TOKEN" ]; then
    AUTHOR_TOKEN="$(token_from_remote "$REMOTE_URL")"
fi

REPO_SLUG="${QUOTE_GITHUB_REPOSITORY:-$(repo_slug_from_remote "$REMOTE_URL")}"

if [ -z "$REPO_SLUG" ]; then
    echo "Could not determine the GitHub repository. Set QUOTE_GITHUB_REPOSITORY=owner/repo." >&2
    exit 1
fi

if [ -z "$AUTHOR_TOKEN" ]; then
    echo "Missing GitHub author token. Set QUOTE_GITHUB_TOKEN, GITHUB_TOKEN, or GH_TOKEN." >&2
    exit 1
fi

if [ -z "$REVIEW_TOKEN" ]; then
    echo "Missing GitHub review token. Set QUOTE_GITHUB_REVIEW_TOKEN to a different GitHub user's token." >&2
    echo "GitHub does not allow the PR author to approve their own pull request." >&2
    exit 1
fi

if [ "$AUTHOR_TOKEN" = "$REVIEW_TOKEN" ]; then
    echo "QUOTE_GITHUB_REVIEW_TOKEN must be different from the author token." >&2
    echo "GitHub does not allow the PR author to approve their own pull request." >&2
    exit 1
fi

if [ "$MERGE_METHOD" != "merge" ] && [ "$MERGE_METHOD" != "squash" ] && [ "$MERGE_METHOD" != "rebase" ]; then
    echo "QUOTE_MERGE_METHOD must be one of: merge, squash, rebase." >&2
    exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/daily-quote.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

print_api_error() {
    local body_file="$1"

    python3 - "$body_file" <<'PYEOF'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    with open(path, encoding="utf-8", errors="replace") as f:
        print(f.read(), file=sys.stderr)
    raise SystemExit

message = data.get("message")
errors = data.get("errors")
if message:
    print(message, file=sys.stderr)
if errors:
    print(json.dumps(errors, indent=2), file=sys.stderr)
PYEOF
}

github_api() {
    local token="$1"
    local method="$2"
    local path="$3"
    local body="${4-}"
    local response_file="$TMP_DIR/github-response.json"
    local status

    if [ "$#" -eq 4 ]; then
        status="$(curl -sS -o "$response_file" -w "%{http_code}" \
            -X "$method" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $token" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$GITHUB_API_ROOT/$path" \
            -d "$body")"
    else
        status="$(curl -sS -o "$response_file" -w "%{http_code}" \
            -X "$method" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $token" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$GITHUB_API_ROOT/$path")"
    fi

    case "$status" in
        2*)
            cat "$response_file"
            ;;
        *)
            echo "GitHub API request failed: $method $path (HTTP $status)" >&2
            print_api_error "$response_file"
            return 1
            ;;
    esac
}

json_field() {
    local field="$1"

    python3 -c '
import json
import sys

data = json.load(sys.stdin)
value = data
for part in sys.argv[1].split("."):
    value = value[part]
print(value)
' "$field"
}

if ! git diff --quiet -- index.html current-quote.json ||
    ! git diff --cached --quiet -- index.html current-quote.json; then
    echo "index.html or current-quote.json has uncommitted changes. Commit or stash them before running the quote updater." >&2
    exit 1
fi

BRANCH="daily-quote/update-$(date '+%Y%m%d-%H%M%S')"
COMMIT_MESSAGE="chore: quote update - $(date '+%Y-%m-%d %H:%M')"
PR_TITLE="$COMMIT_MESSAGE"
PR_BODY="Automated daily quote update generated at $(date '+%Y-%m-%d %H:%M:%S %Z')."

git fetch origin "$BASE_BRANCH"
git switch "$BASE_BRANCH"
git pull --ff-only origin "$BASE_BRANCH"
git switch -c "$BRANCH"

# Pick a quote and inject it into index.html.
python3 - <<'PYEOF'
import html as html_lib
import json
import random
import re

with open("quotes.json", encoding="utf-8") as f:
    quotes = json.load(f)

with open("current-quote.json", encoding="utf-8") as f:
    current = json.load(f)

candidates = [
    quote for quote in quotes
    if quote.get("quote") != current.get("quote")
    or quote.get("author") != current.get("author")
]

pick = random.choice(candidates or quotes)
quote_text = html_lib.escape(pick["quote"], quote=True)
author_text = html_lib.escape(pick["author"], quote=True)

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

# Also write current-quote.json for reference.
with open("current-quote.json", "w", encoding="utf-8") as f:
    json.dump(pick, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Quote set: \"{pick['quote'][:60]}...\" - {pick['author']}")
PYEOF

git add index.html current-quote.json
git commit -m "$COMMIT_MESSAGE"
git push origin "HEAD:refs/heads/$BRANCH"

export BASE_BRANCH BRANCH PR_TITLE PR_BODY
PR_PAYLOAD="$(python3 - <<'PYEOF'
import json
import os

print(json.dumps({
    "title": os.environ["PR_TITLE"],
    "head": os.environ["BRANCH"],
    "base": os.environ["BASE_BRANCH"],
    "body": os.environ["PR_BODY"],
    "maintainer_can_modify": True,
}))
PYEOF
)"

PR_RESPONSE="$(github_api "$AUTHOR_TOKEN" POST "repos/$REPO_SLUG/pulls" "$PR_PAYLOAD")"
PR_NUMBER="$(printf '%s' "$PR_RESPONSE" | json_field number)"
PR_URL="$(printf '%s' "$PR_RESPONSE" | json_field html_url)"

echo "Created pull request #$PR_NUMBER: $PR_URL"

APPROVAL_PAYLOAD="$(python3 - <<'PYEOF'
import json

print(json.dumps({
    "event": "APPROVE",
    "body": "Automated approval for the daily quote update.",
}))
PYEOF
)"

github_api "$REVIEW_TOKEN" POST "repos/$REPO_SLUG/pulls/$PR_NUMBER/reviews" "$APPROVAL_PAYLOAD" >/dev/null
echo "Approved pull request #$PR_NUMBER."

MERGE_PAYLOAD="$(python3 - <<PYEOF
import json

print(json.dumps({
    "commit_title": "Merge pull request #$PR_NUMBER from $BRANCH",
    "commit_message": "$COMMIT_MESSAGE",
    "merge_method": "$MERGE_METHOD",
}))
PYEOF
)"

github_api "$AUTHOR_TOKEN" PUT "repos/$REPO_SLUG/pulls/$PR_NUMBER/merge" "$MERGE_PAYLOAD" >/dev/null
echo "Merged pull request #$PR_NUMBER."

github_api "$AUTHOR_TOKEN" DELETE "repos/$REPO_SLUG/git/refs/heads/$BRANCH" >/dev/null || true

git switch "$BASE_BRANCH"
git pull --ff-only origin "$BASE_BRANCH"
git branch -D "$BRANCH" >/dev/null 2>&1 || true

echo "Done - quote update PR #$PR_NUMBER was approved, merged, and synced locally."
