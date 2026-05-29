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
    printf 'target' >src/main.uya
    printf 'secret' >private/secret.txt
    python3 - <<'PY'
from pathlib import Path
root = Path("large")
for i in range(2000):
    (root / f"file-{i:04d}.txt").write_text("x" * 128, encoding="utf-8")
PY
)

chmod 000 "$REPO_DIR/private"

stdout_file="$TMP_DIR/add.stdout"
stderr_file="$TMP_DIR/add.stderr"

set +e
(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add src/main.uya
) >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "unexpected exit code for pathspec add: got $status want 0" >&2
    cat "$stderr_file" >&2
    exit 1
fi

printf 'src/main.uya\n' >"$TMP_DIR/expected.stdout"
diff -u "$TMP_DIR/expected.stdout" "$stdout_file"

if [ -s "$stderr_file" ]; then
    echo "unexpected stderr for pathspec add" >&2
    cat "$stderr_file" >&2
    exit 1
fi

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "stage entry_count should be 1 after pathspec add, got $ENTRY_COUNT" >&2
    exit 1
fi

OBJECT_COUNT="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT" != "1" ]; then
    echo "pathspec add should only publish the requested file object: got $OBJECT_COUNT" >&2
    find "$REPO_DIR/.hgit/objects/loose" -maxdepth 3 -print >&2
    exit 1
fi
