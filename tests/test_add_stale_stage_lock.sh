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
    printf 'hello stale lock\n' >note.txt
    printf '999999\n' >.hgit/workspace/stage.hgi.lock
)

stdout_file="$TMP_DIR/add-stale-lock.stdout"
stderr_file="$TMP_DIR/add-stale-lock.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add note.txt
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for add with stale stage lock: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for add with stale stage lock" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for add with stale stage lock" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -e "$REPO_DIR/.hgit/workspace/stage.hgi.lock" ]; then
    echo "stale stage lock should be reclaimed and removed" >&2
    exit 1
fi
