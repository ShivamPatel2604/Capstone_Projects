# Project 17: Log Forwarding to CloudWatch

## Objective
Central log management: install the **Amazon CloudWatch agent** on a Linux server and forward its application and system logs to **CloudWatch Logs**, then visualise them on a CloudWatch log dashboard.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- Log source: 1 x Amazon Linux 2023 EC2 instance (`t3.micro`) running Apache, managed via SSM (no SSH / port 22)
- Log agent: Amazon CloudWatch agent, installed with **SSM Run Command** (`AWS-ConfigureAWSPackage`)
- Agent config: stored centrally in SSM Parameter Store (`AmazonCloudWatch-shivam-project17`)
- Region: ap-south-1 (Mumbai)

## Logs forwarded
| Source file on EC2 | CloudWatch log group |
| --- | --- |
| `/var/log/httpd/access_log` | `/shivam-project17/httpd-access` |
| `/var/log/httpd/error_log` | `/shivam-project17/httpd-error` |
| `/var/log/messages` | `/shivam-project17/system` |
| `/var/log/secure` | `/shivam-project17/secure` |

Each instance writes to a log stream named after its instance ID. Retention: 7 days.

## Architecture
```
                       SSM Run Command (install + configure agent)
Ubuntu VM ---------------------------------------------------+
 (Terraform, AWS CLI)                                         v
                         +-------------- EC2: shivam-project17-web ----------------+
Internet --HTTP 80-->    | Apache -> /var/log/httpd/*   rsyslog -> /var/log/messages|
                         |                 \                 /          /secure   |
                         |               CloudWatch agent (reads config from SSM) |
                         +-------------------------|-------------------------------+
                                                   | HTTPS 443
                                                   v
                            CloudWatch Logs: /shivam-project17/* log groups
                                   |                         |
                         Metric filters (2xx/4xx/5xx)   Logs Insights queries
                                   \                         /
                               CloudWatch dashboard: shivam-project17-logs
```

## Project Structure
```
project17-cloudwatch-log-forwarding/
├── terraform/
│   ├── providers.tf             # AWS provider
│   ├── variables.tf             # Region, CIDRs, instance type, retention
│   ├── main.tf                  # VPC, SG, IAM (SSM + CloudWatch agent), EC2, log groups,
│   │                            # agent config parameter, metric filters, dashboard
│   ├── outputs.tf               # Instance ID, URL, log groups, dashboard URL
│   └── templates/user_data.sh   # Installs Apache + rsyslog (NOT the agent)
└── scripts/
    └── generate-traffic.sh      # Sends 200 + 404 requests to create log data
```

## Technologies Used
- Amazon CloudWatch agent, CloudWatch Logs, Logs Insights, Metric Filters, Dashboards
- AWS Systems Manager (Run Command, Parameter Store)
- Terraform
- Amazon EC2 / VPC / IAM
- Apache HTTP Server, rsyslog, Amazon Linux 2023

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Provision the infrastructure
```bash
cd ~/aws-terraform-capstone/project17-cloudwatch-log-forwarding/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Save the values for later steps:
```bash
INSTANCE_ID=$(terraform output -raw instance_id)
WEB_URL=$(terraform output -raw web_url)
CONFIG_PARAM=$(terraform output -raw agent_config_parameter)
```

### 3. Confirm the instance is registered with Systems Manager
Wait 2-3 minutes after apply, then:
```bash
aws ssm describe-instance-information --region ap-south-1 \
  --filters Key=InstanceIds,Values=$INSTANCE_ID \
  --query "InstanceInformationList[].[InstanceId,PingStatus,PlatformName]" --output table
```
Expected: `Online`.

### 4. Confirm the agent is not installed yet
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["rpm -q amazon-cloudwatch-agent || true"]' \
  --query Command.CommandId --output text)
sleep 5
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query StandardOutputContent --output text
```
Expected: `package amazon-cloudwatch-agent is not installed`.

### 5. Install the log agent (SSM Run Command)
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AWS-ConfigureAWSPackage \
  --parameters '{"action":["Install"],"name":["AmazonCloudWatchAgent"]}' \
  --query Command.CommandId --output text)
sleep 20
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query "[Status,StandardOutputContent]" --output text
```
Expected: `Success` and `Successfully installed arn:aws:ssm:::package/AmazonCloudWatchAgent`.

### 6. Review the agent configuration
```bash
aws ssm get-parameter --region ap-south-1 --name $CONFIG_PARAM \
  --query Parameter.Value --output text | python3 -m json.tool
```

### 7. Configure and start the agent (send logs to CloudWatch)
The agent pulls its configuration from Parameter Store:
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AmazonCloudWatch-ManageAgent \
  --parameters "{\"action\":[\"configure\"],\"mode\":[\"ec2\"],\"optionalConfigurationSource\":[\"ssm\"],\"optionalConfigurationLocation\":[\"$CONFIG_PARAM\"],\"optionalRestart\":[\"yes\"]}" \
  --query Command.CommandId --output text)
sleep 20
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query Status --output text
```
Expected: `Success`.

Check the agent status:
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AmazonCloudWatch-ManageAgent \
  --parameters '{"action":["status"]}' \
  --query Command.CommandId --output text)
sleep 5
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query StandardOutputContent --output text
```
Expected: `"status": "running"`.

### 8. Generate log data
```bash
chmod +x ../scripts/generate-traffic.sh
../scripts/generate-traffic.sh $WEB_URL 30
```
Output shows `200` for `/` and `/index.html`, and `404` for `/admin` and `/missing-page-*`.

### 9. Verify the logs arrived in CloudWatch
```bash
aws logs describe-log-groups --region ap-south-1 --log-group-name-prefix /shivam-project17 \
  --query "logGroups[].[logGroupName,retentionInDays,storedBytes]" --output table

aws logs describe-log-streams --region ap-south-1 --log-group-name /shivam-project17/httpd-access \
  --query "logStreams[].logStreamName" --output text

aws logs tail /shivam-project17/httpd-access --region ap-south-1 --since 10m | tail -n 10
aws logs tail /shivam-project17/system --region ap-south-1 --since 30m | tail -n 10
```

### 10. Query logs centrally with Logs Insights (optional)
```bash
QUERY_ID=$(aws logs start-query --region ap-south-1 \
  --log-group-name /shivam-project17/httpd-access \
  --start-time $(date -d '-30 minutes' +%s) --end-time $(date +%s) \
  --query-string "parse @message '* - - [*] \"* * *\" * *' as ip, ts, method, path, proto, status, rest | stats count(*) by status" \
  --query queryId --output text)
sleep 5
aws logs get-query-results --region ap-south-1 --query-id $QUERY_ID --output table
```

### 11. Open the log dashboard
```bash
terraform output -raw dashboard_url
```
Open the URL in the AWS console (set the time range to **1h**). Metric widgets can take 2-3 minutes to show data.

## Dashboard: `shivam-project17-logs`
- HTTP requests vs 4xx / 5xx (metric filters on the access log)
- Requests by HTTP status code (pie)
- Top requested paths
- Log volume per source (all four log groups)
- Latest Apache access log entries
- Apache error log
- System and security logs

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` – SSM Run Command output: CloudWatch agent installed (step 5)
- `2.png` – Agent configured and status `running` (step 7)
- `3.png` – `/shivam-project17/*` log groups and `aws logs tail` output (step 9)
- `4.png` – **CloudWatch log dashboard** `shivam-project17-logs` (deliverable)

## Troubleshooting
- Instance not `Online` in SSM: wait a few minutes; the instance needs outbound internet access.
- `AmazonCloudWatch-ManageAgent` fails with `AccessDenied` on the parameter: the parameter name must start with `AmazonCloudWatch-`.
- No log streams: check agent status (step 7) and that `/var/log/httpd/access_log` has entries (run step 8).
- Dashboard metric widgets empty: metric filters only count events received *after* they were created; generate traffic again.
- Agent logs on the instance: `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log` (read with `AWS-RunShellScript`).

## Cleanup
```bash
cd ~/aws-terraform-capstone/project17-cloudwatch-log-forwarding/terraform
terraform destroy
```
Log groups are created by Terraform, so `destroy` removes them along with the logs.

## Verification
- CloudWatch agent installed via SSM Run Command and status is `running`.
- Four log groups under `/shivam-project17/` each contain a log stream named after the instance ID.
- `aws logs tail` shows live Apache and system log events.
- Dashboard shows request/error counts and log entries from all sources.

## Deliverables
- Log dashboard screenshot: `4.png` (plus supporting screenshots `1.png` – `3.png`)
