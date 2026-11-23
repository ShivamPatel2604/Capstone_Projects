# Project 19: Scheduled S3 Backup

## Objective
Automate a backup routine: a **cron job** on a Linux server archives its application and system logs every 5 minutes and uploads them to a private, encrypted **Amazon S3** bucket, then the backup files are listed and verified from S3.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- Backup source: 1 x Amazon Linux 2023 EC2 instance (`t3.micro`) running Apache, managed via SSM (no SSH / port 22)
- Scheduler: `cronie` (`crond`), job file `/etc/cron.d/s3-log-backup`, created with **SSM Run Command**
- Backup script: `/usr/local/bin/s3-log-backup.sh` (installed by user_data, uses AWS CLI v2)
- Destination: S3 bucket `shivam-project19-log-backups-<account-id>`
- Region: ap-south-1 (Mumbai)

## What is backed up
| Source on EC2 | Contents |
| --- | --- |
| `/var/log/httpd/` | Apache access and error logs |
| `/var/log/messages` | System log |
| `/var/log/secure` | Authentication / security log |
| `/var/log/cron` | Cron daemon log (shows each backup run) |

Each run creates one archive:
```
s3://<bucket>/log-backups/<instance-id>/YYYY/MM/DD/logs-<instance-id>-<YYYYMMDDTHHMMSSZ>.tar.gz
```
The SHA-256 checksum of the archive is stored as object metadata (`x-amz-meta-sha256`) for integrity checks.

## Bucket protection
- Block Public Access (all four settings) + `BucketOwnerEnforced` (ACLs disabled)
- Default encryption SSE-S3 (AES-256)
- Versioning enabled
- Bucket policy denies non-HTTPS access
- Lifecycle: backups expire after 30 days, old versions after 7 days
- EC2 role can only `PutObject` under `log-backups/*` (cannot read or delete backups)

## Architecture
```
                     SSM Run Command (create cron job, run backup)
Ubuntu VM ---------------------------------------------------+
 (Terraform, AWS CLI)                                        v
                    +-------------- EC2: shivam-project19-web ---------------+
Internet --HTTP 80->| Apache -> /var/log/httpd/*  rsyslog -> /var/log/messages |
                    |                                         /secure, /cron  |
                    |  crond: */5 * * * *  ->  s3-log-backup.sh               |
                    |                          tar.gz + sha256 -> aws s3 cp   |
                    +-------------------------------|-------------------------+
                                                    | HTTPS 443 (IAM role)
                                                    v
          S3: shivam-project19-log-backups-<account>/log-backups/<instance-id>/YYYY/MM/DD/
              (private, encrypted, versioned, 30-day lifecycle)
                                                    |
Ubuntu VM <---- scripts/show-backups.sh (list, download, verify checksum) ----+
```

## Project Structure
```
project19-scheduled-s3-backup/
|-- terraform/
|   |-- providers.tf             # AWS provider
|   |-- variables.tf             # Region, CIDRs, instance type, backup prefix, retention
|   |-- main.tf                  # VPC, SG, S3 bucket (+ encryption, versioning, lifecycle,
|   |                            # policy), IAM (SSM + S3 upload), EC2
|   |-- outputs.tf               # Instance ID, bucket, backup location, console URL
|   `-- templates/user_data.sh   # Installs Apache, rsyslog, cronie and the backup script
`-- scripts/
    |-- create-cron-job.json     # SSM Run Command parameters that create the cron job
    `-- show-backups.sh          # Lists S3 backups and verifies the latest archive
```

## Technologies Used
- Amazon S3 (encryption, versioning, lifecycle, bucket policy)
- cron (`cronie`), Bash, tar/gzip, AWS CLI v2
- AWS Systems Manager Run Command
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
cd ~/aws-terraform-capstone/project19-scheduled-s3-backup/terraform
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
BUCKET=$(terraform output -raw backup_bucket)
```

### 3. Confirm the instance is registered with Systems Manager
Wait 2-3 minutes after apply, then:
```bash
aws ssm describe-instance-information --region ap-south-1 \
  --filters Key=InstanceIds,Values=$INSTANCE_ID \
  --query "InstanceInformationList[].[InstanceId,PingStatus,PlatformName]" --output table
```
Expected: `Online`.

### 4. Confirm the bucket is empty and protected
```bash
aws s3 ls s3://$BUCKET --recursive --region ap-south-1
aws s3api get-bucket-encryption --bucket $BUCKET --region ap-south-1 --output table
aws s3api get-bucket-versioning --bucket $BUCKET --region ap-south-1
aws s3api get-public-access-block --bucket $BUCKET --region ap-south-1 --output table
aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET --region ap-south-1 --output table
```
Expected: no objects, `AES256`, `Enabled`, all public-access settings `True`, expiration 30 days.

### 5. Generate some log data
```bash
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code} /\n" $WEB_URL/
  curl -s -o /dev/null -w "%{http_code} /missing\n" $WEB_URL/missing
done
```

### 6. Run the backup script once manually (test before scheduling)
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["/usr/local/bin/s3-log-backup.sh"]' \
  --query Command.CommandId --output text)
sleep 10
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query "[Status,StandardOutputContent,StandardErrorContent]" --output text
```
Expected: `Success` and `... uploaded s3://shivam-project19-log-backups-.../log-backups/i-.../logs-i-...tar.gz (... bytes, sha256=...)`.

### 7. Create the cron job (SSM Run Command)
The job file content is in `scripts/create-cron-job.json` - schedule `*/5 * * * *` (every 5 minutes):
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters file://../scripts/create-cron-job.json \
  --comment "Project 19 - create S3 log backup cron job" \
  --query Command.CommandId --output text)
sleep 5
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query "[Status,StandardOutputContent]" --output text
```
Expected: `Success`, the contents of `/etc/cron.d/s3-log-backup` and `active` for `crond`.

### 8. Wait for scheduled runs and check the cron log
Wait at least 10 minutes (two runs), then:
```bash
CMD_ID=$(aws ssm send-command --region ap-south-1 --instance-ids $INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["echo === cron runs ===; grep s3-log-backup /var/log/cron | tail -n 5","echo === backup log ===; tail -n 5 /var/log/s3-backup.log"]' \
  --query Command.CommandId --output text)
sleep 5
aws ssm get-command-invocation --region ap-south-1 --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query StandardOutputContent --output text
```
Expected: `CROND[...]: (root) CMD (/usr/local/bin/s3-log-backup.sh ...)` lines every 5 minutes and matching `uploaded s3://...` lines.

### 9. Show the S3 backup files
```bash
chmod +x ../scripts/show-backups.sh
../scripts/show-backups.sh $BUCKET
```
The script prints:
- all backup objects with sizes and a total (`aws s3 ls --summarize`)
- the 10 latest backups as a table
- metadata of the latest backup (encryption `AES256`, version ID, `sha256`)
- an integrity check (downloaded checksum = stored checksum -> `OK`)
- the list of log files inside the archive

Also open the backup folder in the S3 console:
```bash
terraform output -raw backup_console_url
```

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - Manual backup run succeeded (step 6)
- `2.png` - Cron job created: `/etc/cron.d/s3-log-backup` and `crond` active (step 7)
- `3.png` - Cron log showing scheduled runs every 5 minutes (step 8)
- `4.png` - `show-backups.sh` output listing the backups and checksum `OK` (step 9)
- `5.png` - **S3 console showing the backup files** (deliverable)

## Troubleshooting
- Instance not `Online` in SSM: wait a few minutes; the instance needs outbound internet access.
- `/usr/local/bin/s3-log-backup.sh: No such file`: user_data is still running - check `/var/log/cloud-init-output.log` with `AWS-RunShellScript`.
- `AccessDenied` on upload: the role can only write under `log-backups/`; check the `PREFIX` in the script matches `backup_prefix`.
- No cron runs: cron.d files must be mode 644, owned by root, end with a newline and include the user field (`root`); check `systemctl status crond`.
- `show-backups.sh` shows no files: wait for the next 5-minute mark or rerun step 6.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project19-scheduled-s3-backup/terraform
terraform destroy
```
The bucket has `force_destroy = true`, so `destroy` also deletes all backup objects and versions.

## Verification
- Backup script uploads a `.tar.gz` archive with a SHA-256 checksum to S3.
- `/etc/cron.d/s3-log-backup` runs the script every 5 minutes; `/var/log/cron` shows each run.
- New backup objects appear in S3 under `log-backups/<instance-id>/YYYY/MM/DD/` every 5 minutes.
- Downloaded backup checksum matches the stored checksum and the archive contains the Apache and system logs.

## Deliverables
- Backup screenshot: `5.png` (plus supporting screenshots `1.png` - `4.png`)
