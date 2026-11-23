#!/bin/bash
# Runs ON the EC2 instance. Proves the AWS CLI uses the attached IAM role (no
# access keys) and that the role can only do what its policy allows.
# Usage: s3-access-test.sh <app-bucket> <restricted-bucket> [allowed-prefix]
set -uo pipefail

APP_BUCKET="${1:?Usage: $0 <app-bucket> <restricted-bucket> [allowed-prefix]}"
RESTRICTED_BUCKET="${2:?Usage: $0 <app-bucket> <restricted-bucket> [allowed-prefix]}"
PREFIX="${3:-app-data}"

export HOME="${HOME:-/root}"

IMDS=http://169.254.169.254/latest
TOKEN=$(curl -s -X PUT "$IMDS/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
imds() { curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/$1"; }

INSTANCE_ID=$(imds meta-data/instance-id)
export AWS_DEFAULT_REGION=$(imds meta-data/placement/region)
ROLE_NAME=$(imds meta-data/iam/security-credentials/)

echo "================================================================"
echo " Project 23 - IAM role based S3 access test"
echo " Date     : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo " Instance : $INSTANCE_ID ($AWS_DEFAULT_REGION)"
echo " Buckets  : app=$APP_BUCKET  restricted=$RESTRICTED_BUCKET"
echo " Allowed  : s3://$APP_BUCKET/$PREFIX/*"
echo "================================================================"

echo
echo "=== 1. Where do the credentials come from? ==="
echo "Instance profile : $(imds meta-data/iam/info | grep -o '"InstanceProfileArn" : "[^"]*"' | cut -d'"' -f4)"
echo "Role (IMDSv2)    : $ROLE_NAME"
# Print only non-secret fields of the temporary credentials
imds "meta-data/iam/security-credentials/$ROLE_NAME" \
  | grep -E '"(Code|Type|LastUpdated|Expiration)"' | sed 's/^ */  /'
echo "Static key file  : $([ -f ~/.aws/credentials ] && echo "PRESENT (~/.aws/credentials)" || echo "none (~/.aws/credentials does not exist)")"
echo "Key env vars     : $([ -n "${AWS_ACCESS_KEY_ID:-}" ] && echo "PRESENT (AWS_ACCESS_KEY_ID)" || echo "none")"
echo
aws configure list

PASS=0
FAIL=0
RESULTS=()

# check <allow|deny> <description> <command...>
check() {
  local expect=$1 desc=$2 out rc actual status
  shift 2
  echo
  echo "--- $desc (expected: ${expect^^})"
  echo "\$ $*"
  out=$("$@" 2>&1)
  rc=$?
  echo "$out" | head -n 15

  if [ $rc -eq 0 ]; then
    actual=allow
  elif echo "$out" | grep -qE 'AccessDenied|UnauthorizedOperation|Forbidden|\(403\)'; then
    actual=deny
  else
    actual=error
  fi

  if [ "$actual" = "$expect" ]; then
    status=PASS
    PASS=$((PASS + 1))
  else
    status=FAIL
    FAIL=$((FAIL + 1))
  fi
  echo "=> ${actual^^} ... $status"
  RESULTS+=("$(printf '%-4s  %-6s %s' "$status" "${actual^^}" "$desc")")
}

TEST_KEY="$PREFIX/ec2-upload-$INSTANCE_ID-$(date -u +%Y%m%dT%H%M%SZ).txt"
TEST_FILE=$(mktemp)
echo "Uploaded by $INSTANCE_ID using IAM role $ROLE_NAME at $(date -u)" > "$TEST_FILE"

echo
echo "=== 2. Allowed actions ==="
check allow "Identify caller (assumed role, no keys)" \
  aws sts get-caller-identity --output table
check allow "List objects in app bucket" \
  aws s3 ls "s3://$APP_BUCKET/" --recursive
check allow "Read object in $PREFIX/" \
  aws s3 cp "s3://$APP_BUCKET/$PREFIX/welcome.txt" -
check allow "Upload object to $PREFIX/" \
  aws s3 cp "$TEST_FILE" "s3://$APP_BUCKET/$TEST_KEY"
check allow "Download uploaded object and verify content" \
  bash -c "aws s3 cp 's3://$APP_BUCKET/$TEST_KEY' /tmp/s3-download.txt && cmp '$TEST_FILE' /tmp/s3-download.txt && cat /tmp/s3-download.txt"
check allow "Uploaded object is encrypted at rest" \
  aws s3api head-object --bucket "$APP_BUCKET" --key "$TEST_KEY" \
  --query "{Key:'$TEST_KEY',Size:ContentLength,Encryption:ServerSideEncryption}" --output table

echo
echo "=== 3. Denied actions (least privilege) ==="
check deny "Upload outside $PREFIX/" \
  aws s3 cp "$TEST_FILE" "s3://$APP_BUCKET/admin/hacked.txt"
check deny "Read object outside $PREFIX/" \
  aws s3 cp "s3://$APP_BUCKET/admin/config.txt" -
check deny "Delete object (no s3:DeleteObject)" \
  aws s3 rm "s3://$APP_BUCKET/$TEST_KEY"
check deny "List restricted bucket" \
  aws s3 ls "s3://$RESTRICTED_BUCKET/"
check deny "Read object in restricted bucket" \
  aws s3 cp "s3://$RESTRICTED_BUCKET/secret.txt" -
check deny "List all buckets in the account" \
  aws s3 ls
check deny "Use another service (EC2 DescribeInstances)" \
  aws ec2 describe-instances --max-items 1
check deny "Use IAM (ListUsers)" \
  aws iam list-users --max-items 1

rm -f "$TEST_FILE" /tmp/s3-download.txt

echo
echo "================================================================"
echo " SUMMARY  ($PASS passed, $FAIL failed)"
echo "================================================================"
printf '%s\n' "${RESULTS[@]}"

[ "$FAIL" -eq 0 ]
