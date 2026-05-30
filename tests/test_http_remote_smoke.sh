#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UYA="${UYA:-$HOME/uya/uya/bin/uya}"
SERVER_BIN="build/http_remote_smoke_server"
TEST_ROOT="build/http-remote-smoke"
REPO_ROOT="$TEST_ROOT/repo"

mkdir -p build
rm -rf "$TEST_ROOT"
mkdir -p "$REPO_ROOT/.hgit/objects/loose" "$REPO_ROOT/.hgit/refs/heads"

"$UYA" build src/hypergit/http_remote_smoke_server.uya -o "$SERVER_BIN"

free_port() {
python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

run_once() {
  local port="$1"
  local token="$2"
  local max_body="$3"
  "$SERVER_BIN" "$REPO_ROOT" "$port" "$token" "$max_body" &
  RUN_PID=$!
}

stop_server() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

port="$(free_port)"
run_once "$port" "secret-token" "65536"
pid="$RUN_PID"
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 0.2
code="$(curl -sS -o "$TEST_ROOT/unauthorized.out" -w '%{http_code}' "http://127.0.0.1:${port}/capabilities")"
test "$code" = "401"
stop_server "$pid"
trap - EXIT

port="$(free_port)"
run_once "$port" "secret-token" "65536"
pid="$RUN_PID"
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 0.2
code="$(curl -sS -H 'Authorization: Bearer secret-token' -o "$TEST_ROOT/capabilities.json" -w '%{http_code}' "http://127.0.0.1:${port}/capabilities")"
test "$code" = "200"
rg -q '"service":"hypergit-http-remote"' "$TEST_ROOT/capabilities.json"
rg -q '"auth_required":true' "$TEST_ROOT/capabilities.json"
stop_server "$pid"
trap - EXIT

port="$(free_port)"
run_once "$port" "secret-token" "8"
pid="$RUN_PID"
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 0.2
printf '0123456789abcdef' > "$TEST_ROOT/oversized.body"
code="$(curl -sS -H 'Authorization: Bearer secret-token' -H 'Content-Type: application/octet-stream' --data-binary @"$TEST_ROOT/oversized.body" -o "$TEST_ROOT/oversized.out" -w '%{http_code}' "http://127.0.0.1:${port}/objects/batch")"
test "$code" = "413"
stop_server "$pid"
trap - EXIT
