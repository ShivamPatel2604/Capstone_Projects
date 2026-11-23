#!/bin/bash
# Generates web traffic (200s and 404s) so the access log has data for the dashboard.
# Usage: ./generate-traffic.sh http://<public-ip> [rounds]
set -euo pipefail

URL="${1:?Usage: $0 http://<public-ip> [rounds]}"
ROUNDS="${2:-30}"

for i in $(seq 1 "$ROUNDS"); do
  curl -s -o /dev/null -w "%{http_code} /\n" "$URL/"
  curl -s -o /dev/null -w "%{http_code} /index.html\n" "$URL/index.html"
  curl -s -o /dev/null -w "%{http_code} /admin\n" "$URL/admin"
  curl -s -o /dev/null -w "%{http_code} /missing-page-$((i % 3))\n" "$URL/missing-page-$((i % 3))"
  sleep 1
done
