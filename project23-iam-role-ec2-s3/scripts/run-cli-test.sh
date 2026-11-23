#!/bin/bash
# Runs s3-access-test.sh on the EC2 instance through SSM Run Command (no SSH)
# and saves the CLI test output to ../cli-test-output.txt.
# Usage: ./run-cli-test.sh            (reads values from terraform output)
#        ./run-cli-test.sh <instance-id> <app-bucket> <restricted-bucket> [prefix] [region]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TF_DIR="$SCRIPT_DIR/../terraform"
OUTPUT_FILE="$SCRIPT_DIR/../cli-test-output.txt"

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

INSTANCE_ID="${1:-$(tf_out instance_id)}"
APP_BUCKET="${2:-$(tf_out app_bucket)}"
RESTRICTED_BUCKET="${3:-$(tf_out restricted_bucket)}"
PREFIX="${4:-$(tf_out allowed_prefix)}"
REGION="${5:-ap-south-1}"

echo "Waiting for $INSTANCE_ID to register with SSM..."
for _ in $(seq 1 30); do
  PING=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" --output text)
  [ "$PING" = "Online" ] && break
  sleep 10
done
if [ "$PING" != "Online" ]; then
  echo "Instance is not Online in SSM (status: $PING). Check the role has AmazonSSMManagedInstanceCore." >&2
  exit 1
fi
echo "SSM status: Online"

# Ship the test script as base64 so no quoting/escaping is needed
SCRIPT_B64=$(base64 -w0 "$SCRIPT_DIR/s3-access-test.sh")
PARAMS=$(printf '{"commands":["echo %s | base64 -d > /tmp/s3-access-test.sh","bash /tmp/s3-access-test.sh %s %s %s"]}' \
  "$SCRIPT_B64" "$APP_BUCKET" "$RESTRICTED_BUCKET" "$PREFIX")

CMD_ID=$(aws ssm send-command --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Project 23 IAM role S3 access test" \
  --parameters "$PARAMS" \
  --query "Command.CommandId" --output text)
echo "SSM command: $CMD_ID"

STATUS=Pending
for _ in $(seq 1 60); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query "Status" --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Pending | InProgress | Delayed) ;; *) break ;; esac
done

aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" --output text | tee "$OUTPUT_FILE"

ERRORS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query "StandardErrorContent" --output text)
if [ -n "$ERRORS" ] && [ "$ERRORS" != "None" ]; then
  echo "--- stderr ---"
  echo "$ERRORS"
fi

echo
echo "SSM command status: $STATUS"
echo "Output saved to $(realpath "$OUTPUT_FILE")"
[ "$STATUS" = "Success" ]
