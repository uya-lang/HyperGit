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
    printf 'base\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    printf 'staged\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    printf 'dirty\n' >main.txt
    printf 'keep\n' >notes.txt
    "$TMP_DIR/hgx" checkout -- . >/dev/null 2>&1
)

if [ "$(cat "$REPO_DIR/main.txt")" != "staged" ]; then
    echo "checkout -- . should restore the staged content" >&2
    exit 1
fi

if [ "$(cat "$REPO_DIR/notes.txt")" != "keep" ]; then
    echo "checkout -- . should leave untracked files untouched" >&2
    exit 1
fi

(
    cd "$REPO_DIR"
    printf 'dirty again\n' >main.txt
    "$TMP_DIR/hgx" checkout . >/dev/null 2>&1
)

if [ "$(cat "$REPO_DIR/main.txt")" != "staged" ]; then
    echo "checkout . should restore the staged content" >&2
    exit 1
fi

if [ "$(cat "$REPO_DIR/notes.txt")" != "keep" ]; then
    echo "checkout . should leave untracked files untouched" >&2
    exit 1
fi
