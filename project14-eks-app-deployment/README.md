# Project 14: App Deployment using EKS

## Objective
Provision an Amazon EKS cluster with Terraform and deploy a containerized web app on Kubernetes, exposed publicly through an AWS Load Balancer.

## AWS Configuration
- AWS Service: Amazon EKS (managed node group)
- Region: ap-south-1 (Mumbai)
- Cluster: shivam-project14-eks
- Nodes: 2 x t3.medium (on-demand)
- App Image: `590507089733.dkr.ecr.ap-south-1.amazonaws.com/shivam-project13-ecr:v1` (from Project 13)
- Exposure: Kubernetes `Service` of type `LoadBalancer` (public AWS Classic Load Balancer)

## Architecture
```
Internet --> AWS Load Balancer (port 80) --> Service project14-web-svc --> 2 x Pods (nginx app from ECR)
                                                     |
                          EKS cluster in VPC 10.14.0.0/16 (2 public subnets, 2 AZs)
```

## Project Structure
```
project14-eks-app-deployment/
├── terraform/
│   ├── providers.tf     # AWS provider and versions
│   ├── variables.tf     # Region, cluster name, node sizing
│   ├── main.tf          # VPC, subnets, IAM roles, EKS cluster, node group
│   └── outputs.tf       # Cluster details and kubeconfig command
└── k8s/
    ├── deployment.yaml  # 2 replicas of the Project 13 ECR image
    └── service.yaml     # LoadBalancer service exposing port 80
```

## Technologies Used
- Terraform
- Amazon EKS / EC2 / VPC / IAM / ELB
- Amazon ECR
- kubectl
- AWS CLI
- Ubuntu 24.04

## Implementation Steps (run on the Linux VM)

### 1. Verify AWS identity and region
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
aws configure get region   # should be ap-south-1
```

### 2. Confirm the Project 13 image exists in ECR
```bash
aws ecr describe-images --repository-name shivam-project13-ecr --region ap-south-1
```

### 3. Install kubectl (if not installed)
```bash
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client
```

### 4. Provision EKS with Terraform (~15 minutes)
```bash
cd ~/aws-terraform-capstone/project14-eks-app-deployment/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

### 5. Configure kubectl and verify nodes
```bash
aws eks update-kubeconfig --region ap-south-1 --name shivam-project14-eks
kubectl get nodes -o wide
```

### 6. Deploy the application
```bash
cd ../k8s
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl rollout status deployment/project14-web
kubectl get pods -o wide
```

### 7. Expose the service publicly and get the URL
```bash
kubectl get svc project14-web-svc -w   # wait until EXTERNAL-IP shows a hostname, then Ctrl+C
URL=$(kubectl get svc project14-web-svc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$URL"
curl -I "http://$URL"                   # expect HTTP/1.1 200 OK (DNS can take 2-3 minutes)
```

### 8. Capture the deliverable screenshot
Open `http://<EXTERNAL-IP hostname>` in a browser and take a screenshot showing the URL bar and the page. Also capture the terminal output of:
```bash
kubectl get nodes,pods,svc
```
Save the screenshots in this folder as `1.png` (browser) and `2.png` (kubectl output).

## Cleanup (important – EKS is billed per hour)
Delete the Service first so Kubernetes removes the AWS Load Balancer; otherwise `terraform destroy` can fail on the VPC.
```bash
cd ~/aws-terraform-capstone/project14-eks-app-deployment/k8s
kubectl delete -f service.yaml -f deployment.yaml
# wait ~1 minute for the load balancer to be deleted
cd ../terraform
terraform destroy
```

## Verification
- `kubectl get nodes` shows 2 nodes in `Ready` state.
- `kubectl get pods` shows 2 `project14-web` pods `Running`.
- `kubectl get svc` shows a public `EXTERNAL-IP` hostname for `project14-web-svc`.
- The app is reachable from the internet at `http://<EXTERNAL-IP hostname>`.

## Deliverables
- Public access screenshot: `1.png`
- Cluster/workload status screenshot: `2.png`
