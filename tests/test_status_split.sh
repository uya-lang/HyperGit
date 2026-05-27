#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

run_status_case() {
    local repo_dir="$1"
    local expected_stdout="$2"
    local stdout_file="$TMP_DIR/$(basename "$repo_dir").stdout"
    local stderr_file="$TMP_DIR/$(basename "$repo_dir").stderr"

    set +e
    (
        cd "$repo_dir"
        "$TMP_DIR/hgx" status
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo "unexpected exit code for status in $repo_dir: got $status want 0" >&2
        cat "$stderr_file" >&2
        exit 1
    fi

    diff -u "$expected_stdout" "$stdout_file"

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for status in $repo_dir" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
}

REPO_UNSTAGED="$TMP_DIR/repo-unstaged"
mkdir -p "$REPO_UNSTAGED"
(
    cd "$REPO_UNSTAGED"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    printf 'alpha' >alpha.txt
)

cat >"$TMP_DIR/repo-unstaged.expected" <<'EOF'
On branch main

No commits yet

Changes not staged for commit:
  new file:   alpha.txt
EOF

run_status_case "$REPO_UNSTAGED" "$TMP_DIR/repo-unstaged.expected"

REPO_SPLIT="$TMP_DIR/repo-split"
mkdir -p "$REPO_SPLIT"
(
    cd "$REPO_SPLIT"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    mkdir -p docs src
    printf 'staged' >src/main.uya
    "$TMP_DIR/hgx" add src >/dev/null 2>&1
    printf 'unstaged change' >src/main.uya
    printf 'readme' >docs/readme.md
)

cat >"$TMP_DIR/repo-split.expected" <<'EOF'
On branch main

No commits yet

Changes to be committed:
  new file:   src/main.uya

Changes not staged for commit:
  new file:   docs/readme.md
  modified:   src/main.uya
EOF

run_status_case "$REPO_SPLIT" "$TMP_DIR/repo-split.expected"
