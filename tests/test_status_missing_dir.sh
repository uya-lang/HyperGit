#!/usr/bin/env bash
set -euo pipefail

# Regression test: a committed file whose parent directory is later removed must
# be reported as deleted, not abort status with "failed to inspect repository
# status". Previously status_open_dir_for_change aborted when the directory was
# gone; it now falls back to a full-path lstat.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1
HGX="$TMP_DIR/hgx"

REPO_DIR="$TMP_DIR/repo"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$HGX" init >/dev/null 2>&1
    mkdir -p sub/deep
    printf 'a\n' >sub/a.txt
    printf 'b\n' >sub/deep/b.txt
    printf 'root\n' >root.txt
    "$HGX" add root.txt sub/a.txt sub/deep/b.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$HGX" commit -m "first" >/dev/null 2>&1
)

# Remove an entire tracked directory subtree.
rm -rf "$REPO_DIR/sub"

stdout_file="$TMP_DIR/status.stdout"
stderr_file="$TMP_DIR/status.stderr"
set +e
( cd "$REPO_DIR" && "$HGX" status ) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "status aborted after a tracked directory was removed: exit $status" >&2
    cat "$stderr_file" >&2
    exit 1
fi
if [ -s "$stderr_file" ]; then
    echo "unexpected stderr from status" >&2
    cat "$stderr_file" >&2
    exit 1
fi

# Both files under the removed directory must be reported as deleted.
grep -F "deleted:" "$stdout_file" | grep -F "sub/a.txt" >/dev/null
grep -F "deleted:" "$stdout_file" | grep -F "sub/deep/b.txt" >/dev/null

echo "test_status_missing_dir: OK"
