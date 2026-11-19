# Project 4: IAM User Automation with Terraform

## Overview
This project automates AWS IAM user creation and permission management using Terraform.

## Objectives
- Create an AWS IAM user.
- Define a custom S3 read-only IAM policy.
- Store the policy document as a Terraform variable.
- Attach the policy to the IAM user.
- Verify resources using Terraform.

## AWS Configuration
- Cloud Provider: AWS
- Region: ap-south-1 (Mumbai)
- Infrastructure as Code: Terraform
- IAM User: shivam-terraform-s3-user
- IAM Policy: shivam-s3-read-only-policy
- Project: Project 4

## Resources Created
1. aws_iam_user
2. aws_iam_policy
3. aws_iam_user_policy_attachment

## Project Structure
- providers.tf: AWS provider configuration
- variables.tf: IAM username and S3 policy variable
- main.tf: IAM resources
- outputs.tf: Terraform outputs
- .gitignore: Excludes state and sensitive files
- README.md: Project documentation

## Deployment Instructions

Initialize Terraform:

terraform init

Format configuration:

terraform fmt

Validate configuration:

terraform validate

Preview infrastructure:

terraform plan

Deploy resources:

terraform apply

## Verification

terraform output

terraform state list

## Security
- No AWS credentials are stored in source files.
- No administrator permissions are granted to the created user.
- S3 permissions are restricted to the configured bucket ARN.
- Terraform state files are excluded from GitHub.

## Cleanup
To remove the resources created by this project:

terraform destroy

Only run cleanup when the project is no longer required.
