variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project21"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.21.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per Availability Zone, ALB needs at least two)"
  type        = list(string)
  default     = ["10.21.1.0/24", "10.21.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two Availability Zones."
  }
}

variable "instance_count" {
  description = "Number of monitored web servers behind the load balancer"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "cpu_alarm_threshold" {
  description = "Average CPU utilization (%) that triggers the high CPU alarm"
  type        = number
  default     = 70
}

variable "memory_alarm_threshold" {
  description = "Memory used (%) reported by the CloudWatch agent that triggers the high memory alarm"
  type        = number
  default     = 80
}

variable "latency_alarm_threshold" {
  description = "ALB target response time p90 (seconds) that triggers the high latency alarm"
  type        = number
  default     = 1
}

variable "dashboard_period" {
  description = "Default period (seconds) for dashboard graphs"
  type        = number
  default     = 60
}
