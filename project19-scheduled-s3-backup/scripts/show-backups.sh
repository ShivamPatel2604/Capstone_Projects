#!/bin/bash
# Lists the log backups in S3 and verifies the latest archive.
# Usage: ./show-backups.sh <bucket> [prefix] [region]
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket> [prefix] [region]}"
PREFIX="${2:-log-backups}"
REGION="${3:-ap-south-1}"

COUNT=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX/" --region "$REGION" \
  --query "KeyCount" --output text)
if [ "$COUNT" = "0" ]; then
  echo "No backups found yet in s3://$BUCKET/$PREFIX/"
  exit 0
fi

echo "=== Backup files in s3://$BUCKET/$PREFIX/ ==="
aws s3 ls "s3://$BUCKET/$PREFIX/" --recursive --human-readable --summarize --region "$REGION"

echo
echo "=== Latest 10 backups ==="
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX/" --region "$REGION" \
  --query "reverse(sort_by(Contents, &LastModified))[:10].[LastModified, Size, Key]" \
  --output table

LATEST=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX/" --region "$REGION" \
  --query "sort_by(Contents, &LastModified)[-1].Key" --output text)

echo
echo "=== Metadata of latest backup: $LATEST ==="
aws s3api head-object --bucket "$BUCKET" --key "$LATEST" --region "$REGION" \
  --query "{Size:ContentLength, Modified:LastModified, Encryption:ServerSideEncryption, Version:VersionId, Metadata:Metadata}" \
  --output table

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
aws s3 cp "s3://$BUCKET/$LATEST" "$TMP/backup.tar.gz" --region "$REGION" --only-show-errors

EXPECTED=$(aws s3api head-object --bucket "$BUCKET" --key "$LATEST" --region "$REGION" \
  --query "Metadata.sha256" --output text)
ACTUAL=$(sha256sum "$TMP/backup.tar.gz" | cut -d' ' -f1)

echo
echo "=== Integrity check ==="
echo "expected sha256: $EXPECTED"
echo "actual   sha256: $ACTUAL"
if [ "$EXPECTED" = "$ACTUAL" ]; then echo "OK - checksum matches"; else echo "MISMATCH"; exit 1; fi

echo
echo "=== Contents of latest backup ==="
tar -tzvf "$TMP/backup.tar.gz"
