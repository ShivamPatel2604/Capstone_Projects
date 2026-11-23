variable "aws_region" {
  description = "AWS region for the state bucket and GitOps-managed infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix used for every resource name in this project"
  type        = string
  default     = "shivam-project18"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the CI roles"
  type        = string
  default     = "ShivamPatel2604/Capstone_Projects"
}

variable "github_environment" {
  description = "GitHub environment (with required reviewers) that gates terraform apply"
  type        = string
  default     = "production"
}

variable "state_key" {
  description = "Object key of the GitOps-managed Terraform state inside the state bucket"
  type        = string
  default     = "project18/infra/terraform.tfstate"
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
