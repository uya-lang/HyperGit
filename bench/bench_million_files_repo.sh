#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE_COUNT="${1:-1000000}"
WORDS_PER_FILE="${2:-2048}"
DIR_COUNT="${3:-1000}"
MIN_SPEEDUP="${HGX_BENCH_MIN_SPEEDUP:-2.0}"
REPEATS="${HGX_BENCH_REPEATS:-1}"
KEEP_REPOS="${HGX_BENCH_KEEP_REPOS:-0}"
CLEAN_ARTIFACTS="${HGX_BENCH_CLEAN_ARTIFACTS:-1}"
HGX_BUILD_OPT="${HGX_BENCH_BUILD_OPT:--O3}"
HGX_BUILD_CFLAGS="${HGX_BENCH_CFLAGS:--std=c99 -O3 -g0 -fno-builtin}"
GIT_PRELOAD_INDEX="${HGX_BENCH_GIT_PRELOAD_INDEX:-false}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/build/bench/million-files/$STAMP"
HGX_BUILD_SPLIT_C_DIR="$OUT_DIR/uyacache"
DATA_DIR="$OUT_DIR/data"
DATA_FILES="$DATA_DIR/files"
BIN="$OUT_DIR/hgx"

STEPS=(
  init
  status_untracked
  add_initial
  status_staged
  commit_initial
  status_clean
  log_initial
  diff_workspace
  add_modified
  commit_modified
  log_modified
  diff_commit_to_commit
)

GIT=(git -c "core.preloadIndex=$GIT_PRELOAD_INDEX")

declare -A BEST_MS
declare -A BEST_STATUS
declare -A BEST_STDOUT_LINES
declare -A BEST_STDOUT_BYTES
declare -A BEST_STDERR_BYTES

mkdir -p "$OUT_DIR" "$DATA_FILES"
: >"$OUT_DIR/metrics.env"

now_ms() {
  date +%s%3N
}

write_metric() {
  printf '%s=%s\n' "$1" "$2" >>"$OUT_DIR/metrics.env"
}

metric_key() {
  printf '%s:%s' "$1" "$2"
}

record_best() {
  local tool="$1"
  local step="$2"
  local ms="$3"
  local status="$4"
  local stdout_lines="$5"
  local stdout_bytes="$6"
  local stderr_bytes="$7"
  local key
  key="$(metric_key "$tool" "$step")"

  if [ -z "${BEST_MS[$key]+set}" ] || [ "$ms" -lt "${BEST_MS[$key]}" ]; then
    BEST_MS[$key]="$ms"
    BEST_STATUS[$key]="$status"
    BEST_STDOUT_LINES[$key]="$stdout_lines"
    BEST_STDOUT_BYTES[$key]="$stdout_bytes"
    BEST_STDERR_BYTES[$key]="$stderr_bytes"
  fi
}

copy_dataset() {
  local target_repo="$1"
  mkdir -p "$target_repo"
  if ! cp -a --reflink=auto "$DATA_FILES" "$target_repo/files" 2>/dev/null; then
    cp -a "$DATA_FILES" "$target_repo/files"
  fi
}

run_timed() {
  local label="$1"
  local repo="$2"
  shift 2

  local stdout_file="$OUT_DIR/$label.stdout"
  local stderr_file="$OUT_DIR/$label.stderr"
  local start_ms
  local end_ms
  local status
  local elapsed_ms
  local stdout_bytes
  local stdout_lines
  local stderr_bytes

  start_ms="$(now_ms)"
  set +e
  (cd "$repo" && "$@") >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  end_ms="$(now_ms)"
  elapsed_ms="$((end_ms - start_ms))"
  stdout_bytes="$(wc -c <"$stdout_file")"
  stdout_lines="$(wc -l <"$stdout_file")"
  stderr_bytes="$(wc -c <"$stderr_file")"

  write_metric "${label}_status" "$status"
  write_metric "${label}_ms" "$elapsed_ms"
  write_metric "${label}_stdout_bytes" "$stdout_bytes"
  write_metric "${label}_stdout_lines" "$stdout_lines"
  write_metric "${label}_stderr_bytes" "$stderr_bytes"

  LAST_MS="$elapsed_ms"
  LAST_STATUS="$status"
  LAST_STDOUT_LINES="$stdout_lines"
  LAST_STDOUT_BYTES="$stdout_bytes"
  LAST_STDERR_BYTES="$stderr_bytes"

  if [ "$status" -ne 0 ]; then
    echo "benchmark command failed: $label" >&2
    echo "stdout: $stdout_file" >&2
    echo "stderr: $stderr_file" >&2
    tail -200 "$stderr_file" >&2 || true
    exit "$status"
  fi
}

run_sample() {
  local tool="$1"
  local step="$2"
  local repeat="$3"
  local repo="$4"
  shift 4
  local label="${tool}_${step}_r${repeat}"

  run_timed "$label" "$repo" "$@"
  record_best "$tool" "$step" "$LAST_MS" "$LAST_STATUS" "$LAST_STDOUT_LINES" "$LAST_STDOUT_BYTES" "$LAST_STDERR_BYTES"
}

write_speedup_metrics() {
  local step="$1"
  local hgx_ms="$2"
  local git_ms="$3"
  local speedup
  local pass

  speedup="$(awk -v git_ms="$git_ms" -v hgx_ms="$hgx_ms" 'BEGIN {
    if (hgx_ms <= 0) {
      print "inf";
    } else {
      printf "%.3f", git_ms / hgx_ms;
    }
  }')"
  pass="$(awk -v git_ms="$git_ms" -v hgx_ms="$hgx_ms" -v min="$MIN_SPEEDUP" 'BEGIN {
    if (hgx_ms <= 0 && git_ms > 0) {
      print "yes";
    } else if (hgx_ms > 0 && git_ms / hgx_ms >= min) {
      print "yes";
    } else {
      print "no";
    }
  }')"

  write_metric "${step}_speedup" "$speedup"
  write_metric "${step}_pass" "$pass"
  STEP_SPEEDUP="$speedup"
  STEP_PASS="$pass"
}

cleanup_heavy_artifacts() {
  if [ "$KEEP_REPOS" != "0" ] || [ "$CLEAN_ARTIFACTS" != "1" ]; then
    return
  fi
  rm -rf "$DATA_DIR" "$OUT_DIR"/run-* "$HGX_BUILD_SPLIT_C_DIR" "$BIN"
}

if ! [[ "$REPEATS" =~ ^[0-9]+$ ]] || [ "$REPEATS" -lt 1 ]; then
  echo "HGX_BENCH_REPEATS must be a positive integer" >&2
  exit 2
fi

cat >"$OUT_DIR/machine.txt" <<EOF
timestamp=$(date -Iseconds)
command=bash bench/bench_million_files_repo.sh $FILE_COUNT $WORDS_PER_FILE $DIR_COUNT
min_speedup=$MIN_SPEEDUP
repeats=$REPEATS
keep_repos=$KEEP_REPOS
clean_artifacts=$CLEAN_ARTIFACTS
hgx_build_opt=$HGX_BUILD_OPT
hgx_build_cflags=$HGX_BUILD_CFLAGS
hgx_build_split_c_dir=$HGX_BUILD_SPLIT_C_DIR
git_preload_index=$GIT_PRELOAD_INDEX
uname=$(uname -a)
cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || true)
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo unknown)
git_version=$(git --version)
uya=$("${UYA:-$HOME/uya/uya/bin/uya}" --version 2>/dev/null || true)
filesystem=$(df -h "$ROOT" | tail -1)
inodes=$(df -i "$ROOT" | tail -1)
HGX_ADD_PARALLEL_WORKERS=${HGX_ADD_PARALLEL_WORKERS:-}
HGX_ADD_PROFILE=${HGX_ADD_PROFILE:-}
HGX_STATUS_PROFILE=${HGX_STATUS_PROFILE:-}
HGX_COMMIT_PROFILE=${HGX_COMMIT_PROFILE:-}
HGX_DIFF_PROFILE=${HGX_DIFF_PROFILE:-}
EOF

CFLAGS="$HGX_BUILD_CFLAGS" "${UYA:-$HOME/uya/uya/bin/uya}" build "$ROOT/src/hgx/main.uya" -o "$BIN" "$HGX_BUILD_OPT" --split-c-dir="$HGX_BUILD_SPLIT_C_DIR" >"$OUT_DIR/build.stdout" 2>"$OUT_DIR/build.stderr"

generate_start="$(now_ms)"
python3 - "$DATA_FILES" "$FILE_COUNT" "$WORDS_PER_FILE" "$DIR_COUNT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
file_count = int(sys.argv[2])
words_per_file = int(sys.argv[3])
dir_count = max(1, int(sys.argv[4]))

words = [
    "able", "about", "above", "accept", "across", "active", "actor", "adapt",
    "after", "again", "agent", "agree", "ahead", "album", "alert", "align",
    "allow", "along", "amber", "anchor", "answer", "apple", "apply", "area",
    "array", "artist", "asset", "atlas", "audio", "author", "auto", "awake",
    "balance", "base", "beacon", "before", "better", "binary", "blend", "block",
    "border", "branch", "bright", "build", "bundle", "button", "byte", "cache",
    "canvas", "carbon", "carry", "case", "center", "change", "chart", "check",
    "choice", "city", "clean", "client", "cloud", "code", "color", "column",
    "commit", "common", "copy", "core", "craft", "create", "cursor", "data",
    "debug", "delta", "design", "detail", "device", "diff", "direct", "domain",
    "draft", "drive", "dynamic", "early", "edge", "editor", "effect", "engine",
    "entry", "equal", "event", "exact", "export", "fabric", "factor", "fast",
    "field", "file", "filter", "final", "flow", "focus", "format", "frame",
    "fresh", "future", "garden", "global", "graph", "green", "group", "guide",
    "handle", "happy", "hash", "header", "height", "hello", "hidden", "history",
    "image", "import", "index", "input", "inside", "item", "join", "json",
    "kernel", "label", "large", "layer", "layout", "learn", "level", "light",
    "limit", "line", "local", "logic", "main", "manage", "manifest", "map",
    "margin", "marker", "memory", "merge", "metric", "model", "module", "native",
    "node", "normal", "object", "open", "option", "output", "panel", "parallel",
    "parent", "parser", "path", "payload", "pixel", "policy", "prefix", "print",
    "profile", "query", "queue", "range", "ready", "record", "reduce", "ref",
    "remote", "render", "repo", "result", "right", "root", "route", "schema",
    "scope", "screen", "search", "second", "segment", "serial", "server", "shape",
    "shard", "signal", "simple", "size", "small", "source", "sparse", "split",
    "stable", "stage", "state", "status", "store", "stream", "string", "style",
    "system", "table", "target", "task", "text", "thread", "time", "token",
    "trace", "tree", "update", "valid", "value", "vector", "version", "view",
    "virtual", "worker", "world", "write",
]

def make_payload(index: int) -> bytes:
    state = (index + 1) & 0xFFFFFFFF
    parts = []
    for _ in range(words_per_file):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        parts.append(words[state % len(words)])
    return (" ".join(parts) + "\n").encode("ascii")

for directory_index in range(dir_count):
    (root / f"d{directory_index:04d}").mkdir(parents=True, exist_ok=True)

for index in range(file_count):
    directory_index = index % dir_count
    path = root / f"d{directory_index:04d}" / f"file{index:07d}.txt"
    with open(path, "wb") as handle:
        handle.write(make_payload(index))

    if index and index % 10000 == 0:
        print(f"generated {index}/{file_count}", flush=True)
PY
generate_finish="$(now_ms)"
write_metric "generate_ms" "$((generate_finish - generate_start))"

repeat=1
while [ "$repeat" -le "$REPEATS" ]; do
  RUN_DIR="$OUT_DIR/run-$repeat"
  HGX_REPO="$RUN_DIR/hgx-repo"
  GIT_REPO="$RUN_DIR/git-repo"
  mkdir -p "$RUN_DIR"
  copy_dataset "$HGX_REPO"
  copy_dataset "$GIT_REPO"

  run_sample hgx init "$repeat" "$HGX_REPO" "$BIN" init
  run_sample git init "$repeat" "$GIT_REPO" "${GIT[@]}" init

  run_sample hgx status_untracked "$repeat" "$HGX_REPO" "$BIN" status
  run_sample git status_untracked "$repeat" "$GIT_REPO" "${GIT[@]}" status --untracked-files=all

  run_sample hgx add_initial "$repeat" "$HGX_REPO" env HGX_ADD_PARALLEL_WORKERS="${HGX_ADD_PARALLEL_WORKERS:-0}" "$BIN" add files
  run_sample git add_initial "$repeat" "$GIT_REPO" "${GIT[@]}" add --verbose files

  run_sample hgx status_staged "$repeat" "$HGX_REPO" "$BIN" status
  run_sample git status_staged "$repeat" "$GIT_REPO" "${GIT[@]}" status --untracked-files=all

  run_sample hgx commit_initial "$repeat" "$HGX_REPO" env HGX_AUTHOR_NAME=bench HGX_AUTHOR_EMAIL=bench@example.test "$BIN" commit -m "bench million files baseline"
  run_sample git commit_initial "$repeat" "$GIT_REPO" "${GIT[@]}" -c user.name=bench -c user.email=bench@example.test commit -m "bench million files baseline"

  run_sample hgx status_clean "$repeat" "$HGX_REPO" "$BIN" status
  run_sample git status_clean "$repeat" "$GIT_REPO" "${GIT[@]}" status

  run_sample hgx log_initial "$repeat" "$HGX_REPO" "$BIN" log
  run_sample git log_initial "$repeat" "$GIT_REPO" "${GIT[@]}" log --stat --summary

  HGX_BASE_COMMIT="$(awk '/^commit / { print $2; exit }' "$OUT_DIR/hgx_log_initial_r${repeat}.stdout")"
  GIT_BASE_COMMIT="$(cd "$GIT_REPO" && "${GIT[@]}" rev-parse HEAD)"
  write_metric "hgx_base_commit_r${repeat}" "$HGX_BASE_COMMIT"
  write_metric "git_base_commit_r${repeat}" "$GIT_BASE_COMMIT"

  python3 - "$HGX_REPO/files/d0000/file0000000.txt" "$GIT_REPO/files/d0000/file0000000.txt" "$WORDS_PER_FILE" <<'PY'
import sys
from pathlib import Path

payload = ("updated " * int(sys.argv[3])).strip() + "\n"
for raw_path in sys.argv[1:3]:
    Path(raw_path).write_text(payload, encoding="ascii")
PY

  run_sample hgx diff_workspace "$repeat" "$HGX_REPO" "$BIN" diff
  run_sample git diff_workspace "$repeat" "$GIT_REPO" "${GIT[@]}" diff

  run_sample hgx add_modified "$repeat" "$HGX_REPO" "$BIN" add files/d0000/file0000000.txt
  run_sample git add_modified "$repeat" "$GIT_REPO" "${GIT[@]}" add --verbose files/d0000/file0000000.txt

  run_sample hgx commit_modified "$repeat" "$HGX_REPO" env HGX_AUTHOR_NAME=bench HGX_AUTHOR_EMAIL=bench@example.test "$BIN" commit -m "bench single file update"
  run_sample git commit_modified "$repeat" "$GIT_REPO" "${GIT[@]}" -c user.name=bench -c user.email=bench@example.test commit -m "bench single file update"

  run_sample hgx log_modified "$repeat" "$HGX_REPO" "$BIN" log
  run_sample git log_modified "$repeat" "$GIT_REPO" "${GIT[@]}" log --stat --summary

  HGX_HEAD_COMMIT="$(awk '/^commit / { print $2; exit }' "$OUT_DIR/hgx_log_modified_r${repeat}.stdout")"
  GIT_HEAD_COMMIT="$(cd "$GIT_REPO" && "${GIT[@]}" rev-parse HEAD)"
  write_metric "hgx_head_commit_r${repeat}" "$HGX_HEAD_COMMIT"
  write_metric "git_head_commit_r${repeat}" "$GIT_HEAD_COMMIT"

  run_sample hgx diff_commit_to_commit "$repeat" "$HGX_REPO" "$BIN" diff "$HGX_BASE_COMMIT" "$HGX_HEAD_COMMIT"
  run_sample git diff_commit_to_commit "$repeat" "$GIT_REPO" "${GIT[@]}" diff "$GIT_BASE_COMMIT" "$GIT_HEAD_COMMIT"

  repeat="$((repeat + 1))"
done

cat >"$OUT_DIR/summary.md" <<EOF
# HyperGit million-file command benchmark

- files: $FILE_COUNT
- words_per_file: $WORDS_PER_FILE
- directories: $DIR_COUNT
- min_speedup: $MIN_SPEEDUP
- repeats: $REPEATS
- output: $OUT_DIR

| step | hgx_ms | git_ms | git/hgx | pass | hgx_stdout_lines | git_stdout_lines | hgx_stderr_bytes | git_stderr_bytes |
| --- | ---: | ---: | ---: | :---: | ---: | ---: | ---: | ---: |
EOF

failures=0
for step in "${STEPS[@]}"; do
  hgx_key="$(metric_key hgx "$step")"
  git_key="$(metric_key git "$step")"
  hgx_ms="${BEST_MS[$hgx_key]}"
  git_ms="${BEST_MS[$git_key]}"

  write_metric "hgx_${step}_ms" "$hgx_ms"
  write_metric "git_${step}_ms" "$git_ms"
  write_metric "hgx_${step}_status" "${BEST_STATUS[$hgx_key]}"
  write_metric "git_${step}_status" "${BEST_STATUS[$git_key]}"
  write_speedup_metrics "$step" "$hgx_ms" "$git_ms"

  if [ "$STEP_PASS" != "yes" ]; then
    failures="$((failures + 1))"
  fi

  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$step" \
    "$hgx_ms" \
    "$git_ms" \
    "$STEP_SPEEDUP" \
    "$STEP_PASS" \
    "${BEST_STDOUT_LINES[$hgx_key]}" \
    "${BEST_STDOUT_LINES[$git_key]}" \
    "${BEST_STDERR_BYTES[$hgx_key]}" \
    "${BEST_STDERR_BYTES[$git_key]}" >>"$OUT_DIR/summary.md"
done

cleanup_heavy_artifacts

printf '%s\n' "$OUT_DIR"

if [ "$failures" -ne 0 ]; then
  echo "benchmark failed: $failures step(s) below ${MIN_SPEEDUP}x; see $OUT_DIR/summary.md" >&2
  exit 1
fi
