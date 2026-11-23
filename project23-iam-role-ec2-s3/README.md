# Project 23: IAM Role Based Access

## Objective
Secure resource usage: give an **EC2 instance** access to **Amazon S3** through an **IAM role** (instance profile) instead of access keys, and scope that role with a **least-privilege policy** so the instance can only do exactly what it needs.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI)
- EC2: 1 x Amazon Linux 2023 `t3.micro`, no SSH / no inbound ports, managed via SSM
- IAM role: `shivam-project23-ec2-s3-role` attached through instance profile `shivam-project23-ec2-s3-profile`
- S3: `shivam-project23-app-data-<account-id>` (allowed) and `shivam-project23-restricted-<account-id>` (no access)
- Test: `scripts/run-cli-test.sh` runs `scripts/s3-access-test.sh` on the instance with SSM Run Command and saves the **CLI test output**
- Region: ap-south-1 (Mumbai)

## How the role works
```
EC2 instance --(instance profile)--> IAM role --(trust: ec2.amazonaws.com)--> STS temporary credentials
     |                                                                              |
     `-- AWS CLI on the instance <-- IMDSv2 (169.254.169.254) <---------------------'
         (no access keys on disk, credentials rotate automatically ~every hour)
```

## Role permissions (least privilege)
| Policy | Statement | Actions | Resource |
| --- | --- | --- | --- |
| `shivam-project23-s3-app-data-access` | `ListAppBucket` | `s3:ListBucket`, `s3:GetBucketLocation` | `arn:aws:s3:::<app-bucket>` |
| | `ReadWriteAllowedPrefix` | `s3:GetObject`, `s3:PutObject` | `arn:aws:s3:::<app-bucket>/app-data/*` |
| `AmazonSSMManagedInstanceCore` (AWS managed) | - | SSM agent only | - |

Everything else is implicitly denied: no `DeleteObject`, no access outside `app-data/`, no other bucket, no `ListAllMyBuckets`, no other AWS service.

## Expected test results
| # | Test | Expected |
| --- | --- | --- |
| 1 | `aws sts get-caller-identity` (shows `assumed-role/shivam-project23-ec2-s3-role/i-...`) | ALLOW |
| 2 | List app bucket | ALLOW |
| 3 | Read `app-data/welcome.txt` | ALLOW |
| 4 | Upload to `app-data/` | ALLOW |
| 5 | Download the uploaded file and compare | ALLOW |
| 6 | `head-object` shows `AES256` encryption | ALLOW |
| 7 | Upload to `admin/` (outside prefix) | DENY |
| 8 | Read `admin/config.txt` (outside prefix) | DENY |
| 9 | Delete an object | DENY |
| 10 | List restricted bucket | DENY |
| 11 | Read `secret.txt` in restricted bucket | DENY |
| 12 | `aws s3 ls` (list all buckets) | DENY |
| 13 | `aws ec2 describe-instances` | DENY |
| 14 | `aws iam list-users` | DENY |

A test **passes** when the actual result matches the expected one, so denied calls are a success - they prove the policy is enforced.

## Security controls
- No IAM user or access keys on the instance - credentials come from the role via IMDS and expire automatically.
- IMDSv2 required (`http_tokens = required`, hop limit 1) to protect role credentials from SSRF and containers.
- Security group has **no inbound rules**; shell access only through SSM (audited in CloudTrail).
- Buckets: Block Public Access, `BucketOwnerEnforced` (ACLs disabled), SSE-S3 encryption, HTTPS-only bucket policy.
- Encrypted gp3 root volume.

## Architecture
```
Ubuntu VM (Terraform, AWS CLI)
   |
   |-- terraform apply --> VPC 10.23.0.0/16, public subnet, IGW, SG (no inbound)
   |                       IAM role + instance profile + S3 policy
   |                       EC2 i-... (AL2023, IMDSv2, role attached)
   |                       S3 app bucket       app-data/welcome.txt, admin/config.txt
   |                       S3 restricted bucket secret.txt
   |
   `-- scripts/run-cli-test.sh --SSM Run Command--> EC2: s3-access-test.sh
                                                       |-- role credentials (IMDSv2)
                                                       |-- ALLOW  app bucket / app-data/*
                                                       `-- DENY   everything else
                       <-- output saved to cli-test-output.txt
```

## Project Structure
```
project23-iam-role-ec2-s3/
|-- terraform/
|   |-- providers.tf        # AWS provider
|   |-- variables.tf        # Region, names, CIDRs, instance type, allowed prefix
|   |-- main.tf             # VPC, SG, S3 buckets + seed objects, IAM role/policy/
|   |                       # instance profile, EC2 instance
|   `-- outputs.tf          # Instance, buckets, role, policy, console URLs
|-- scripts/
|   |-- s3-access-test.sh   # Runs on EC2: credential source + allow/deny tests
|   `-- run-cli-test.sh     # Runs on the VM: sends the test via SSM, saves output
`-- cli-test-output.txt     # Generated CLI test output (deliverable)
```

## Technologies Used
- AWS IAM (roles, trust policy, instance profiles, least-privilege policies)
- Amazon EC2 (IMDSv2), Amazon S3, AWS STS
- AWS Systems Manager (Run Command)
- Terraform, AWS CLI v2, Bash
- Linux (Ubuntu, Amazon Linux 2023)

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Create the role, buckets and instance
```bash
cd ~/aws-terraform-capstone/project23-iam-role-ec2-s3/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

### 3. Confirm the role is attached to the instance
```bash
INSTANCE_ID=$(terraform output -raw instance_id)
ROLE=$(terraform output -raw role_name)

aws ec2 describe-instances --instance-ids $INSTANCE_ID --region ap-south-1 \
  --query "Reservations[0].Instances[0].{Id:InstanceId,State:State.Name,Profile:IamInstanceProfile.Arn,IMDS:MetadataOptions.HttpTokens}" \
  --output table

aws iam get-role --role-name $ROLE \
  --query "Role.{Role:RoleName,Trust:AssumeRolePolicyDocument.Statement[0].Principal.Service}" --output table
aws iam list-attached-role-policies --role-name $ROLE --output table
aws iam get-policy-version --policy-arn $(terraform output -raw s3_policy_arn) --version-id v1 \
  --query "PolicyVersion.Document" --output json
```
Expected: instance profile `shivam-project23-ec2-s3-profile`, `HttpTokens = required`, trust `ec2.amazonaws.com`, two attached policies.

### 4. Run the CLI test on the instance (deliverable)
```bash
chmod +x ../scripts/*.sh
../scripts/run-cli-test.sh
```
The script waits until the instance is `Online` in SSM, runs the test on the instance, prints the output and saves it to `project23-iam-role-ec2-s3/cli-test-output.txt`.

Expected output (abridged):
```
=== 1. Where do the credentials come from? ===
Role (IMDSv2)    : shivam-project23-ec2-s3-role
  "Type" : "AWS-HMAC",
  "Expiration" : "2026-11-23T21:10:00Z"
Static key file  : none (~/.aws/credentials does not exist)
      Name                    Value             Type    Location
access_key     ****************ABCD         iam-role
...
--- Identify caller (assumed role, no keys) (expected: ALLOW)
|  Arn  |  arn:aws:sts::<account>:assumed-role/shivam-project23-ec2-s3-role/i-0abc...  |
...
--- Upload outside app-data/ (expected: DENY)
upload failed: ... An error occurred (AccessDenied) when calling the PutObject operation ...
=> DENY ... PASS
...
 SUMMARY  (14 passed, 0 failed)
PASS  ALLOW  Identify caller (assumed role, no keys)
...
PASS  DENY   Use IAM (ListUsers)
```

Optional - run it interactively instead (requires the Session Manager plugin):
```bash
aws ssm start-session --target $INSTANCE_ID --region ap-south-1
# on the instance:
aws sts get-caller-identity
aws s3 ls s3://<app-bucket>/app-data/
aws s3 ls s3://<restricted-bucket>/      # AccessDenied
```

### 5. Commit the CLI test output
```bash
cd ~/aws-terraform-capstone
git add project23-iam-role-ec2-s3/cli-test-output.txt
git commit -m "Add Project 23 CLI test output"
git push
```

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - `terraform apply` / `terraform output` (step 2)
- `2.png` - role attached to the instance and role policies (step 3)
- `3.png` - **`run-cli-test.sh` output: credential source and ALLOW tests** (deliverable)
- `4.png` - **`run-cli-test.sh` output: DENY tests and summary** (deliverable)
- `5.png` - EC2 console -> instance -> **Security** tab showing the IAM role

## Troubleshooting
- `Instance is not Online in SSM`: wait 2-3 minutes after apply; the instance needs outbound internet (IGW route) and `AmazonSSMManagedInstanceCore`.
- `Unable to locate credentials` on the instance: the instance profile is missing or IMDS is disabled - check step 3.
- Allowed test returns `AccessDenied` right after apply: IAM changes are eventually consistent; rerun after ~30 seconds.
- `BucketAlreadyExists`: bucket names are global; change `project_name` in `variables.tf`.
- `base64: invalid option -- 'w'`: run `run-cli-test.sh` on Linux (GNU coreutils), not macOS.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project23-iam-role-ec2-s3/terraform
terraform destroy
```
Both buckets have `force_destroy = true`, so test uploads are removed too.

## Verification
- The instance has the IAM role attached through an instance profile and requires IMDSv2.
- No access keys exist on the instance; `aws configure list` shows `iam-role` and `get-caller-identity` shows the assumed role.
- The role can list the app bucket and read/write `app-data/`, and is denied everything else (14/14 tests pass).

## Deliverables
- CLI test output: `cli-test-output.txt` plus screenshots `3.png` and `4.png` (supporting screenshots `1.png`, `2.png`, `5.png`)
