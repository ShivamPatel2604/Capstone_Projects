variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project22"
}

variable "archive_prefix" {
  description = "S3 key prefix for application logs that are archived long term"
  type        = string
  default     = "logs"
}

variable "debug_prefix" {
  description = "S3 key prefix for short-lived debug logs"
  type        = string
  default     = "debug"
}

variable "transition_to_ia_days" {
  description = "Days after upload when archived logs move to S3 Standard-IA (minimum 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "S3 requires objects to be at least 30 days old before moving to STANDARD_IA."
  }
}

variable "transition_to_glacier_ir_days" {
  description = "Days after upload when archived logs move to S3 Glacier Instant Retrieval"
  type        = number
  default     = 90
}

variable "transition_to_deep_archive_days" {
  description = "Days after upload when archived logs move to S3 Glacier Deep Archive"
  type        = number
  default     = 180
}

variable "log_expiration_days" {
  description = "Days after upload when archived logs are permanently deleted"
  type        = number
  default     = 365
}

variable "debug_expiration_days" {
  description = "Days after upload when debug logs are permanently deleted"
  type        = number
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which overwritten/deleted (noncurrent) log versions are removed"
  type        = number
  default     = 30
}
