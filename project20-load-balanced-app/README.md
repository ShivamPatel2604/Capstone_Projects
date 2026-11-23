# Project 20: Load Balanced App Deployment

## Objective
Improve scale and performance of a web app by running it on **two EC2 instances in two Availability Zones** behind an **Application Load Balancer (ALB)** with **health checks**, so traffic is spread across both servers and an unhealthy server is automatically taken out of rotation.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- Web servers: 2 x Amazon Linux 2023 EC2 instances (`t3.micro`) running Apache, one per AZ, managed via SSM (no SSH / port 22)
- Load balancer: internet-facing ALB `shivam-project20-alb`, HTTP listener on port 80
- Target group: `shivam-project20-tg` (instance targets, round robin, stickiness off)
- Region: ap-south-1 (Mumbai), AZs `ap-south-1a` and `ap-south-1b`

## Health check configuration
| Setting | Value |
| --- | --- |
| Protocol / port | HTTP / traffic port (80) |
| Path | `/health` (returns `200 OK`) |
| Success code | `200` |
| Interval | 10 seconds |
| Timeout | 5 seconds |
| Healthy threshold | 2 consecutive successes |
| Unhealthy threshold | 2 consecutive failures (~20 s to fail over) |
| Deregistration delay | 30 seconds |

## Security
- Instances accept HTTP **only from the ALB security group** - they cannot be reached directly from the internet
- No SSH, no key pair - administration through SSM Session Manager / Run Command
- IMDSv2 required, encrypted gp3 root volumes
- ALB drops invalid HTTP header fields

## Architecture
```
                                 Internet (HTTP 80)
                                        |
                                        v
                   +-------- ALB: shivam-project20-alb (SG: 80 from 0.0.0.0/0) --------+
                   |   Listener :80 -> Target group shivam-project20-tg (round robin)  |
                   |   Health check: GET /health every 10s, expect 200                 |
                   +-------------------+-------------------------------+---------------+
                                       | HTTP 80 (SG: ALB only)        |
               VPC 10.20.0.0/16        v                               v
     +------------------------------------------+   +------------------------------------------+
     | ap-south-1a  public subnet 10.20.1.0/24  |   | ap-south-1b  public subnet 10.20.2.0/24  |
     |  EC2 shivam-project20-web-1 (Apache)     |   |  EC2 shivam-project20-web-2 (Apache)     |
     |  /  /whoami.txt  /health                 |   |  /  /whoami.txt  /health                 |
     +------------------------------------------+   +------------------------------------------+
                         ^                                              ^
                         +------------ SSM Run Command (no SSH) --------+
                                   Ubuntu VM (Terraform, AWS CLI)
```

## Project Structure
```
project20-load-balanced-app/
|-- terraform/
|   |-- providers.tf             # AWS provider
|   |-- variables.tf             # Region, CIDRs, instance count/type, health check path
|   |-- main.tf                  # VPC, 2 subnets, SGs, IAM (SSM), 2 EC2s,
|   |                            # ALB, target group + health checks, listener
|   |-- outputs.tf               # ALB URL, target group ARN, instances, console URL
|   `-- templates/user_data.sh   # Apache page showing server/AZ, /whoami.txt, /health
`-- scripts/
    |-- show-target-health.sh    # Health check settings + health of each target
    `-- test-load-balancing.sh   # Sends N requests and counts responses per server
```

## Technologies Used
- Elastic Load Balancing - Application Load Balancer, target groups, health checks
- Amazon EC2 / VPC (multi-AZ) / IAM / Security Groups
- AWS Systems Manager Run Command
- Terraform
- Apache HTTP Server, Bash, curl, Amazon Linux 2023

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Provision the infrastructure
```bash
cd ~/aws-terraform-capstone/project20-load-balanced-app/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Save the values for later steps:
```bash
ALB_URL=$(terraform output -raw alb_url)
TG_ARN=$(terraform output -raw target_group_arn)
read -r WEB1 WEB2 <<< "$(terraform output -json instance_ids | tr -d '[]"' | tr ',' ' ')"
chmod +x ../scripts/*.sh
```

### 3. Confirm both EC2s are running in different AZs
```bash
aws ec2 describe-instances --region ap-south-1 --instance-ids $WEB1 $WEB2 \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,Placement.AvailabilityZone,State.Name,PrivateIpAddress]" \
  --output table
```
Expected: `shivam-project20-web-1` in `ap-south-1a`, `shivam-project20-web-2` in `ap-south-1b`, both `running`.

### 4. Check the ALB health checks
Wait 2-3 minutes after apply (user_data installs Apache), then:
```bash
../scripts/show-target-health.sh $TG_ARN
```
Expected: health check path `/health`, matcher `200`, interval `10`, and **both targets `healthy`**.

Also open the target group in the console (**Targets** and **Health checks** tabs):
```bash
terraform output -raw target_group_console_url
```

### 5. Verify load balancing
```bash
../scripts/test-load-balancing.sh $ALB_URL 20
```
Expected: responses alternate between `web-1` (ap-south-1a) and `web-2` (ap-south-1b), about 50% each.

Open the app in a browser and refresh a few times - the page colour, server name, instance ID and AZ change between the two servers:
```bash
echo $ALB_URL
```

Confirm the instances cannot be reached directly (only via the ALB):
```bash
WEB1_IP=$(aws ec2 describe-instances --region ap-south-1 --instance-ids $WEB1 \
  --query "Reservations[].Instances[].PublicIpAddress" --output text)
curl -s -m 5 http://$WEB1_IP/ || echo "Direct access blocked - timeout as expected"
```

### 6. Health check failover test
Make `web-1` fail its health check by removing `/health` (the app itself keeps running):
```bash
aws ssm send-command --region ap-south-1 --instance-ids $WEB1 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["mv /var/www/html/health /var/www/html/health.disabled"]' \
  --comment "Project 20 - fail health check on web-1" --output text --query Command.CommandId
sleep 30
../scripts/show-target-health.sh $TG_ARN
../scripts/test-load-balancing.sh $ALB_URL 10
```
Expected: `web-1` is `unhealthy` (reason `Target.ResponseCodeMismatch`, 404) and **all 10 requests are served by `web-2`**.

Restore `web-1`:
```bash
aws ssm send-command --region ap-south-1 --instance-ids $WEB1 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["mv /var/www/html/health.disabled /var/www/html/health"]' \
  --comment "Project 20 - restore health check on web-1" --output text --query Command.CommandId
sleep 30
../scripts/show-target-health.sh $TG_ARN
../scripts/test-load-balancing.sh $ALB_URL 10
```
Expected: both targets `healthy` again and traffic is shared by both servers.

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - `terraform apply` complete with outputs (step 2)
- `2.png` - Two EC2 instances running in two AZs (step 3)
- `3.png` - Target group: health check settings and both targets `healthy` (step 4, console or CLI)
- `4.png` - **Load balancing: `test-load-balancing.sh` showing requests split between web-1 and web-2** (deliverable)
- `5.png` - Browser showing the ALB page served by web-1 and by web-2 after refresh
- `6.png` - Failover: web-1 `unhealthy` and all traffic going to web-2 (step 6)

## Troubleshooting
- Targets stay `initial` / `unhealthy` right after apply: user_data is still installing Apache - wait 2-3 minutes.
- `Target.Timeout`: check the web SG allows port 80 from the ALB SG and Apache is running (`systemctl status httpd` via SSM).
- `Target.ResponseCodeMismatch`: `/var/www/html/health` is missing - check `/var/log/cloud-init-output.log`.
- ALB returns `503`: no healthy targets in the target group.
- Every request goes to the same server: make sure the browser is not caching (use the script), and that stickiness is disabled on the target group.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project20-load-balanced-app/terraform
terraform destroy
```
The ALB is billed per hour - destroy it once the screenshots are taken.

## Verification
- Two EC2 instances run the app in two different Availability Zones.
- The ALB health check (`GET /health`, expect `200`) marks both targets `healthy`.
- Requests to the ALB DNS name are distributed across both instances.
- When one instance fails its health check it is removed from rotation and the other serves all traffic; it rejoins automatically once healthy.
- Instances are only reachable through the ALB.

## Deliverables
- Load balancing screenshot: `4.png` (plus supporting screenshots `1.png` - `3.png`, `5.png`, `6.png`)
