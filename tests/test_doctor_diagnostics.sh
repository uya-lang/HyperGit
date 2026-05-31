#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

build_hgx() {
    local attempt=1
    while [ "$attempt" -le 5 ]; do
        set +e
        "$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1
        status=$?
        set -e
        if [ "$status" -eq 0 ]; then
            return 0
        fi
        if [ "$status" -ne 139 ]; then
            return "$status"
        fi
        attempt=$((attempt + 1))
    done
    return 139
}

build_hgx

create_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir"
    (
        cd "$repo_dir"
        "$TMP_DIR/hgx" init >/dev/null 2>&1
        mkdir -p src
        printf 'hello doctor\n' >src/main.uya
        "$TMP_DIR/hgx" add src >/dev/null 2>&1
        HGX_AUTHOR_NAME='Test User' HGX_AUTHOR_EMAIL='test@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    )
}

run_doctor_case() {
    local name="$1"
    local repo_dir="$2"
    local expected_exit="$3"
    shift 3

    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"

    set +e
    (
        cd "$repo_dir"
        "$TMP_DIR/hgx" doctor
    ) >"$stdout_file" 2>"$stderr_file"
    local status=$?
    set -e

    if [ "$status" -ne "$expected_exit" ]; then
        echo "unexpected exit code for doctor case $name: got $status want $expected_exit" >&2
        cat "$stdout_file" >&2 || true
        cat "$stderr_file" >&2 || true
        exit 1
    fi

    if [ -s "$stderr_file" ]; then
        echo "unexpected stderr for doctor case $name" >&2
        cat "$stderr_file" >&2
        exit 1
    fi

    for expected in "$@"; do
        grep -F "$expected" "$stdout_file" >/dev/null
    done
}

CLEAN_REPO="$TMP_DIR/repo-clean"
create_repo "$CLEAN_REPO"
run_doctor_case clean "$CLEAN_REPO" 0 "audit: current=1 rotated=0 last=commit" "doctor: ok"

CORRUPT_REPO="$TMP_DIR/repo-corrupt"
create_repo "$CORRUPT_REPO"
HEAD_HEX="$(tr -d '\n' <"$CORRUPT_REPO/.hgit/refs/heads/main")"
CORRUPT_OBJECT="$CORRUPT_REPO/.hgit/objects/loose/${HEAD_HEX:0:2}/${HEAD_HEX:2}"
printf '\x00' >"$CORRUPT_OBJECT"
run_doctor_case corrupt "$CORRUPT_REPO" 1 "doctor: found" "corrupt loose object"

STALE_INDEX_REPO="$TMP_DIR/repo-stale-index"
create_repo "$STALE_INDEX_REPO"
rm -f "$STALE_INDEX_REPO/.hgit/indexes/commit-graph.hgi"
run_doctor_case stale-index "$STALE_INDEX_REPO" 1 "doctor: found" "commit graph index is missing or stale"

AUDIT_REPO="$TMP_DIR/repo-audit-corrupt"
create_repo "$AUDIT_REPO"
printf '{"version":1,"kind":"commit"\n' >"$AUDIT_REPO/.hgit/audit/events.jsonl"
run_doctor_case audit-corrupt "$AUDIT_REPO" 1 "doctor: found" "audit log is invalid"

STATE_REPO="$TMP_DIR/repo-state"
create_repo "$STATE_REPO"
python3 - "$STATE_REPO/.hgit/workspace/state.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["dirty_count"] = 1
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, separators=(",", ":"))
    fh.write("\n")
PY
run_doctor_case workspace-state "$STATE_REPO" 1 "doctor: found" "workspace state mismatch"

STALE_LOCK_REPO="$TMP_DIR/repo-stale-lock"
create_repo "$STALE_LOCK_REPO"
printf '999999\n' >"$STALE_LOCK_REPO/.hgit/workspace/stage.hgi.lock"
run_doctor_case stale-lock "$STALE_LOCK_REPO" 1 "doctor: found" "stale stage lock"
