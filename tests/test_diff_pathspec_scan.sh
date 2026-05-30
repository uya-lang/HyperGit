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
    mkdir -p src private large
    printf 'one\n' >src/main.uya
    printf 'secret\n' >private/secret.txt
    python3 - <<'PY'
from pathlib import Path
root = Path("large")
for i in range(2000):
    (root / f"file-{i:04d}.txt").write_text("x" * 128, encoding="utf-8")
PY
    "$TMP_DIR/hgx" add src private large >/dev/null 2>&1
    HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "base" >/dev/null 2>&1
    printf 'two\n' >src/main.uya
)

chmod 000 "$REPO_DIR/private"

stdout_file="$TMP_DIR/diff.stdout"
stderr_file="$TMP_DIR/diff.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" diff src/main.uya
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for pathspec diff scan: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for pathspec diff scan" >&2
    cat "$stderr_file" >&2
    exit 1
fi

grep -F "diff --hgx a/src/main.uya b/src/main.uya" "$stdout_file" >/dev/null
grep -F "+two" "$stdout_file" >/dev/null
grep -F "1 file changed, 1 insertion(+), 1 deletion(-)" "$stdout_file" >/dev/null
