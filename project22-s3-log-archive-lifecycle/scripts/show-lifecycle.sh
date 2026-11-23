#!/bin/bash
# Shows the lifecycle rules on the log archive bucket and proves they apply to the uploaded logs.
# Usage: ./show-lifecycle.sh <bucket> [region]
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket> [region]}"
REGION="${2:-ap-south-1}"

echo "=== Lifecycle rules on s3://$BUCKET ==="
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION" \
  --query "Rules[].{ID:ID, Status:Status, Prefix:Filter.Prefix, ExpireDays:Expiration.Days, NoncurrentExpireDays:NoncurrentVersionExpiration.NoncurrentDays}" \
  --output table

echo
echo "=== Storage class transitions ==="
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION" \
  --query "Rules[?Transitions].Transitions[]" --output table

echo
echo "=== Objects and current storage class ==="
aws s3api list-objects-v2 --bucket "$BUCKET" --region "$REGION" \
  --query "Contents[].[Key, Size, StorageClass, LastModified]" --output table

# S3 returns an x-amz-expiration header naming the rule and the exact delete date
for PREFIX in logs/ debug/; do
  KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX" --region "$REGION" \
    --query "Contents[0].Key" --output text)
  if [ "$KEY" = "None" ]; then
    echo "No objects under $PREFIX - run upload-logs.sh first"
    continue
  fi
  echo
  echo "=== Expiration applied to $KEY ==="
  aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" \
    --query "{Expiration:Expiration, StorageClass:StorageClass, Encryption:ServerSideEncryption, Size:ContentLength, Metadata:Metadata}" \
    --output table
done
