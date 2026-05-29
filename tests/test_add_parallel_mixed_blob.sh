#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

make_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir"
    (
        cd "$repo_dir"
        "$TMP_DIR/hgx" init >/dev/null 2>&1
        mkdir -p src assets
        local i
        for i in $(seq 1 24); do
            printf 'small-%02d\n' $((i % 9)) >"src/file_$i.txt"
        done
        python3 - <<'PY'
from pathlib import Path

chunk_a = b'abcd1234' * 131072
chunk_b = b'wxyz5678' * 131072
with Path('assets/big_a.bin').open('wb') as f:
    for _ in range(9):
        f.write(chunk_a)
with Path('assets/big_b.bin').open('wb') as f:
    for _ in range(9):
        f.write(chunk_b)
PY
    )
}

run_add() {
    local repo_dir="$1"
    local workers="$2"
    local name="$3"

    set +e
    (
        cd "$repo_dir"
        HGX_ADD_PARALLEL_WORKERS="$workers" "$TMP_DIR/hgx" add src assets
    ) >"$TMP_DIR/$name.stdout" 2>"$TMP_DIR/$name.stderr"
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for $name: got $status want 0" >&2
        cat "$TMP_DIR/$name.stderr" >&2
        exit 1
    fi

    if [ -s "$TMP_DIR/$name.stderr" ]; then
        echo "unexpected stderr for $name" >&2
        cat "$TMP_DIR/$name.stderr" >&2
        exit 1
    fi
}

capture_repo_state() {
    local repo_dir="$1"
    local name="$2"

    (
        cd "$repo_dir"
        "$TMP_DIR/hgx" status
    ) >"$TMP_DIR/$name.status" 2>"$TMP_DIR/$name.status.stderr"

    if [ -s "$TMP_DIR/$name.status.stderr" ]; then
        echo "unexpected stderr for status $name" >&2
        cat "$TMP_DIR/$name.status.stderr" >&2
        exit 1
    fi

    find "$repo_dir/.hgit/objects/loose" -type f | sed "s|$repo_dir/.hgit/objects/loose/||" | sort >"$TMP_DIR/$name.objects"
    find "$repo_dir/.hgit/cache/chunks" -type f | sed "s|$repo_dir/.hgit/cache/chunks/||" | sort >"$TMP_DIR/$name.chunks"
}

SERIAL_REPO="$TMP_DIR/repo-serial"
PARALLEL_REPO="$TMP_DIR/repo-parallel"

make_repo "$SERIAL_REPO"
make_repo "$PARALLEL_REPO"

run_add "$SERIAL_REPO" 1 serial_add
run_add "$PARALLEL_REPO" 4 parallel_add

if [ ! -s "$TMP_DIR/serial_add.stdout" ] || [ ! -s "$TMP_DIR/parallel_add.stdout" ]; then
    echo "expected add to print staged paths for serial and parallel mixed runs" >&2
    exit 1
fi

sort "$TMP_DIR/serial_add.stdout" >"$TMP_DIR/serial_add.sorted"
sort "$TMP_DIR/parallel_add.stdout" >"$TMP_DIR/parallel_add.sorted"
diff -u "$TMP_DIR/serial_add.sorted" "$TMP_DIR/parallel_add.sorted"

capture_repo_state "$SERIAL_REPO" serial
capture_repo_state "$PARALLEL_REPO" parallel

diff -u "$TMP_DIR/serial.status" "$TMP_DIR/parallel.status"
diff -u "$TMP_DIR/serial.objects" "$TMP_DIR/parallel.objects"
diff -u "$TMP_DIR/serial.chunks" "$TMP_DIR/parallel.chunks"

CHUNK_COUNT="$(wc -l <"$TMP_DIR/serial.chunks" | tr -d ' ')"
if [ "$CHUNK_COUNT" -lt 2 ]; then
    echo "expected cached chunks after mixed parallel add, got $CHUNK_COUNT" >&2
    exit 1
fi
