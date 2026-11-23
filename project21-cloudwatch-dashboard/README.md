# Project 21: CloudWatch Monitoring Dashboard

## Objective
Visualize application and infrastructure **performance** in a single **Amazon CloudWatch dashboard**: request rate, latency, HTTP errors and target health from the load balancer, plus CPU, memory, disk and network for each web server, with alarm status at the top.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- Monitored app: 2 x Amazon Linux 2023 EC2 (`t3.micro`, detailed monitoring on) running Apache behind an Application Load Balancer, managed via SSM (no SSH)
- CloudWatch agent on each instance publishing memory, disk, iowait and TCP connection metrics to the `CWAgent` namespace
- Dashboard: `shivam-project21-performance` (created by Terraform)
- Region: ap-south-1 (Mumbai)

## Dashboard layout
| Row | Widgets | Source |
| --- | --- | --- |
| 1 | Title + app link, **alarm status** for all 7 alarms | CloudWatch alarms |
| 2 | **Current performance** single values: requests (5 min), latency p90, 5xx errors, healthy / unhealthy hosts | `AWS/ApplicationELB` |
| 3 | ALB requests per minute, **target response time p50/p90/p99** (with alarm line), HTTP responses by status code (2xx/4xx/5xx) | `AWS/ApplicationELB` |
| 4 | **EC2 CPU %** per server (with alarm line), **memory used %**, root disk used % | `AWS/EC2`, `CWAgent` |
| 5 | Network in/out, established TCP connections + CPU iowait, target health + status checks | `AWS/EC2`, `CWAgent`, `AWS/ApplicationELB` |

## Alarms (shown on the dashboard)
| Alarm | Metric | Condition |
| --- | --- | --- |
| `shivam-project21-web-N-high-cpu` | `AWS/EC2 CPUUtilization` | Average > 70% for 2 of 3 minutes |
| `shivam-project21-web-N-high-memory` | `CWAgent mem_used_percent` | Average > 80% for 2 of 3 minutes |
| `shivam-project21-unhealthy-hosts` | `UnHealthyHostCount` | > 0 for 2 minutes |
| `shivam-project21-high-latency` | `TargetResponseTime` p90 | > 1 s for 2 of 3 minutes |
| `shivam-project21-target-5xx` | `HTTPCode_Target_5XX_Count` | > 5 per minute for 2 minutes |

## Architecture
```
   Ubuntu VM: generate-traffic.sh ---- HTTP ----> ALB shivam-project21-alb
              stress-instance.sh  ---- SSM -----+       |  AWS/ApplicationELB metrics
                                                |       v
                         +----------------------+-----------------------+
                         |  EC2 web-1 (ap-south-1a)   EC2 web-2 (ap-south-1b)
                         |  Apache: /  /cgi-bin/slow  /health
                         |  CloudWatch agent -> CWAgent (mem, disk, iowait, tcp)
                         |  Detailed monitoring -> AWS/EC2 (CPU, network, status)
                         +------------------------------+-----------------+
                                                        v
                         CloudWatch metrics + 7 alarms -> Dashboard shivam-project21-performance
```

## Project Structure
```
project21-cloudwatch-dashboard/
|-- terraform/
|   |-- providers.tf             # AWS provider
|   |-- variables.tf             # Region, CIDRs, instance type, alarm thresholds
|   |-- main.tf                  # VPC, ALB, 2 EC2s, IAM (SSM + CloudWatch agent),
|   |                            # CloudWatch alarms and the dashboard definition
|   |-- outputs.tf               # App URL, instance IDs, dashboard URL, alarm names
|   `-- templates/user_data.sh   # Apache + slow endpoint, CloudWatch agent config
`-- scripts/
    |-- generate-traffic.sh      # Mixed traffic (fast, slow, 404) for N seconds
    `-- stress-instance.sh       # CPU + memory stress on one server via SSM
```

## Technologies Used
- Amazon CloudWatch - dashboards, metrics, alarms, CloudWatch agent
- Elastic Load Balancing (ALB), Amazon EC2 (detailed monitoring), VPC, IAM
- AWS Systems Manager Run Command
- Terraform
- Apache HTTP Server, stress-ng, Bash, curl, Amazon Linux 2023

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Provision the infrastructure and dashboard
```bash
cd ~/aws-terraform-capstone/project21-cloudwatch-dashboard/terraform
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
read -r WEB1 WEB2 <<< "$(terraform output -json instance_ids | tr -d '[]"' | tr ',' ' ')"
chmod +x ../scripts/*.sh
```

### 3. Confirm metrics are arriving
Wait 3-5 minutes after apply (user_data installs Apache and the CloudWatch agent), then:
```bash
curl -s $ALB_URL/ | grep "Served by"
aws cloudwatch list-metrics --region ap-south-1 --namespace CWAgent \
  --dimensions Name=InstanceId,Value=$WEB1 --query "Metrics[].MetricName" --output table
```
Expected: the page is served, and `mem_used_percent`, `disk_used_percent`, `cpu_usage_iowait`, `netstat_tcp_established` are listed.

If the CWAgent list is empty, check the agent on the instance:
```bash
aws ssm send-command --region ap-south-1 --instance-ids $WEB1 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status"]' \
  --query Command.CommandId --output text
```

### 4. Generate application traffic
Run 10 minutes of mixed traffic (fast pages, slow pages, 404s) from 5 parallel clients:
```bash
../scripts/generate-traffic.sh $ALB_URL 600 5
```

### 5. Generate CPU and memory load (in a second terminal while traffic runs)
```bash
cd ~/aws-terraform-capstone/project21-cloudwatch-dashboard/terraform
WEB1=$(terraform output -json instance_ids | tr -d '[]"' | cut -d, -f1)
../scripts/stress-instance.sh $WEB1 300
```
Expected after 2-3 minutes: `web-1` CPU climbs above the 70% alarm line, memory rises, and `shivam-project21-web-1-high-cpu` turns **In alarm** on the dashboard.

### 6. Open the dashboard
```bash
terraform output -raw dashboard_url
```
Open the URL, set the time range to **1h** and enable **auto refresh (1 minute)**. You should see:
- Request rate and the 2xx/4xx split from `generate-traffic.sh`
- Latency p90 around 0.5 s from the `/cgi-bin/slow` endpoint
- `web-1` CPU and memory spiking during the stress test, `web-2` staying low
- 2 healthy hosts, 0 unhealthy, root disk usage, network and TCP connections per server

Confirm from the CLI as well:
```bash
aws cloudwatch describe-alarms --region ap-south-1 --alarm-name-prefix shivam-project21 \
  --query "MetricAlarms[].[AlarmName,StateValue]" --output table
aws cloudwatch get-dashboard --region ap-south-1 --dashboard-name shivam-project21-performance \
  --query DashboardName --output text
```

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - `terraform apply` complete with outputs (step 2)
- `2.png` - CWAgent metrics listed for the instance (step 3)
- `3.png` - **Full CloudWatch dashboard with traffic and the CPU/memory spike visible** (deliverable)
- `4.png` - Dashboard close-up: alarm status bar with the high CPU alarm **In alarm** and the CPU graph above the alarm line
- `5.png` - `describe-alarms` output (step 6)

## Troubleshooting
- Memory/disk widgets empty: the CloudWatch agent is not running or the role is missing `CloudWatchAgentServerPolicy` - check `amazon-cloudwatch-agent-ctl -a status` and `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`.
- ALB widgets empty: no traffic yet - ALB metrics are only published when there are requests.
- Graphs look flat: set the dashboard time range to 1h or 3h and the period to 1 minute.
- High CPU alarm stays `OK`: let the stress run at least 3 minutes; `t3.micro` burst credits can be checked with the `CPUCreditBalance` metric.
- Alarms in `INSUFFICIENT_DATA` right after apply: normal until the first datapoints arrive.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project21-cloudwatch-dashboard/terraform
terraform destroy
```
The ALB, detailed monitoring and custom metrics are billed - destroy once the screenshots are taken.

## Verification
- The dashboard `shivam-project21-performance` exists and shows ALB, EC2 and CloudWatch agent metrics.
- Request count, latency percentiles and status codes change while `generate-traffic.sh` runs.
- CPU and memory for the stressed server rise on the dashboard and the high CPU alarm fires.
- Alarm status for all alarms is visible at the top of the dashboard.

## Deliverables
- Dashboard screenshot: `3.png` (plus supporting screenshots `1.png`, `2.png`, `4.png`, `5.png`)
