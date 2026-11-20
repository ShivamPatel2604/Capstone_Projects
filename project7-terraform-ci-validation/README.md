# Project 7: CI Validation for Terraform

![Terraform Validation](https://github.com/ShivamPatel2604/Capstone_Projects/actions/workflows/terraform-validation.yml/badge.svg?branch=feature%2Fproject7-clean-main)

## Goal
Automate Infrastructure as Code checks using GitHub Actions.

## Tasks
- Run Terraform fmt checks.
- Run Terraform validate.
- Trigger validation automatically on push and pull requests.
- Display workflow status using a GitHub Actions badge.

## Terraform Configuration
This project uses Terraform's built-in terraform_data resource.
No AWS infrastructure is provisioned.

## Validation Commands
```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```
