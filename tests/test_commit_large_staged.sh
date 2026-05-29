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
    mkdir -p bulk
    i=1
    while [ "$i" -le 20 ]; do
        head -c 2097152 /dev/zero >"bulk/file-$i.bin"
        i=$((i + 1))
    done
    "$TMP_DIR/hgx" add bulk >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "large first" >/dev/null 2>&1
)

HEAD_FILE="$REPO_DIR/.hgit/refs/heads/main"
if [ ! -f "$HEAD_FILE" ]; then
    echo "missing head ref after large staged commit" >&2
    exit 1
fi

HEAD_HEX="$(tr -d '\n' <"$HEAD_FILE")"
if ! printf '%s' "$HEAD_HEX" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "unexpected head ref after large staged commit: $HEAD_HEX" >&2
    exit 1
fi

STATUS_STDOUT="$TMP_DIR/status.stdout"
STATUS_STDERR="$TMP_DIR/status.stderr"
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status
) >"$STATUS_STDOUT" 2>"$STATUS_STDERR"

grep -F "nothing to commit" "$STATUS_STDOUT" >/dev/null

if [ -s "$STATUS_STDERR" ]; then
    echo "unexpected stderr after large staged commit" >&2
    cat "$STATUS_STDERR" >&2
    exit 1
fi
