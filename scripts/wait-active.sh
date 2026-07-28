#!/usr/bin/env bash
# Wait until DummyServer answers GET /active on 127.0.0.1:<port>.
#
# Usage: scripts/wait-active.sh <port> [timeout_seconds]
# Exit 0 when body contains "ok"; non-zero on timeout or bad args.

set -euo pipefail

PORT="${1:-}"
TIMEOUT_SECS="${2:-60}"

if [[ -z "$PORT" || ! "$PORT" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 <port> [timeout_seconds]" >&2
  exit 1
fi

URL="http://127.0.0.1:${PORT}/active"
DEADLINE=$((SECONDS + TIMEOUT_SECS))
DELAY=0.1

echo "Waiting for ${URL} (timeout ${TIMEOUT_SECS}s)..."

while (( SECONDS < DEADLINE )); do
  if BODY="$(curl -sf --max-time 2 "$URL" 2>/dev/null)" && [[ "$BODY" == *ok* ]]; then
    echo "Server ready on port ${PORT}"
    exit 0
  fi
  sleep "$DELAY"
  # Exponential backoff, capped at 2s (Master used up to 5s; keep CI snappy).
  DELAY="$(awk -v d="$DELAY" 'BEGIN { n=d*2; if (n>2) n=2; printf "%.2f", n }')"
done

echo "Timed out waiting for ${URL}" >&2
exit 1
