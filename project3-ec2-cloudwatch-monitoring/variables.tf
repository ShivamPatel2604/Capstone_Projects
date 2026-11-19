
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "shivam-project3-ec2-monitoring"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "cpu_threshold" {
  type    = number
  default = 70
}

variable "alarm_evaluation_periods" {
  type    = number
  default = 2
}

variable "load_duration_seconds" {
  type    = number
  default = 600
}
