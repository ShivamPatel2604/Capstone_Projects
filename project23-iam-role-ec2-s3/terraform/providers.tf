terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "project23-iam-role-ec2-s3"
      ManagedBy = "Terraform"
      Owner     = "ShivamPatel2604"
    }
  }
}
