data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Application artifacts bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-app-artifacts-${data.aws_caller_identity.current.account_id}"

  # Capstone lab: allow `terraform destroy` to remove the versioned bucket during cleanup
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.artifact_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

# ---------------------------------------------------------------------------
# Application configuration in SSM Parameter Store
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "app_version" {
  name        = "/${var.name_prefix}/${var.environment}/app_version"
  description = "Deployed application version (managed by GitOps)"
  type        = "String"
  value       = var.app_version
}

resource "aws_ssm_parameter" "feature_flags" {
  name        = "/${var.name_prefix}/${var.environment}/feature_flags"
  description = "Application feature flags (managed by GitOps)"
  type        = "String"
  value       = jsonencode(var.feature_flags)
}
