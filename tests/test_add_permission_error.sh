#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+rwx "$TMP_DIR" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    printf 'ok' > readable.txt
    printf 'secret' > unreadable.txt
)

chmod 000 "$REPO_DIR/unreadable.txt"

stdout_file="$TMP_DIR/add.stdout"
stderr_file="$TMP_DIR/add.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add .
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "add . should succeed while skipping unreadable files: got $status" >&2
    exit 1
fi

if [ -s "$stdout_file" ]; then
    echo "unexpected stdout for unreadable add" >&2
    cat "$stdout_file" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stderr" <<'EOF'
warning: skipped unreadable path: unreadable.txt
EOF

diff -u "$TMP_DIR/expected.stderr" "$stderr_file"

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "stage entry_count should be 1 after skipping unreadable file, got $ENTRY_COUNT" >&2
    exit 1
fi
