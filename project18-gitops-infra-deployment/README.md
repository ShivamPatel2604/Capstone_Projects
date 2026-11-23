# Project 18: GitOps Infra Deployment

## Objective
Trigger infrastructure updates from **pull request merges**. Git is the single source of truth:
changes to Terraform are proposed in a PR, reviewed with an automatic `terraform plan`, and applied
by GitHub Actions only after the PR is merged **and** a reviewer approves the `production` deployment.

## Tasks
| Task | How it is implemented |
| --- | --- |
| Configure apply job | `apply` job in `.github/workflows/project18-gitops-infra.yml` runs on push to `main` (PR merge), downloads the exact reviewed `tfplan` and runs `terraform apply tfplan` |
| Add approvals | GitHub **environment `production`** with *required reviewers* + branch policy `main`. The AWS apply role trusts **only** the OIDC subject `repo:ShivamPatel2604/Capstone_Projects:environment:production`, so nothing can apply without an approved deployment |

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI + `gh`)
- CI: GitHub Actions, Terraform 1.17.2, AWS auth via **OIDC** (no AWS keys stored in GitHub)
- State: S3 remote backend with native S3 locking (`use_lockfile = true`, no DynamoDB)
- Region: ap-south-1 (Mumbai)

## Architecture
```
 Developer                 GitHub                                   AWS (ap-south-1)
 ---------                 ------                                   ----------------
 edit infra.auto.tfvars
 git push branch  ---->  Pull Request
                           |  plan job (OIDC -> shivam-project18-gha-plan, read-only)
                           |    fmt / init / validate / plan  ----->  reads S3 state + resources
                           |    plan posted as PR comment
                           v
                         Merge to main
                           |  plan job  -> tfplan artifact
                           v
                         apply job  (environment: production)
                           |  WAITING for required reviewer approval
                           |  Approve
                           v
                         OIDC -> shivam-project18-gha-apply  ----->  terraform apply tfplan
                                                                     S3 artifacts bucket
                                                                     SSM /shivam-project18/production/*
```

## Project Structure
```
.github/workflows/project18-gitops-infra.yml   # PR plan + merge-triggered, approval-gated apply

project18-gitops-infra-deployment/
├── bootstrap/            # Run ONCE from the VM (local state)
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf           # S3 state bucket, GitHub OIDC provider, plan role, apply role
│   └── outputs.tf        # Prints the `gh variable set` commands
├── infra/                # Managed ONLY through GitOps (PR -> merge -> approve)
│   ├── providers.tf      # S3 backend (bucket passed at init) + AWS provider
│   ├── variables.tf
│   ├── main.tf           # S3 artifacts bucket + SSM parameters (app version, feature flags)
│   ├── outputs.tf
│   └── infra.auto.tfvars # Desired state - edit this in a PR to trigger a deployment
└── screenshots/          # Workflow run screenshots (deliverable)
```

## Security design
| Control | Detail |
| --- | --- |
| No static credentials | GitHub OIDC -> `sts:AssumeRoleWithWebIdentity`, 1 hour sessions |
| Separate roles | **plan** role (read-only + state lock) for PRs/main, **apply** role (write) only for the `production` environment |
| Least privilege | Apply role can only manage `shivam-project18-app-*` buckets and `/shivam-project18/*` SSM parameters |
| Reviewed plan is applied | The `tfplan` produced by the plan job is uploaded and applied as-is; Terraform rejects it if state changed meanwhile |
| Serialised runs | `concurrency` group, `cancel-in-progress: false` - an apply is never cancelled mid-way |
| State protection | Versioned, encrypted, public-access-blocked bucket with a TLS-only bucket policy |

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
gh auth status
```

### 2. Bootstrap the state bucket, OIDC provider and IAM roles (one time)
```bash
cd ~/aws-terraform-capstone/project18-gitops-infra-deployment/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```
> If the account already has the GitHub OIDC provider (`token.actions.githubusercontent.com`),
> use `terraform plan -var="create_oidc_provider=false" -out=tfplan` instead.

### 3. Store the bootstrap outputs as GitHub repository variables
```bash
terraform output -raw gh_variable_commands | bash
gh variable list --repo ShivamPatel2604/Capstone_Projects
```

### 4. Create the `production` environment with required reviewers (approval gate)
```bash
REPO=ShivamPatel2604/Capstone_Projects
MY_ID=$(gh api user --jq .id)

gh api -X PUT repos/$REPO/environments/production --input - <<EOF
{
  "reviewers": [{ "type": "User", "id": $MY_ID }],
  "prevent_self_review": false,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
EOF

gh api -X POST repos/$REPO/environments/production/deployment-branch-policies \
  -f name=main -f type=branch
```
UI alternative: **Settings -> Environments -> New environment `production`** -> tick *Required reviewers*,
add yourself -> *Deployment branches and tags*: selected branches -> `main`.

### 5. First GitOps deployment
```bash
cd ~/aws-terraform-capstone
git checkout -b project18-initial-deploy
# any change under project18-gitops-infra-deployment/infra/ triggers the pipeline
git commit --allow-empty -m "Project 18: initial GitOps deploy"   # or edit infra.auto.tfvars
git push -u origin project18-initial-deploy
gh pr create --fill --base main
```
1. The **Terraform Plan** job runs and comments the plan on the PR.
2. Merge the PR -> the workflow runs on `main`: plan, then **Terraform Apply** shows *Waiting*.
3. Open the run -> **Review deployments** -> tick `production` -> **Approve and deploy**.
4. Apply finishes; outputs are written to the job summary.

> An empty commit does not match the `paths` filter. For the very first run either edit
> `infra.auto.tfvars` or start it from **Actions -> Project 18 - GitOps Infra Deployment -> Run workflow** on `main`.

### 6. Demonstrate an infra update from a PR merge
```bash
git checkout main && git pull
git checkout -b project18-bump-version
sed -i 's/app_version             = "1.0.0"/app_version             = "1.1.0"/' \
  project18-gitops-infra-deployment/infra/infra.auto.tfvars
sed -i 's/new_checkout = false/new_checkout = true/' \
  project18-gitops-infra-deployment/infra/infra.auto.tfvars
git commit -am "Project 18: release 1.1.0 and enable new_checkout"
git push -u origin project18-bump-version
gh pr create --fill --base main
```
Plan on the PR shows `~ update in-place` for the two SSM parameters. Merge, approve, and verify:
```bash
aws ssm get-parameter --name /shivam-project18/production/app_version   --query Parameter.Value --output text
aws ssm get-parameter --name /shivam-project18/production/feature_flags --query Parameter.Value --output text
gh run list --workflow project18-gitops-infra.yml --limit 5
```

## Deliverables - Workflow run screenshots
Save under `screenshots/`:
1. `01-pr-plan-comment.png` - Terraform plan comment on the PR
2. `02-apply-waiting-approval.png` - Run graph with **Terraform Apply** waiting for review
3. `03-review-deployments.png` - *Review deployments* dialog approving `production`
4. `04-apply-success.png` - Successful run (plan + apply green) with the apply summary
5. `05-ssm-parameters.png` - AWS console / CLI showing the updated SSM values

## Cleanup
```bash
# 1. Destroy GitOps-managed infra (using your VM admin credentials)
cd ~/aws-terraform-capstone/project18-gitops-infra-deployment/infra
BUCKET=$(cd ../bootstrap && terraform output -raw tf_state_bucket)
terraform init -backend-config="bucket=$BUCKET"
terraform destroy

# 2. Destroy the bootstrap (state bucket, OIDC provider, roles)
cd ../bootstrap
terraform destroy

# 3. Remove GitHub configuration
REPO=ShivamPatel2604/Capstone_Projects
gh variable delete TF_STATE_BUCKET    --repo $REPO
gh variable delete AWS_PLAN_ROLE_ARN  --repo $REPO
gh variable delete AWS_APPLY_ROLE_ARN --repo $REPO
gh api -X DELETE repos/$REPO/environments/production
```
> Run cleanup only after the screenshots are captured. While the variables exist, every merge that
> touches `infra/` will request an approval before deploying.

## Technologies Used
- GitHub Actions (environments, required reviewers, OIDC, artifacts, github-script)
- Terraform (S3 backend with native locking, saved plans)
- AWS IAM (OIDC identity provider, scoped roles), Amazon S3, AWS Systems Manager Parameter Store
