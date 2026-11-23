variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix used for every resource name (must match the bootstrap IAM scope)"
  type        = string
  default     = "shivam-project18"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "production"
}

variable "app_version" {
  description = "Application version published to SSM Parameter Store"
  type        = string
}

variable "feature_flags" {
  description = "Feature flags published to SSM Parameter Store"
  type        = map(bool)
  default     = {}
}

variable "artifact_retention_days" {
  description = "Days before non-current artifact versions are expired"
  type        = number
  default     = 30

  validation {
    condition     = var.artifact_retention_days >= 1 && var.artifact_retention_days <= 365
    error_message = "artifact_retention_days must be between 1 and 365."
  }
}
