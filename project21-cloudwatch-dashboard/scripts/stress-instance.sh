#!/bin/bash
# Runs CPU and memory stress on one web server via SSM so the CPU/memory graphs spike
# and the high CPU alarm goes into ALARM.
# Usage: ./stress-instance.sh <instance-id> [duration-seconds] [region]
set -euo pipefail

INSTANCE_ID="${1:?Usage: $0 <instance-id> [duration-seconds] [region]}"
DURATION="${2:-300}"
REGION="${3:-ap-south-1}"

COMMAND_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Project 21 - CPU/memory stress for dashboard" \
  --parameters "commands=[\"stress-ng --cpu 0 --cpu-load 90 --vm 1 --vm-bytes 60% --timeout ${DURATION}s --metrics-brief\"],executionTimeout=[\"$((DURATION + 120))\"]" \
  --query Command.CommandId --output text)

echo "Stress started on $INSTANCE_ID for ${DURATION}s (SSM command $COMMAND_ID)"
echo "Watch the 'EC2 CPU utilization' and 'Memory used' widgets and the alarm status bar."
echo
echo "Check status: aws ssm get-command-invocation --region $REGION --command-id $COMMAND_ID --instance-id $INSTANCE_ID --query Status"
