#!/bin/bash
# Shows the ALB health check settings and the health of every registered target.
# Usage: ./show-target-health.sh <target-group-arn> [region]
set -euo pipefail

TG_ARN="${1:?Usage: $0 <target-group-arn> [region]}"
REGION="${2:-ap-south-1}"

echo "=== Health check configuration ==="
aws elbv2 describe-target-groups --region "$REGION" --target-group-arns "$TG_ARN" \
  --query "TargetGroups[].{Path:HealthCheckPath,Protocol:HealthCheckProtocol,Port:HealthCheckPort,Matcher:Matcher.HttpCode,IntervalSec:HealthCheckIntervalSeconds,TimeoutSec:HealthCheckTimeoutSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}" \
  --output table

echo
echo "=== Target health ==="
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{Target:Target.Id,AZ:Target.AvailabilityZone,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table
