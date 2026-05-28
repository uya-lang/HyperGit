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
    printf 'one\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
)

FIRST_HEAD="$(tr -d '\n' <"$REPO_DIR/.hgit/refs/heads/main")"

(
    cd "$REPO_DIR"
    printf 'two\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "second" >/dev/null 2>&1
    "$TMP_DIR/hgx" checkout "$FIRST_HEAD" >/dev/null 2>&1
)

if [ "$(cat "$REPO_DIR/main.txt")" != "one" ]; then
    echo "checkout should restore first commit content" >&2
    exit 1
fi

grep -F "\"base_commit\":\"$FIRST_HEAD\"" "$REPO_DIR/.hgit/workspace/state.json" >/dev/null
[ -s "$REPO_DIR/.hgit/workspace/local-change.hgi" ]
