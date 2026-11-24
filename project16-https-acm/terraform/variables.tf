variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project16"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.16.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per Availability Zone, ALB needs at least two)"
  type        = list(string)
  default     = ["10.16.1.0/24", "10.16.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two Availability Zones."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

variable "domain_name" {
  description = "Domain for a public ACM certificate validated through Route 53 (e.g. app.example.com). Leave empty to import a self-signed certificate into ACM instead."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Route 53 public hosted zone that contains domain_name (e.g. example.com). Defaults to domain_name when empty."
  type        = string
  default     = ""
}

variable "http_mode" {
  description = "How plain HTTP (port 80) is handled: \"block\" = port 80 closed on the ALB (no listener, SG denies it), \"redirect\" = port 80 only returns a 301 to HTTPS"
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "redirect"], var.http_mode)
    error_message = "http_mode must be \"block\" or \"redirect\"."
  }
}

variable "ssl_policy" {
  description = "ALB security policy for the HTTPS listener (TLS 1.2 and 1.3 only)"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}
