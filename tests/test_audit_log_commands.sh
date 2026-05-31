#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$HOME/uya/uya/bin/uya" build "$ROOT/src/hgx/main.uya" -o "$TMP_DIR/hgx" >/dev/null 2>&1

CHECKOUT_POLICY_ID="1111111111111111111111111111111111111111111111111111111111111111"
PUSH_POLICY_ID="4444444444444444444444444444444444444444444444444444444444444444"
CHECKOUT_FILE_BYTES=4
PUSH_FILE_BYTES=9437184
CHECKOUT_REPO="$TMP_DIR/checkout-repo"
REMOTE_DIR="$TMP_DIR/remote"
LOCAL_DIR="$TMP_DIR/local"
PEER_DIR="$TMP_DIR/peer"
REMOTE_URI="file://$REMOTE_DIR"

mkdir -p "$CHECKOUT_REPO" "$REMOTE_DIR" "$LOCAL_DIR" "$PEER_DIR"

write_policy() {
    local repo_dir="$1"
    local pathspec="$2"
    local policy_id="$3"
    local dedupe_scope="$4"
    cat >"$repo_dir/.hgit/policy.json" <<EOF
{"version":1,"rules":[{"pathspec":"$pathspec","policy_id":"$policy_id","dedupe_scope":"$dedupe_scope","audit":"enabled","cache_ttl_secs":120}]}
EOF
}

write_big_file() {
    local path="$1"
    local fill="$2"
    python3 - "$path" "$fill" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
fill = sys.argv[2].encode("ascii")
path.write_bytes(fill * 9437184)
PY
}

(
    cd "$CHECKOUT_REPO"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    write_policy "$CHECKOUT_REPO" "main.txt" "$CHECKOUT_POLICY_ID" "repository"
    printf 'one\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Audit User' HGX_AUTHOR_EMAIL='audit@example.com' "$TMP_DIR/hgx" commit -m "first" >/dev/null 2>&1
    printf '%s' "$(tr -d '\n' <.hgit/refs/heads/main)" >"$TMP_DIR/checkout-first-head"

    printf 'two\n' >main.txt
    "$TMP_DIR/hgx" add main.txt >/dev/null 2>&1
    HGX_AUTHOR_NAME='Audit User' HGX_AUTHOR_EMAIL='audit@example.com' "$TMP_DIR/hgx" commit -m "second" >/dev/null 2>&1
    printf '%s' "$(tr -d '\n' <.hgit/refs/heads/main)" >"$TMP_DIR/checkout-second-head"

    "$TMP_DIR/hgx" checkout "$(cat "$TMP_DIR/checkout-first-head")" >/dev/null 2>&1
)

(
    cd "$REMOTE_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
)

(
    cd "$LOCAL_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    write_policy "$LOCAL_DIR" "big.bin" "$PUSH_POLICY_ID" "global"
    write_big_file big.bin A
    "$TMP_DIR/hgx" add big.bin >/dev/null 2>&1
    HGX_AUTHOR_NAME='Audit User' HGX_AUTHOR_EMAIL='audit@example.com' "$TMP_DIR/hgx" commit -m "seed" >/dev/null 2>&1
    printf '%s' "$(tr -d '\n' <.hgit/refs/heads/main)" >"$TMP_DIR/push-head"
    "$TMP_DIR/hgx" push "$REMOTE_URI" >/dev/null 2>&1
)

(
    cd "$PEER_DIR"
    "$TMP_DIR/hgx" init >/dev/null 2>&1
    write_policy "$PEER_DIR" "big.bin" "$PUSH_POLICY_ID" "global"
    "$TMP_DIR/hgx" fetch "$REMOTE_URI" >/dev/null 2>&1
)

CHECKOUT_FIRST_HEAD="$(cat "$TMP_DIR/checkout-first-head")"
CHECKOUT_SECOND_HEAD="$(cat "$TMP_DIR/checkout-second-head")"
PUSH_HEAD="$(cat "$TMP_DIR/push-head")"

python3 - "$CHECKOUT_REPO" "$LOCAL_DIR" "$PEER_DIR" "$REMOTE_DIR" "$CHECKOUT_FIRST_HEAD" "$CHECKOUT_SECOND_HEAD" "$PUSH_HEAD" "$CHECKOUT_POLICY_ID" "$PUSH_POLICY_ID" "$CHECKOUT_FILE_BYTES" "$PUSH_FILE_BYTES" <<'PY'
import json
import sys
from pathlib import Path

checkout_repo, local_dir, peer_dir, remote_dir, checkout_first_head, checkout_second_head, push_head, checkout_policy_id, push_policy_id, checkout_file_bytes, push_file_bytes = sys.argv[1:]
checkout_file_bytes = int(checkout_file_bytes)
push_file_bytes = int(push_file_bytes)
remote_uri = f"file://{remote_dir}"

checkout_log = Path(checkout_repo) / ".hgit" / "audit" / "events.jsonl"
local_log = Path(local_dir) / ".hgit" / "audit" / "events.jsonl"
peer_log = Path(peer_dir) / ".hgit" / "audit" / "events.jsonl"

assert checkout_log.is_file(), f"missing checkout audit log: {checkout_log}"
assert local_log.is_file(), f"missing local audit log: {local_log}"
assert peer_log.is_file(), f"missing peer audit log: {peer_log}"

checkout_events = [json.loads(line) for line in checkout_log.read_text().splitlines() if line.strip()]
local_events = [json.loads(line) for line in local_log.read_text().splitlines() if line.strip()]
peer_events = [json.loads(line) for line in peer_log.read_text().splitlines() if line.strip()]

assert [event["kind"] for event in checkout_events] == ["commit", "commit", "checkout"], checkout_events
assert [event["kind"] for event in local_events] == ["commit", "push"], local_events
assert [event["kind"] for event in peer_events] == ["fetch"], peer_events

commit_event = checkout_events[1]
assert commit_event["target"] == "main", commit_event
assert commit_event["head_before"] == checkout_first_head, commit_event
assert commit_event["head_after"] == checkout_second_head, commit_event
assert commit_event["policy_id"] == checkout_policy_id, commit_event
assert commit_event["dedupe_scope"] == "repository", commit_event
assert commit_event["audit_enabled"] is True, commit_event
assert commit_event["affected_path_count"] == 1, commit_event
assert commit_event["affected_byte_count"] == checkout_file_bytes, commit_event

checkout_event = checkout_events[2]
assert checkout_event["target"] == checkout_first_head, checkout_event
assert checkout_event["head_before"] == checkout_second_head, checkout_event
assert checkout_event["head_after"] == checkout_first_head, checkout_event
assert checkout_event["policy_id"] == checkout_policy_id, checkout_event
assert checkout_event["dedupe_scope"] == "repository", checkout_event
assert checkout_event["audit_enabled"] is True, checkout_event
assert checkout_event["affected_path_count"] == 1, checkout_event
assert checkout_event["affected_byte_count"] == checkout_file_bytes, checkout_event

push_event = local_events[1]
assert push_event["target"] == remote_uri, push_event
assert push_event["head_before"] == "", push_event
assert push_event["head_after"] == push_head, push_event
assert push_event["policy_id"] == push_policy_id, push_event
assert push_event["dedupe_scope"] == "global", push_event
assert push_event["audit_enabled"] is True, push_event
assert push_event["affected_path_count"] == 1, push_event
assert push_event["affected_byte_count"] == push_file_bytes, push_event

fetch_event = peer_events[0]
assert fetch_event["target"] == remote_uri, fetch_event
assert fetch_event["head_before"] == "", fetch_event
assert fetch_event["head_after"] == push_head, fetch_event
assert fetch_event["policy_id"] == push_policy_id, fetch_event
assert fetch_event["dedupe_scope"] == "global", fetch_event
assert fetch_event["audit_enabled"] is True, fetch_event
assert fetch_event["affected_path_count"] == 1, fetch_event
assert fetch_event["affected_byte_count"] == push_file_bytes, fetch_event
PY
