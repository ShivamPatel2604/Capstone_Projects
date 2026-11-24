#!/bin/bash
# Shows the ALB listeners, the security group rules and the ACM certificate details.
# Usage: ./show-https-config.sh <alb-arn> <certificate-arn> [region]
set -euo pipefail

ALB_ARN="${1:?Usage: $0 <alb-arn> <certificate-arn> [region]}"
CERT_ARN="${2:?Usage: $0 <alb-arn> <certificate-arn> [region]}"
REGION="${3:-ap-south-1}"

echo "=== ALB listeners ==="
aws elbv2 describe-listeners --region "$REGION" --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[].{Port:Port,Protocol:Protocol,SslPolicy:SslPolicy,Action:DefaultActions[0].Type,Certificate:Certificates[0].CertificateArn}" \
  --output table

echo
echo "=== ALB security group inbound rules ==="
SG_ID=$(aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].SecurityGroups[0]" --output text)
aws ec2 describe-security-group-rules --region "$REGION" \
  --filters "Name=group-id,Values=$SG_ID" \
  --query "SecurityGroupRules[?IsEgress==\`false\`].{Port:FromPort,Protocol:IpProtocol,Source:CidrIpv4,Description:Description}" \
  --output table

echo
echo "=== ACM certificate ==="
aws acm describe-certificate --region "$REGION" --certificate-arn "$CERT_ARN" \
  --query "Certificate.{Domain:DomainName,SANs:join(', ',SubjectAlternativeNames),Type:Type,Status:Status,Issuer:Issuer,KeyAlgorithm:KeyAlgorithm,NotAfter:NotAfter,InUseBy:join(', ',InUseBy)}" \
  --output table

echo
echo "=== Target health ==="
TG_ARN=$(aws elbv2 describe-target-groups --region "$REGION" --load-balancer-arn "$ALB_ARN" \
  --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State}" \
  --output table
