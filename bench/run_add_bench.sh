#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/build/bench/add/$STAMP"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HGX_BIN="$TMP_DIR/hgx"
BASE_REPO="$TMP_DIR/base-repo"

mkdir -p "$OUT_DIR"

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$HGX_BIN" >/dev/null 2>&1

cat >"$OUT_DIR/machine.txt" <<EOF
timestamp=$(date -Iseconds)
uname=$(uname -a)
cwd=$ROOT
cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo unknown)
EOF

python3 - <<'PY' "$BASE_REPO"
from pathlib import Path
import sys

repo = Path(sys.argv[1])
repo.mkdir(parents=True, exist_ok=True)
PY

(
    cd "$BASE_REPO"
    "$HGX_BIN" init >/dev/null 2>&1
    python3 - <<'PY'
from pathlib import Path

root = Path("src")
for d in range(96):
    sub = root / f"pkg{d:03d}"
    sub.mkdir(parents=True, exist_ok=True)
    for i in range(16):
        (sub / f"file_{i:03d}.txt").write_text(f"seed-{d:03d}-{i:03d}\n", encoding="utf-8")
PY
    "$HGX_BIN" add src >/dev/null 2>&1
    HGX_AUTHOR_NAME='Bench User' HGX_AUTHOR_EMAIL='bench@example.com' "$HGX_BIN" commit -m baseline >/dev/null 2>&1
)

run_timed_add() {
    local repo_dir="$1"
    local workers="$2"
    local pathspec="$3"
    local label="$4"

    local stdout_file="$OUT_DIR/$label.stdout"
    local stderr_file="$OUT_DIR/$label.stderr"
    local time_file="$OUT_DIR/$label.time"
    local start_ms
    local end_ms
    local elapsed_ms

    start_ms="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
    set +e
    (
        cd "$repo_dir"
        env HGX_ADD_PARALLEL_WORKERS="$workers" "$HGX_BIN" add "$pathspec"
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e
    end_ms="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
    elapsed_ms="$((end_ms - start_ms))"
    python3 - <<'PY' "$elapsed_ms" >"$time_file"
import sys
value_ms = int(sys.argv[1])
print(f"{value_ms / 1000:.3f}")
PY

    if [ "$status" -ne 0 ]; then
        echo "benchmark command failed: $label" >&2
        cat "$stderr_file" >&2
        exit 1
    fi

    if [ -s "$stdout_file" ]; then
        echo "unexpected stdout for $label" >&2
        cat "$stdout_file" >&2
        exit 1
    fi

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for $label" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
}

clone_case_repo() {
    local case_name="$1"
    local target="$TMP_DIR/$case_name"
    cp -a "$BASE_REPO" "$target"
    printf '%s' "$target"
}

prepare_single_file_case() {
    local repo_dir="$1"
    python3 - <<'PY' "$repo_dir"
from pathlib import Path
import sys

repo = Path(sys.argv[1])
(repo / "src/pkg048/file_008.txt").write_text("single-file-updated\n", encoding="utf-8")
PY
}

prepare_directory_case() {
    local repo_dir="$1"
    python3 - <<'PY' "$repo_dir"
from pathlib import Path
import sys

repo = Path(sys.argv[1]) / "src/pkg072"
for i in range(16):
    (repo / f"file_{i:03d}.txt").write_text(f"dir-update-{i:03d}\n", encoding="utf-8")
PY
}

SERIAL_SINGLE="$(clone_case_repo serial-single)"
PARALLEL_SINGLE="$(clone_case_repo parallel-single)"
prepare_single_file_case "$SERIAL_SINGLE"
prepare_single_file_case "$PARALLEL_SINGLE"
run_timed_add "$SERIAL_SINGLE" 1 "src/pkg048/file_008.txt" serial_single_file_add
run_timed_add "$PARALLEL_SINGLE" 4 "src/pkg048/file_008.txt" parallel_single_file_add

SERIAL_DIR="$(clone_case_repo serial-dir)"
PARALLEL_DIR="$(clone_case_repo parallel-dir)"
prepare_directory_case "$SERIAL_DIR"
prepare_directory_case "$PARALLEL_DIR"
run_timed_add "$SERIAL_DIR" 1 "src/pkg072" serial_directory_add
run_timed_add "$PARALLEL_DIR" 4 "src/pkg072" parallel_directory_add

FAST_PATH_REPO="$(clone_case_repo fast-path)"
prepare_directory_case "$FAST_PATH_REPO"
run_timed_add "$FAST_PATH_REPO" 4 "src/pkg072" fast_path_warm_add
run_timed_add "$FAST_PATH_REPO" 4 "src/pkg072" fast_path_repeat_add

cat >"$OUT_DIR/commands.txt" <<'EOF'
env HGX_ADD_PARALLEL_WORKERS=1 hgx add src/pkg048/file_008.txt
env HGX_ADD_PARALLEL_WORKERS=4 hgx add src/pkg048/file_008.txt
env HGX_ADD_PARALLEL_WORKERS=1 hgx add src/pkg072
env HGX_ADD_PARALLEL_WORKERS=4 hgx add src/pkg072
env HGX_ADD_PARALLEL_WORKERS=4 hgx add src/pkg072
env HGX_ADD_PARALLEL_WORKERS=4 hgx add src/pkg072
EOF

cat >"$OUT_DIR/summary.md" <<EOF
# HyperGit add benchmark

- serial_single_file_add: $(cat "$OUT_DIR/serial_single_file_add.time")s
- parallel_single_file_add: $(cat "$OUT_DIR/parallel_single_file_add.time")s
- serial_directory_add: $(cat "$OUT_DIR/serial_directory_add.time")s
- parallel_directory_add: $(cat "$OUT_DIR/parallel_directory_add.time")s
- fast_path_warm_add: $(cat "$OUT_DIR/fast_path_warm_add.time")s
- fast_path_repeat_add: $(cat "$OUT_DIR/fast_path_repeat_add.time")s
EOF

printf '%s\n' "$OUT_DIR"
