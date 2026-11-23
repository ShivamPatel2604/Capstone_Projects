#!/bin/bash
# Sends N requests to the ALB and counts how many each web server answered.
# Usage: ./test-load-balancing.sh <alb-url> [requests]
set -euo pipefail

ALB_URL="${1:?Usage: $0 <alb-url> [requests]}"
REQUESTS="${2:-20}"
RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

echo "Sending $REQUESTS requests to $ALB_URL/whoami.txt"
echo
printf "%-4s %-6s %-6s %-20s %-14s %s\n" "#" "HTTP" "SERVER" "INSTANCE" "AZ" "PRIVATE_IP"
for i in $(seq 1 "$REQUESTS"); do
  BODY=$(mktemp)
  CODE=$(curl -s -o "$BODY" -w "%{http_code}" "$ALB_URL/whoami.txt" || true)
  if [ "$CODE" = "200" ]; then
    read -r NAME INSTANCE AZ IP < "$BODY"
  else
    NAME="-"; INSTANCE="no-healthy-target"; AZ="-"; IP="-"
  fi
  rm -f "$BODY"
  printf "%-4s %-6s %-6s %-20s %-14s %s\n" "$i" "$CODE" "$NAME" "$INSTANCE" "$AZ" "$IP"
  echo "$NAME $INSTANCE $AZ" >> "$RESULTS"
  sleep 0.2
done

echo
echo "=== Requests per server ==="
sort "$RESULTS" | uniq -c | awk -v total="$REQUESTS" '{ printf "%-6s %-20s %-14s %3d requests (%d%%)\n", $2, $3, $4, $1, ($1 * 100 / total) }'
