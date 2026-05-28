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
    mkdir -p src docs
    printf 'source\n' >src/main.uya
    printf 'readme\n' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    "$TMP_DIR/hgx" sparse remove docs >/dev/null 2>&1
)

[ -f "$REPO_DIR/src/main.uya" ]
[ ! -e "$REPO_DIR/docs/readme.md" ]
grep -F '"mode":"exclude"' "$REPO_DIR/.hgit/workspace/sparse.json" >/dev/null

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" sparse add docs >/dev/null 2>&1
    "$TMP_DIR/hgx" checkout HEAD >/dev/null 2>&1
)

[ "$(cat "$REPO_DIR/docs/readme.md")" = "readme" ]
grep -F '"mode":"include"' "$REPO_DIR/.hgit/workspace/sparse.json" >/dev/null
