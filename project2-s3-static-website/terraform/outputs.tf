output "s3_bucket_name" {
  description = "Name of S3 bucket"
  value       = aws_s3_bucket.website.id
}

output "website_endpoint" {
  description = "Static website URL"
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
