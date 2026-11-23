#!/bin/bash
# Sends a mixed workload to the ALB so the dashboard graphs have data:
#   - fast pages (2xx), slow pages (latency), missing pages (4xx)
# Usage: ./generate-traffic.sh <alb-url> [duration-seconds] [parallel-clients]
set -euo pipefail

ALB_URL="${1:?Usage: $0 <alb-url> [duration-seconds] [parallel-clients]}"
DURATION="${2:-600}"
CLIENTS="${3:-5}"
END=$(( $(date +%s) + DURATION ))

client() {
  local ok=0 slow=0 missing=0
  while [ "$(date +%s)" -lt "$END" ]; do
    case $(( RANDOM % 10 )) in
      0|1) curl -s -o /dev/null "$ALB_URL/cgi-bin/slow" || true; slow=$((slow + 1)) ;;
      2)   curl -s -o /dev/null "$ALB_URL/does-not-exist-$RANDOM" || true; missing=$((missing + 1)) ;;
      *)   curl -s -o /dev/null "$ALB_URL/" || true; ok=$((ok + 1)) ;;
    esac
    sleep 0.1
  done
  echo "client $1: $ok fast, $slow slow, $missing 404"
}

echo "Generating traffic to $ALB_URL for ${DURATION}s with $CLIENTS parallel clients..."
for c in $(seq 1 "$CLIENTS"); do
  client "$c" &
done
wait
echo "Done. Metrics appear on the dashboard within 1-2 minutes."
