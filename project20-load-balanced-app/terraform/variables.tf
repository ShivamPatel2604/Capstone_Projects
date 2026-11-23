variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project20"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per Availability Zone, ALB needs at least two)"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two Availability Zones."
  }
}

variable "instance_count" {
  description = "Number of web servers behind the load balancer (spread across the AZs)"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "health_check_path" {
  description = "Path the ALB requests to decide whether a target is healthy"
  type        = string
  default     = "/health"
}
