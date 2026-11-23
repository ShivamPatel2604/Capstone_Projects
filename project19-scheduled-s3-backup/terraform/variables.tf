variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project19"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.19.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.19.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

variable "backup_prefix" {
  description = "S3 key prefix under which log backups are stored"
  type        = string
  default     = "log-backups"
}

variable "backup_retention_days" {
  description = "Days after which backup objects expire from the bucket"
  type        = number
  default     = 30
}
