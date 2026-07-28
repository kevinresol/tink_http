#!/usr/bin/env bash
# Start a DummyServer container-under-test for the container lane.
#
# Usage:
#   scripts/run-container.sh <container> <port>
#   scripts/run-container.sh <container> <port> --foreground
#
# M6 supports container name `node` only (maps to -D server=node on Travix node).
# Build uses dummy-server.hxml via TRAVIX_HXML — never the runner tests.hxml.
#
# Default: start in background, wait for /active, print CONTAINER_PID, exit 0
# leaving the server running for a subsequent probe:
#
#   scripts/run-container.sh node "$PORT"
#   lix run travix node \
#     -D suites=container \
#     -D clients=node \
#     -D endpoints=local \
#     -D port="$PORT" \
#     -D cases=methods,headers,body
#
# Stop (either):
#   curl -sf "http://127.0.0.1:${PORT}/close"   # graceful DummyServer exit
#   kill "$(cat /tmp/tink_http_container_${PORT}.pid)"   # or kill $CONTAINER_PID
#
# CI (M9): `.github/workflows/ci.yml` container cell runs this script, then
# `lix run travix node` with suites=container / clients=node / endpoints=local,
# and always tears down via /close + pid file (see Stop container under test).
#
# --foreground: after /active, wait on the server; INT/TERM/EXIT send /close then kill.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTAINER="${1:-}"
PORT="${2:-}"
FOREGROUND=0
if [[ "${3:-}" == "--foreground" ]]; then
  FOREGROUND=1
fi

usage() {
  echo "usage: $0 <container> <port> [--foreground]" >&2
  echo "  container: node (only; more names later)" >&2
  echo "  port:      listen port for DummyServer" >&2
  exit 1
}

[[ -n "$CONTAINER" && -n "$PORT" && "$PORT" =~ ^[0-9]+$ ]] || usage

case "$CONTAINER" in
  node)
    TRAVIX_TARGET=node
    SERVER=node
    ;;
  *)
    echo "unsupported container: ${CONTAINER} (M6: only 'node')" >&2
    exit 1
    ;;
esac

PID_FILE="/tmp/tink_http_container_${PORT}.pid"
WAIT_SCRIPT="${ROOT}/scripts/wait-active.sh"
WAIT_TIMEOUT_SECS="${WAIT_TIMEOUT_SECS:-60}"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${OLD_PID}" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "refusing to start: pid ${OLD_PID} already recorded for port ${PORT} (${PID_FILE})" >&2
    exit 1
  fi
  rm -f "$PID_FILE"
fi

stop_server() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    curl -sf --max-time 2 "http://127.0.0.1:${PORT}/close" >/dev/null 2>&1 || true
    sleep 0.2
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill "$SERVER_PID" 2>/dev/null || true
      wait "$SERVER_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
}

on_signal() {
  stop_server
  exit 130
}

echo ">> Building/starting container '${CONTAINER}' on port ${PORT} (dummy-server.hxml)"

# M0 canonical DummyServer form — do not rewrite tests.hxml / tests.runner.hxml.
TRAVIX_HXML=dummy-server.hxml lix run travix "$TRAVIX_TARGET" \
  -D "port=${PORT}" \
  -D "server=${SERVER}" &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

trap on_signal INT TERM

if ! "$WAIT_SCRIPT" "$PORT" "$WAIT_TIMEOUT_SECS"; then
  echo "container '${CONTAINER}' failed to become active on port ${PORT}" >&2
  stop_server
  exit 1
fi

echo "CONTAINER_PID=${SERVER_PID}"
echo "Stop: curl -sf http://127.0.0.1:${PORT}/close   # or: kill ${SERVER_PID}"

if [[ "$FOREGROUND" -eq 1 ]]; then
  trap 'stop_server; exit 130' INT TERM
  trap 'stop_server' EXIT
  wait "$SERVER_PID" || true
  trap - EXIT INT TERM
  rm -f "$PID_FILE"
  exit 0
fi

# Background mode: leave server running for the probe.
# disown so the DummyServer job is not SIGHUP'd when this script exits.
trap - INT TERM
disown "$SERVER_PID" 2>/dev/null || true
exit 0
