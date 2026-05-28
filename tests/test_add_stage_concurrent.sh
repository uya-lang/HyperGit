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
    mkdir -p src docs
    python3 - <<'PY'
from pathlib import Path
root = Path(".")
(root / "src" / "main.uya").write_text("a" * (4 * 1024 * 1024), encoding="utf-8")
(root / "docs" / "readme.md").write_text("b" * (4 * 1024 * 1024), encoding="utf-8")
PY
)

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add src
) >"$TMP_DIR/add_src.stdout" 2>"$TMP_DIR/add_src.stderr" &
PID_SRC=$!

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" add docs
) >"$TMP_DIR/add_docs.stdout" 2>"$TMP_DIR/add_docs.stderr" &
PID_DOCS=$!

wait "$PID_SRC"
wait "$PID_DOCS"

for name in add_src add_docs; do
    if [ -s "$TMP_DIR/$name.stdout" ]; then
        echo "unexpected stdout for $name" >&2
        cat "$TMP_DIR/$name.stdout" >&2
        exit 1
    fi
    if [ -s "$TMP_DIR/$name.stderr" ]; then
        echo "unexpected stderr for $name" >&2
        cat "$TMP_DIR/$name.stderr" >&2
        exit 1
    fi
done

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
if [ ! -f "$STAGE_FILE" ]; then
    echo "missing stage file after concurrent add" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "2" ]; then
    echo "unexpected concurrent stage entry_count: got $ENTRY_COUNT want 2" >&2
    od -An -t x1 "$STAGE_FILE" >&2
    exit 1
fi

STRINGS_OUT="$TMP_DIR/stage.strings"
strings "$STAGE_FILE" >"$STRINGS_OUT"
grep -F "src/main.uya" "$STRINGS_OUT" >/dev/null
grep -F "docs/readme.md" "$STRINGS_OUT" >/dev/null

OBJECT_COUNT="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT" != "2" ]; then
    echo "unexpected loose object count after concurrent add: got $OBJECT_COUNT want 2" >&2
    find "$REPO_DIR/.hgit/objects/loose" -maxdepth 3 -print >&2
    exit 1
fi
