variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project23"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.23.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.23.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_prefix" {
  description = "Only S3 key prefix in the app bucket the EC2 role may read and write"
  type        = string
  default     = "app-data"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.allowed_prefix))
    error_message = "allowed_prefix must be a single folder name without slashes."
  }
}
