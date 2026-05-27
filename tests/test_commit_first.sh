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
    printf 'hello' >src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
)

stdout_file="$TMP_DIR/commit.stdout"
stderr_file="$TMP_DIR/commit.stderr"

set +e
(
    cd "$REPO_DIR"
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "initial"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for first commit: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for first commit" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for first commit" >&2
    cat "$stderr_file" >&2
    exit 1
fi

HEAD_FILE="$REPO_DIR/.hgit/refs/heads/main"
if [ ! -f "$HEAD_FILE" ]; then
    echo "missing head ref after first commit" >&2
    exit 1
fi

HEAD_HEX="$(tr -d '\n' <"$HEAD_FILE")"
if ! printf '%s' "$HEAD_HEX" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "unexpected head ref contents: $HEAD_HEX" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$REPO_DIR/.hgit/workspace/stage.hgi" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "0" ]; then
    echo "stage entry_count should be 0 after commit, got $ENTRY_COUNT" >&2
    exit 1
fi
