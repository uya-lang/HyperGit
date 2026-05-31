#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UYA="${UYA:-$HOME/uya/uya/bin/uya}"
HELPER="$ROOT_DIR/tests/http_remote_protocol_probe.py"
SERVER_BIN="build/http_remote_smoke_server"
TMP_DIR="$(mktemp -d)"
SOURCE_REPO="$TMP_DIR/source"
TARGET_REPO="$TMP_DIR/target"
BROKEN_REPO="$TMP_DIR/broken"
TOKEN="secret-token"

cleanup() {
  if [ -n "${RUN_PID:-}" ]; then
    kill "$RUN_PID" 2>/dev/null || true
    wait "$RUN_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p build "$SOURCE_REPO" "$TARGET_REPO"
"$UYA" build src/hgx/main.uya -o "$TMP_DIR/hgx" >/dev/null 2>&1
"$UYA" build src/hypergit/http_remote_smoke_server.uya -o "$SERVER_BIN" >/dev/null 2>&1

free_port() {
python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

run_server() {
  local repo_root="$1"
  local token="$2"
  local max_body="$3"
  local port
  port="$(free_port)"
  "$SERVER_BIN" "$repo_root" "$port" "$token" "$max_body" >"$TMP_DIR/server-${port}.log" 2>&1 &
  RUN_PID=$!
  RUN_PORT="$port"
  sleep 0.2
}

stop_server() {
  if [ -n "${RUN_PID:-}" ]; then
    kill "$RUN_PID" 2>/dev/null || true
    wait "$RUN_PID" 2>/dev/null || true
    RUN_PID=""
    RUN_PORT=""
  fi
}

(
  cd "$SOURCE_REPO"
  "$TMP_DIR/hgx" init >/dev/null 2>&1
  mkdir -p src docs
  printf 'http protocol path\n' >src/main.uya
  printf 'http guide\n' >docs/readme.md
  "$TMP_DIR/hgx" add src docs >/dev/null 2>&1
  HGX_AUTHOR_NAME='Protocol User' HGX_AUTHOR_EMAIL='protocol@example.com' "$TMP_DIR/hgx" commit -m 'seed source' >/dev/null 2>&1
)

(
  cd "$TARGET_REPO"
  "$TMP_DIR/hgx" init >/dev/null 2>&1
)

SOURCE_HEAD="$(tr -d '\n' < "$SOURCE_REPO/.hgit/refs/heads/main")"
MISSING_OBJECT="$(printf '99%.0s' $(seq 1 32))"
ZERO_HEAD="$(printf '00%.0s' $(seq 1 32))"

run_server "$SOURCE_REPO" "$TOKEN" 65536

code="$(curl -sS -o "$TMP_DIR/unauthorized.out" -w '%{http_code}' -H 'Content-Type: application/octet-stream' --data-binary '' "http://127.0.0.1:${RUN_PORT}/objects/batch")"
test "$code" = "401"

code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -o "$TMP_DIR/capabilities.json" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/capabilities")"
test "$code" = "200"
python3 "$HELPER" capabilities-check "$TMP_DIR/capabilities.json" 65536

python3 "$HELPER" batch-request "$TMP_DIR/object-batch.body" "$SOURCE_HEAD" "$MISSING_OBJECT"
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/object-batch.body" -o "$TMP_DIR/object-batch.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/objects/batch")"
test "$code" = "200"
python3 "$HELPER" batch-check "$TMP_DIR/object-batch.out" "$SOURCE_REPO" "$SOURCE_HEAD" "$MISSING_OBJECT"

python3 "$HELPER" fetch-request "$TMP_DIR/fetch.body"
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/fetch.body" -o "$TMP_DIR/fetch.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/fetch")"
test "$code" = "200"
python3 "$HELPER" fetch-check "$TMP_DIR/fetch.out" "$SOURCE_REPO" "$SOURCE_HEAD"
stop_server

run_server "$TARGET_REPO" "$TOKEN" 65536
PUSH_COUNT="$(python3 "$HELPER" push-request "$SOURCE_REPO" "$TMP_DIR/push.body")"
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/push.body" -o "$TMP_DIR/push.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/push?expected_head=${ZERO_HEAD}")"
test "$code" = "200"
python3 "$HELPER" push-check "$TMP_DIR/push.out" "$PUSH_COUNT"
test "$(tr -d '\n' < "$TARGET_REPO/.hgit/refs/heads/main")" = "$SOURCE_HEAD"
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/fetch.body" -o "$TMP_DIR/push-fetch.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/fetch")"
test "$code" = "200"
python3 "$HELPER" fetch-check "$TMP_DIR/push-fetch.out" "$TARGET_REPO" "$SOURCE_HEAD"
stop_server

run_server "$SOURCE_REPO" "$TOKEN" 8
printf '0123456789abcdef' > "$TMP_DIR/oversized.body"
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/oversized.body" -o "$TMP_DIR/oversized.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/objects/batch")"
test "$code" = "413"
stop_server

cp -R "$SOURCE_REPO" "$BROKEN_REPO"
printf '%064d\n' 0 | tr '0' 'z' > "$BROKEN_REPO/.hgit/refs/heads/main"
run_server "$BROKEN_REPO" "$TOKEN" 65536
code="$(curl -sS -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP_DIR/fetch.body" -o "$TMP_DIR/broken-fetch.out" -w '%{http_code}' "http://127.0.0.1:${RUN_PORT}/fetch")"
test "$code" = "500"
rg -q '^internal server error$' "$TMP_DIR/broken-fetch.out"
stop_server
