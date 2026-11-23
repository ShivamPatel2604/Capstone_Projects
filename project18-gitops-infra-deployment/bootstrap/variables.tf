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

variable "github_repository_immutable" {
  description = "Immutable OIDC subject form of the repository (owner@owner_id/repo@repo_id). Check with: gh api repos/OWNER/REPO/actions/oidc/customization/sub. Empty string to disable."
  type        = string
  default     = "ShivamPatel2604@358403276/Capstone_Projects@1464022307"
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
  description = "Create the GitHub OIDC provider. false = reuse the one that already exists in this AWS account"
  type        = bool
  default     = false
}
