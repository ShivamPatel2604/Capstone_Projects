variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
  default     = "shivam-project15"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.15.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.15.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for managed nodes"
  type        = string
  default     = "t3.micro"
}

variable "node_count" {
  description = "Number of managed nodes (web servers) Ansible will configure"
  type        = number
  default     = 2
}
