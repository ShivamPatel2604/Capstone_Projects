output "iam_username" {
  description = "Created IAM username"
  value       = aws_iam_user.s3_user.name
}

output "iam_policy_arn" {
  description = "S3 read-only policy ARN"
  value       = aws_iam_policy.s3_read_policy.arn
}
