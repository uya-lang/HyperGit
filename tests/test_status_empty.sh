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
)

stdout_file="$TMP_DIR/status.stdout"
stderr_file="$TMP_DIR/status.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for empty status: got $status want 0" >&2
    exit 1
fi

cat >"$TMP_DIR/expected.stdout" <<'EOF'
On branch main

No commits yet

nothing to commit
EOF

diff -u "$TMP_DIR/expected.stdout" "$stdout_file"

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for empty status" >&2
    cat "$stderr_file" >&2
    exit 1
fi
