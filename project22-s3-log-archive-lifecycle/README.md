# Project 22: S3 Log Archive with Lifecycle

## Objective
Lower log storage cost: upload application logs to a private **Amazon S3** bucket and attach **lifecycle rules** that automatically move logs to cheaper storage classes as they age and **expire** (delete) them when they are no longer needed.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- Bucket: `shivam-project22-log-archive-<account-id>` (created by Terraform)
- Log upload: `scripts/upload-logs.sh` (generates realistic access/debug logs and uploads them with AWS CLI v2)
- Region: ap-south-1 (Mumbai)

## Lifecycle rules
| Rule ID | Applies to | Action |
| --- | --- | --- |
| `archive-and-expire-app-logs` | `logs/` | Day 30 -> **Standard-IA**, day 90 -> **Glacier Instant Retrieval**, day 180 -> **Glacier Deep Archive**, day 365 -> **expire (delete)**. Noncurrent versions deleted after 30 days, incomplete multipart uploads aborted after 7 days |
| `expire-debug-logs` | `debug/` | **Expire (delete) after 7 days**. Noncurrent versions deleted after 1 day, incomplete multipart uploads aborted after 1 day |

```
logs/   STANDARD --30d--> STANDARD_IA --90d--> GLACIER_IR --180d--> DEEP_ARCHIVE --365d--> deleted
debug/  STANDARD --7d--> deleted
```

All day values are Terraform variables (`terraform/variables.tf`) and respect S3 rules: Standard-IA needs objects at least 30 days old, each storage class stays at least as long as its minimum billable duration (IA 30 d, Glacier IR 90 d, Deep Archive 180 d), so no early-deletion fees are charged.

Object key layout:
```
s3://<bucket>/logs/<app>/YYYY/MM/DD/<app>-YYYY-MM-DD.log.gz        (gzip, ~165 KB each)
s3://<bucket>/debug/<app>/YYYY/MM/DD/<app>-debug-YYYY-MM-DD.log    (plain text)
```

## Why this lowers cost
Approximate S3 storage prices in ap-south-1 (per GB-month, check the [S3 pricing page](https://aws.amazon.com/s3/pricing/) for current values):

| Storage class | Price / GB-month | Used for logs aged |
| --- | --- | --- |
| S3 Standard | ~$0.025 | 0 - 30 days |
| S3 Standard-IA | ~$0.019 | 30 - 90 days |
| S3 Glacier Instant Retrieval | ~$0.005 | 90 - 180 days |
| S3 Glacier Deep Archive | ~$0.002 | 180 - 365 days |
| (expired) | $0 | > 365 days |

Example: 100 GB of new logs per month. Keeping everything in Standard grows without limit (after one year: 1.2 TB, ~$30/month and still rising). With this lifecycle the bucket stabilises at 1.2 TB spread across classes (100 GB Standard + 200 GB IA + 300 GB Glacier IR + 600 GB Deep Archive) costing roughly **$9/month (~70% less)**, and never grows beyond one year of data. Debug logs, which are only useful for a few days, never accumulate at all.

Other cost/safety controls:
- Logs are gzipped before upload (~8x smaller).
- Objects < 128 KB are not transitioned (`transition_default_minimum_object_size = all_storage_classes_128K`), because per-object transition fees would exceed the savings.
- Versioning protects against accidental overwrite/delete, and noncurrent versions expire so old versions do not add hidden cost.
- Incomplete multipart uploads are aborted so their invisible parts are not billed.

## Bucket protection
- Block Public Access (all four settings) + `BucketOwnerEnforced` (ACLs disabled)
- Default encryption SSE-S3 (AES-256)
- Versioning enabled
- Bucket policy denies non-HTTPS access

## Architecture
```
Ubuntu VM (Terraform, AWS CLI)
   |
   |-- terraform apply ------------> S3 bucket shivam-project22-log-archive-<account>
   |                                   private | SSE-S3 | versioned | HTTPS-only
   |                                   Lifecycle configuration:
   |                                     archive-and-expire-app-logs (logs/)
   |                                     expire-debug-logs           (debug/)
   |
   |-- scripts/upload-logs.sh ----> logs/web|api/YYYY/MM/DD/*.log.gz
   |                                debug/web|api/YYYY/MM/DD/*.log
   |
   `-- scripts/show-lifecycle.sh -> rules, storage classes, x-amz-expiration per object
```

## Project Structure
```
project22-s3-log-archive-lifecycle/
|-- terraform/
|   |-- providers.tf        # AWS provider
|   |-- variables.tf        # Region, prefixes, transition and expiration days
|   |-- main.tf             # S3 bucket (+ encryption, versioning, public access block,
|   |                       # HTTPS-only policy) and lifecycle configuration
|   `-- outputs.tf          # Bucket, prefixes, rule IDs, console URLs
`-- scripts/
    |-- upload-logs.sh      # Generates and uploads app (gzip) and debug logs
    `-- show-lifecycle.sh   # Shows lifecycle rules and the expiration applied to objects
```

## Technologies Used
- Amazon S3 (lifecycle rules, storage classes, encryption, versioning, bucket policy)
- Terraform
- AWS CLI v2, Bash, gzip
- Linux (Ubuntu)

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Create the bucket and lifecycle rules
```bash
cd ~/aws-terraform-capstone/project22-s3-log-archive-lifecycle/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
BUCKET=$(terraform output -raw log_bucket)
```

### 3. Confirm the bucket is protected
```bash
aws s3api get-bucket-encryption --bucket $BUCKET --region ap-south-1 --output table
aws s3api get-bucket-versioning --bucket $BUCKET --region ap-south-1
aws s3api get-public-access-block --bucket $BUCKET --region ap-south-1 --output table
```
Expected: `AES256`, `Enabled`, all public-access settings `True`.

### 4. Upload logs to S3
```bash
chmod +x ../scripts/*.sh
../scripts/upload-logs.sh $BUCKET 7
```
Uploads 7 days of logs for the `web` and `api` apps: 14 gzipped access logs under `logs/` and 14 debug logs under `debug/`.
Expected: `uploaded s3://.../logs/web/2026/11/23/web-2026-11-23.log.gz (... bytes)` lines and `Total Objects: 28`.

Verify a log can be read back:
```bash
aws s3 ls s3://$BUCKET/logs/ --recursive --human-readable
aws s3 cp s3://$BUCKET/logs/web/$(date -u +%Y/%m/%d)/web-$(date -u +%F).log.gz - | zcat | head -n 5
```

### 5. Show the lifecycle rules and their effect on the logs
```bash
../scripts/show-lifecycle.sh $BUCKET
```
The script prints:
- both rules with prefix, status and expiration days
- the storage-class transitions (30 / 90 / 180 days)
- every object with its current storage class (`STANDARD` right after upload)
- the `x-amz-expiration` header for a `logs/` and a `debug/` object, e.g.
  `expiry-date="Wed, 24 Nov 2027 00:00:00 GMT", rule-id="archive-and-expire-app-logs"` and
  `expiry-date="Tue, 01 Dec 2026 00:00:00 GMT", rule-id="expire-debug-logs"` - S3's own confirmation of when each log will be deleted.

### 6. View the rule in the S3 console (deliverable)
```bash
terraform output -raw lifecycle_console_url
```
Open the URL -> **Management** tab -> **Lifecycle rules**. Both rules are listed as `Enabled`. Click `archive-and-expire-app-logs` to see the **Review transition and expiration actions** timeline (Day 0 -> 30 -> 90 -> 180 -> 365). Then open any object under `logs/` -> **Properties** -> **Management configurations** to see its expiration date and rule.

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - `terraform apply` output / `terraform output` (step 2)
- `2.png` - `upload-logs.sh` output showing the uploaded logs (step 4)
- `3.png` - `show-lifecycle.sh` output with rules and `x-amz-expiration` (step 5)
- `4.png` - **S3 console Lifecycle rules list** (deliverable)
- `5.png` - **S3 console rule detail with the transition/expiration timeline** (deliverable)

## Troubleshooting
- `BucketAlreadyExists`: bucket names are global; change `project_name` in `variables.tf`.
- `InvalidArgument: 'Days' in Transition action for StorageClass 'STANDARD_IA' must be greater than or equal to 30`: keep `transition_to_ia_days >= 30`.
- `Expiration` missing in `head-object`: the object key must start with `logs/` or `debug/`; S3 may take a few minutes to start returning the header after rules are created.
- Objects still `STANDARD`: expected - transitions run once a day and only after the configured age is reached. Lifecycle rules use the upload date, so backdated log file names do not age faster.
- `upload-logs.sh: date: invalid option`: the script needs GNU `date` (Linux), not macOS/BSD `date`.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project22-s3-log-archive-lifecycle/terraform
terraform destroy
```
The bucket has `force_destroy = true`, so `destroy` also deletes all logs and versions.

## Verification
- 28 log objects are uploaded under `logs/` and `debug/`, encrypted with AES-256.
- The bucket has two enabled lifecycle rules: tiered archive + 365-day expiry for `logs/`, 7-day expiry for `debug/`.
- `head-object` returns an `x-amz-expiration` header naming the matching rule for every uploaded log.
- The S3 console shows the rules and the transition/expiration timeline.

## Deliverables
- S3 rule screenshots: `4.png` and `5.png` (plus supporting screenshots `1.png` - `3.png`)
