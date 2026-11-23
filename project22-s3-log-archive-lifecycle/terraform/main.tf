data "aws_caller_identity" "current" {}

locals {
  # Account ID keeps the bucket name globally unique
  bucket_name = "${var.project_name}-log-archive-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# Log archive bucket: private, encrypted, versioned
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  bucket = local.bucket_name

  # Lets `terraform destroy` remove the bucket even though it holds logs
  force_destroy = true

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle rules - the cost-saving part of the project
#
#   logs/   STANDARD --30d--> STANDARD_IA --90d--> GLACIER_IR --180d--> DEEP_ARCHIVE --365d--> deleted
#   debug/  STANDARD --7d--> deleted
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  # S3 default: objects smaller than 128 KB are never transitioned, because the
  # per-object transition fee and minimum billable size would cost more than it saves.
  transition_default_minimum_object_size = "all_storage_classes_128K"

  rule {
    id     = "archive-and-expire-app-logs"
    status = "Enabled"

    filter {
      prefix = "${var.archive_prefix}/"
    }

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_ir_days
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = var.transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-debug-logs"
    status = "Enabled"

    filter {
      prefix = "${var.debug_prefix}/"
    }

    expiration {
      days = var.debug_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

# Reject any non-TLS access to the logs
data "aws_iam_policy_document" "logs_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}
