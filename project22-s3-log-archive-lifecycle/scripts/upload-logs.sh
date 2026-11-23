#!/bin/bash
# Generates sample application and debug logs and uploads them to the S3 log archive.
# Usage: ./upload-logs.sh <bucket> [days] [region]
#   logs/<app>/YYYY/MM/DD/<app>-YYYY-MM-DD.log.gz  -> long-term archive rule
#   debug/<app>/YYYY/MM/DD/<app>-debug-YYYY-MM-DD.log -> 7-day expiry rule
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket> [days] [region]}"
DAYS="${2:-7}"
REGION="${3:-ap-south-1}"
APPS=(web api)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PATHS=(/ /index.html /login /api/orders /api/users /missing /health)
CODES=(200 200 200 200 201 304 404 500)
AGENTS=("curl/8.5.0" "Mozilla/5.0" "ELB-HealthChecker/2.0")

gen_access_log() { # app date lines
  local app=$1 day=$2 lines=$3 i clf_day
  clf_day=$(date -u -d "$day" +%d/%b/%Y)
  for ((i = 0; i < lines; i++)); do
    printf '10.22.%d.%d - - [%s:%02d:%02d:%02d +0000] "GET %s HTTP/1.1" %s %d "-" "%s" app=%s\n' \
      $((RANDOM % 255)) $((RANDOM % 255)) "$clf_day" \
      $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)) \
      "${PATHS[RANDOM % ${#PATHS[@]}]}" "${CODES[RANDOM % ${#CODES[@]}]}" \
      $((RANDOM % 5000 + 100)) "${AGENTS[RANDOM % ${#AGENTS[@]}]}" "$app"
  done
}

gen_debug_log() { # app date lines
  local app=$1 day=$2 lines=$3 i
  for ((i = 0; i < lines; i++)); do
    printf '%sT%02d:%02d:%02dZ DEBUG [%s] request_id=%04x%04x latency_ms=%d cache_hit=%s\n' \
      "$day" $((RANDOM % 24)) $((RANDOM % 60)) $((RANDOM % 60)) "$app" \
      $RANDOM $RANDOM $((RANDOM % 900 + 5)) "$( ((RANDOM % 2)) && echo true || echo false)"
  done
}

for ((d = DAYS - 1; d >= 0; d--)); do
  DAY=$(date -u -d "-$d day" +%Y-%m-%d)
  DATE_PATH=$(date -u -d "$DAY" +%Y/%m/%d)
  for APP in "${APPS[@]}"; do
    ARCHIVE="$WORK/$APP-$DAY.log.gz"
    # ~12k lines keeps each archive above 128 KB, the minimum size S3 transitions
    gen_access_log "$APP" "$DAY" 12000 | gzip -9 > "$ARCHIVE"
    aws s3 cp "$ARCHIVE" "s3://$BUCKET/logs/$APP/$DATE_PATH/$APP-$DAY.log.gz" \
      --content-type application/gzip --metadata "app=$APP,log-date=$DAY,log-type=access" \
      --region "$REGION" --only-show-errors
    echo "uploaded s3://$BUCKET/logs/$APP/$DATE_PATH/$APP-$DAY.log.gz ($(stat -c %s "$ARCHIVE") bytes)"

    DEBUG="$WORK/$APP-debug-$DAY.log"
    gen_debug_log "$APP" "$DAY" 500 > "$DEBUG"
    aws s3 cp "$DEBUG" "s3://$BUCKET/debug/$APP/$DATE_PATH/$APP-debug-$DAY.log" \
      --content-type text/plain --metadata "app=$APP,log-date=$DAY,log-type=debug" \
      --region "$REGION" --only-show-errors
    echo "uploaded s3://$BUCKET/debug/$APP/$DATE_PATH/$APP-debug-$DAY.log ($(stat -c %s "$DEBUG") bytes)"
  done
done

echo
aws s3 ls "s3://$BUCKET/" --recursive --human-readable --summarize --region "$REGION" | tail -n 2
