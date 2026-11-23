output "instance_id" {
  description = "EC2 instance with the IAM role attached"
  value       = aws_instance.app.id
}

output "app_bucket" {
  description = "Bucket the EC2 role may use (allowed prefix only)"
  value       = aws_s3_bucket.app.bucket
}

output "restricted_bucket" {
  description = "Bucket the EC2 role has no access to"
  value       = aws_s3_bucket.restricted.bucket
}

output "allowed_prefix" {
  description = "Only prefix the EC2 role may read and write"
  value       = var.allowed_prefix
}

output "role_name" {
  description = "IAM role attached to the instance"
  value       = aws_iam_role.ec2_s3.name
}

output "role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.ec2_s3.arn
}

output "instance_profile_name" {
  description = "Instance profile that carries the role to EC2"
  value       = aws_iam_instance_profile.ec2_s3.name
}

output "s3_policy_arn" {
  description = "Least-privilege S3 policy attached to the role"
  value       = aws_iam_policy.s3_access.arn
}

output "role_console_url" {
  description = "IAM console page for the role"
  value       = "https://console.aws.amazon.com/iam/home#/roles/details/${aws_iam_role.ec2_s3.name}"
}

output "instance_console_url" {
  description = "EC2 console page for the instance (Security tab shows the IAM role)"
  value       = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#InstanceDetails:instanceId=${aws_instance.app.id}"
}
