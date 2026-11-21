# Project 13: Build Image and Push to ECR

## Objective
Build a Docker image and publish it to Amazon Elastic Container Registry (ECR).

## AWS Configuration
- AWS Service: Amazon ECR
- Region: ap-south-1 (Mumbai)
- Repository: shivam-project13-ecr
- Registry ID: 590507089733
- Image Tag: v1

## Technologies Used
- Docker
- Nginx Alpine
- Amazon ECR
- AWS CLI
- Ubuntu 24.04

## Implementation Steps
1. Created a private ECR repository.
2. Created an HTML application.
3. Created a Dockerfile using Nginx Alpine.
4. Built the Docker image.
5. Authenticated Docker with AWS ECR.
6. Tagged the Docker image.
7. Pushed the image to Amazon ECR.
8. Verified the image using AWS CLI.

## ECR Image URI
590507089733.dkr.ecr.ap-south-1.amazonaws.com/shivam-project13-ecr:v1

## Verification
The Docker image was successfully pushed and verified in Amazon ECR.

Image status: ACTIVE
Image tag: v1
