variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project24"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.24.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.24.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to reach the web service on port 80 (set to <your-public-ip>/32 to lock it down)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_http_cidr, 0))
    error_message = "allowed_http_cidr must be a valid IPv4 CIDR, e.g. 203.0.113.10/32."
  }
}

variable "auto_restart_delay_seconds" {
  description = "systemd RestartSec for httpd: delay before systemd restarts a crashed (not stopped) service"
  type        = number
  default     = 5

  validation {
    condition     = var.auto_restart_delay_seconds >= 1 && var.auto_restart_delay_seconds <= 60
    error_message = "auto_restart_delay_seconds must be between 1 and 60."
  }
}
