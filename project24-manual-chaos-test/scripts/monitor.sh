#!/bin/bash
# Synthetic health monitor: polls a URL every INTERVAL seconds and logs one line per check:
#   <utc-iso-time> <epoch-ms> <http-code> <latency-s> <UP|DOWN>
# UP = HTTP 200 within the timeout; anything else (refused, timeout, 5xx) = DOWN.
# State changes are also announced with a "### STATE CHANGE" line on stderr.
# Usage: ./monitor.sh <url> [log-file] [interval-seconds]    (Ctrl+C to stop)
set -uo pipefail

URL="${1:?Usage: $0 <url> [log-file] [interval-seconds]}"
LOG="${2:-}"
INTERVAL="${3:-1}"
TIMEOUT=2
PREV=""

[ -n "$LOG" ] && mkdir -p "$(dirname "$LOG")"

while true; do
  read -r MS ISO < <(date -u '+%s%3N %Y-%m-%dT%H:%M:%S.%3NZ')
  RESULT=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time "$TIMEOUT" "$URL" 2>/dev/null)
  read -r CODE LATENCY <<<"${RESULT:-000 $TIMEOUT}"
  if [ "$CODE" = "200" ]; then STATE=UP; else STATE=DOWN; fi

  LINE="$ISO $MS $CODE $LATENCY $STATE"
  if [ -n "$LOG" ]; then echo "$LINE" >>"$LOG"; else echo "$LINE"; fi

  if [ -n "$PREV" ] && [ "$STATE" != "$PREV" ]; then
    echo "### STATE CHANGE $ISO $PREV -> $STATE (http $CODE)" >&2
  fi
  PREV="$STATE"

  sleep "$INTERVAL"
done
