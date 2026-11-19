
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get available subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group - no inbound ports
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-sg"
  description = "EC2 monitoring security group"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# Deploy EC2 instance
resource "aws_instance" "monitoring_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  monitoring = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Generate CPU load automatically
  user_data = <<-EOF
    #!/bin/bash
    (
      for i in $(seq 1 $(nproc)); do
        yes > /dev/null &
        echo $! >> /var/run/cpu-load-pids
      done

      sleep ${var.load_duration_seconds}

      xargs -r kill < /var/run/cpu-load-pids
    ) > /var/log/cpu-load.log 2>&1 &
  EOF

  tags = {
    Name        = "${var.project_name}-ec2"
    Environment = "Capstone"
    Project     = "Project3"
  }
}

# CloudWatch CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "${var.project_name}-cpu-alarm"
  alarm_description   = "Alert when EC2 CPU utilization exceeds threshold"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods

  metric_name = "CPUUtilization"
  namespace   = "AWS/EC2"
  period      = 60
  statistic   = "Average"

  threshold          = var.cpu_threshold
  treat_missing_data = "notBreaching"
  actions_enabled    = false

  dimensions = {
    InstanceId = aws_instance.monitoring_ec2.id
  }

  tags = {
    Name    = "${var.project_name}-cpu-alarm"
    Project = "Project3"
  }
}
