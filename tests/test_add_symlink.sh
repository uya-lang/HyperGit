#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

REPO_DIR="$TMP_DIR/repo"
LINK_PATH="link.txt"
mkdir -p "$REPO_DIR"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    ln -s docs/readme.md "$LINK_PATH"
)

run_and_expect_clean_io() {
    local name="$1"
    shift
    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"

    set +e
    (
        cd "$REPO_DIR"
        "$@"
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for $name: got $status want 0" >&2
        cat "$stderr_file" >&2
        exit 1
    fi

    if [ -s "$stdout_file" ]; then
        echo "unexpected stdout for $name" >&2
        cat "$stdout_file" >&2
        exit 1
    fi

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for $name" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
}

run_and_expect_clean_io add_symlink "$TMP_DIR/hgx" add "$LINK_PATH"

STAGE_FILE="$REPO_DIR/.hgit/workspace/stage.hgi"
if [ ! -f "$STAGE_FILE" ]; then
    echo "missing stage file after symlink add" >&2
    exit 1
fi

ENTRY_COUNT="$(od -An -t u8 -j 40 -N 8 "$STAGE_FILE" | awk '{print $1}')"
if [ "$ENTRY_COUNT" != "1" ]; then
    echo "unexpected stage entry_count after symlink add: got $ENTRY_COUNT want 1" >&2
    exit 1
fi

MODE_OFFSET="$((124 + ${#LINK_PATH}))"
FIRST_FILE_MODE="$(od -An -t u4 -j "$MODE_OFFSET" -N 4 "$STAGE_FILE" | awk '{print $1}')"
if [ "$FIRST_FILE_MODE" != "40960" ]; then
    echo "unexpected first file_mode for symlink add: got $FIRST_FILE_MODE want 40960" >&2
    exit 1
fi

OBJECT_COUNT="$(find "$REPO_DIR/.hgit/objects/loose" -type f | wc -l | tr -d ' ')"
if [ "$OBJECT_COUNT" != "1" ]; then
    echo "unexpected loose object count after symlink add: got $OBJECT_COUNT want 1" >&2
    find "$REPO_DIR/.hgit/objects/loose" -maxdepth 3 -print >&2
    exit 1
fi

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status >"$TMP_DIR/status-staged.stdout" 2>"$TMP_DIR/status-staged.stderr"
)

cat >"$TMP_DIR/status-staged.expected" <<'EOF'
On branch main

No commits yet

Changes to be committed:
  new file:   link.txt
EOF

diff -u "$TMP_DIR/status-staged.expected" "$TMP_DIR/status-staged.stdout"

if [ -s "$TMP_DIR/status-staged.stderr" ]; then
    echo "unexpected stderr for staged symlink status" >&2
    cat "$TMP_DIR/status-staged.stderr" >&2
    exit 1
fi

run_and_expect_clean_io commit_symlink env HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "add symlink"

(
    cd "$REPO_DIR"
    "$TMP_DIR/hgx" status >"$TMP_DIR/status-clean.stdout" 2>"$TMP_DIR/status-clean.stderr"
)

cat >"$TMP_DIR/status-clean.expected" <<'EOF'
On branch main

nothing to commit
EOF

diff -u "$TMP_DIR/status-clean.expected" "$TMP_DIR/status-clean.stdout"

if [ -s "$TMP_DIR/status-clean.stderr" ]; then
    echo "unexpected stderr for clean symlink status" >&2
    cat "$TMP_DIR/status-clean.stderr" >&2
    exit 1
fi
