#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src
    printf 'source\n' >src/main.uya
    "$TMP_DIR/hgx" add src/main.uya >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    printf 'modified\n' >src/main.uya
)

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" dehydrate src/main.uya >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
)
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "dehydrate should fail on dirty paths" >&2
    exit 1
fi

grep -F "error: checkout blocked by dirty workspace" "$TMP_DIR/stderr" >/dev/null
[ -f "$REPO_DIR/src/main.uya" ]
[ "$(cat "$REPO_DIR/src/main.uya")" = "modified" ]
