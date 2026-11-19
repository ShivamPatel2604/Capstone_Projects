variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-2"
}

variable "bucket_prefix" {
  description = "Prefix for S3 website bucket"
  type        = string
  default     = "capstone-static-website"
}
