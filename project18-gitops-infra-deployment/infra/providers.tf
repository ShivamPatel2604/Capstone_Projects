terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial configuration: the bucket name is supplied at init time
  #   terraform init -backend-config="bucket=<TF_STATE_BUCKET>"
  backend "s3" {
    key          = "project18/infra/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "project18-gitops-infra-deployment"
      Component   = "infra"
      Environment = var.environment
      Owner       = "Shivam"
      ManagedBy   = "Terraform-GitOps"
    }
  }
}
