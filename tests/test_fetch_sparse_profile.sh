#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REMOTE_DIR="$TMP_DIR/remote"
LOCAL_DIR="$TMP_DIR/local"
mkdir -p "$REMOTE_DIR" "$LOCAL_DIR"

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p src docs
    printf 'source\n' >src/main.uya
    printf 'guide\n' >docs/readme.md
    "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
    HGX_AUTHOR_NAME='Remote User' HGX_AUTHOR_EMAIL='remote@example.com' "$TMP_DIR/hgx" commit -m "seed remote" >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    "$TMP_DIR/hgx" sparse remove docs >/dev/null 2>&1
)

stdout_file="$TMP_DIR/fetch.stdout"
stderr_file="$TMP_DIR/fetch.stderr"

set +e
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" fetch "file://$REMOTE_DIR"
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for sparse fetch: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for sparse fetch" >&2
    cat "$stdout_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for sparse fetch" >&2
    cat "$stderr_file" >&2
    exit 1
fi

[ "$(cat "$LOCAL_DIR/src/main.uya")" = "source" ]
[ ! -e "$LOCAL_DIR/docs/readme.md" ]
grep -F '"mode":"exclude"' "$LOCAL_DIR/.hgit/workspace/sparse.json" >/dev/null

HYDRATE_STDOUT="$TMP_DIR/hydrate.stdout"
HYDRATE_STDERR="$TMP_DIR/hydrate.stderr"
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" hydrate docs/readme.md
) >"$HYDRATE_STDOUT" 2>"$HYDRATE_STDERR"

grep -F "hydrate 1/1 docs/readme.md" "$HYDRATE_STDOUT" >/dev/null

if [ -s "$HYDRATE_STDERR" ]; then
    echo "unexpected stderr for sparse hydrate" >&2
    cat "$HYDRATE_STDERR" >&2
    exit 1
fi

[ "$(cat "$LOCAL_DIR/docs/readme.md")" = "guide" ]

STATUS_STDOUT="$TMP_DIR/status.stdout"
STATUS_STDERR="$TMP_DIR/status.stderr"
(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" status
) >"$STATUS_STDOUT" 2>"$STATUS_STDERR"

if [ -s "$STATUS_STDERR" ]; then
    echo "unexpected stderr after sparse fetch hydrate" >&2
    cat "$STATUS_STDERR" >&2
    exit 1
fi

grep -F "nothing to commit" "$STATUS_STDOUT" >/dev/null
