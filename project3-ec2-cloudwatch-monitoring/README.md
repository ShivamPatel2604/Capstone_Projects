
# Project 3: EC2 State Monitoring with CloudWatch Alarm

## Objective
Deploy EC2 using Terraform and monitor CPU utilization through CloudWatch.

## AWS Services
- Amazon EC2
- Amazon CloudWatch
- Amazon VPC
- Terraform

## Configuration
- Region: us-east-2
- Instance: t2.micro
- OS: Amazon Linux 2023
- CPU Alarm Threshold: 70%
- Evaluation Period: 2 minutes
- CPU Load Generation: 600 seconds

## Security
- No inbound SSH (22)
- No inbound RDP (3389)
- IMDSv2 enabled
- Encrypted EBS volume

## Deployment

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Cleanup

```bash
terraform destroy
```

## Deliverables
- EC2 instance screenshot
- CloudWatch alarm screenshot
- CPU utilization graph
- GitHub repository link
