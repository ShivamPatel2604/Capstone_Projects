output "log_bucket" {
  description = "S3 bucket that archives the logs"
  value       = aws_s3_bucket.logs.bucket
}

output "archive_location" {
  description = "S3 URI for long-term application logs"
  value       = "s3://${aws_s3_bucket.logs.bucket}/${var.archive_prefix}/"
}

output "debug_location" {
  description = "S3 URI for short-lived debug logs"
  value       = "s3://${aws_s3_bucket.logs.bucket}/${var.debug_prefix}/"
}

output "lifecycle_rule_ids" {
  description = "IDs of the lifecycle rules on the bucket"
  value       = [for r in aws_s3_bucket_lifecycle_configuration.logs.rule : r.id]
}

output "lifecycle_console_url" {
  description = "S3 console page (Management tab) showing the lifecycle rules"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.logs.bucket}?region=${var.aws_region}&tab=management"
}

output "objects_console_url" {
  description = "S3 console view of the uploaded logs"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.logs.bucket}?region=${var.aws_region}&prefix=${var.archive_prefix}/"
}
