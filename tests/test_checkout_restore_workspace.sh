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

LINK_REPO_DIR="$TMP_DIR/link-repo"
mkdir -p "$LINK_REPO_DIR"

(
    cd "$LINK_REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    ln -s docs/readme.md link.txt
    "$TMP_DIR/hgx" add link.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "link" >/dev/null 2>&1
    rm link.txt
    ln -s other-target link.txt
    "$TMP_DIR/hgx" checkout . >/dev/null 2>&1
)

if [ ! -L "$LINK_REPO_DIR/link.txt" ]; then
    echo "checkout . should restore symlink entries as symlinks" >&2
    exit 1
fi

if [ "$(readlink "$LINK_REPO_DIR/link.txt")" != "docs/readme.md" ]; then
    echo "checkout . should restore symlink target content" >&2
    exit 1
fi

LARGE_REPO_DIR="$TMP_DIR/large-repo"
mkdir -p "$LARGE_REPO_DIR"

(
    cd "$LARGE_REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    truncate -s 40000000 large.bin
    "$TMP_DIR/hgx" add large.bin >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "large file" >/dev/null 2>&1
    rm large.bin
    "$TMP_DIR/hgx" checkout -- . >/dev/null 2>&1
)

if [ ! -f "$LARGE_REPO_DIR/large.bin" ]; then
    echo "checkout -- . should restore chunked large files" >&2
    exit 1
fi

if [ "$(stat -c '%s' "$LARGE_REPO_DIR/large.bin")" != "40000000" ]; then
    echo "checkout -- . should restore the full chunked large file size" >&2
    exit 1
fi

MANY_REPO_DIR="$TMP_DIR/many-repo"
mkdir -p "$MANY_REPO_DIR/files"

(
    cd "$MANY_REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    i=0
    while [ "$i" -lt 9000 ]; do
        printf 'file %s\n' "$i" >"files/$i.txt"
        i=$((i + 1))
    done
    "$TMP_DIR/hgx" add files >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "many files" >/dev/null 2>&1
    rm -rf files
    "$TMP_DIR/hgx" checkout -- . >/dev/null 2>&1
)

if [ "$(find "$MANY_REPO_DIR/files" -type f | wc -l | tr -d ' ')" != "9000" ]; then
    echo "checkout -- . should restore many files without exhausting task arena" >&2
    exit 1
fi

if [ "$(cat "$MANY_REPO_DIR/files/8999.txt")" != "file 8999" ]; then
    echo "checkout -- . should restore content after many-file checkout" >&2
    exit 1
fi
