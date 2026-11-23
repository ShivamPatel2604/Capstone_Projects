output "instance_id" {
  description = "Instance ID of the web server whose logs are backed up"
  value       = aws_instance.web.id
}

output "web_url" {
  description = "Public URL of the web server"
  value       = "http://${aws_instance.web.public_ip}"
}

output "backup_bucket" {
  description = "S3 bucket receiving the log backups"
  value       = aws_s3_bucket.backup.bucket
}

output "backup_location" {
  description = "S3 URI where this instance's backups are written"
  value       = "s3://${aws_s3_bucket.backup.bucket}/${var.backup_prefix}/${aws_instance.web.id}/"
}

output "backup_console_url" {
  description = "S3 console view of the backup files"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.backup.bucket}?region=${var.aws_region}&prefix=${var.backup_prefix}/${aws_instance.web.id}/"
}
