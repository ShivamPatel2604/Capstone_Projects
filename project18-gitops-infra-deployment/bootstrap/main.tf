data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  github_oidc_url = "token.actions.githubusercontent.com"

  # GitHub sends either the legacy (owner/repo) or immutable (owner@id/repo@id) subject
  github_sub_repos = compact([var.github_repository, var.github_repository_immutable])

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${local.account_id}:oidc-provider/${local.github_oidc_url}"

  state_object_arn = "${aws_s3_bucket.tf_state.arn}/${var.state_key}"
  state_lock_arn   = "${aws_s3_bucket.tf_state.arn}/${var.state_key}.tflock"

  # Resources the GitOps pipeline is allowed to manage
  managed_bucket_arns = [
    "arn:aws:s3:::${var.name_prefix}-app-*",
    "arn:aws:s3:::${var.name_prefix}-app-*/*",
  ]
  managed_parameter_arn = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/${var.name_prefix}/*"
}

# ---------------------------------------------------------------------------
# Remote state bucket (S3 native locking via use_lockfile, no DynamoDB needed)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.name_prefix}-tfstate-${local.account_id}"

  # Capstone lab: allow `terraform destroy` to remove the versioned bucket during cleanup
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tf_state_tls_only" {
  bucket = aws_s3_bucket.tf_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tf_state.arn, "${aws_s3_bucket.tf_state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.tf_state]
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider (no long-lived AWS keys stored in GitHub)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Plan role: assumable from PRs and from pushes to main. Read-only on infra.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values = flatten([
        for r in local.github_sub_repos : [
          "repo:${r}:pull_request",
          "repo:${r}:ref:refs/heads/main",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-gha-plan"
  description          = "GitHub Actions - terraform plan for Project 18"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tf_state.arn]
  }

  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = [local.state_object_arn]
  }

  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_lock_arn]
  }

  statement {
    sid       = "ReadManagedBuckets"
    actions   = ["s3:Get*", "s3:List*"]
    resources = local.managed_bucket_arns
  }

  statement {
    sid       = "ReadManagedParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"]
    resources = [local.managed_parameter_arn]
  }

  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# ---------------------------------------------------------------------------
# Apply role: ONLY assumable by jobs running in the approved GitHub environment
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = [for r in local.github_sub_repos : "repo:${r}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${var.name_prefix}-gha-apply"
  description          = "GitHub Actions - terraform apply for Project 18 (environment-gated)"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tf_state.arn]
  }

  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.state_object_arn]
  }

  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_lock_arn]
  }

  statement {
    sid       = "ManageProjectBuckets"
    actions   = ["s3:*"]
    resources = local.managed_bucket_arns
  }

  statement {
    sid = "ManageProjectParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [local.managed_parameter_arn]
  }

  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
