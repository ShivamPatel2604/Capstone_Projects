data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # Account ID keeps the bucket name globally unique
  bucket_name = "${var.project_name}-log-backups-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# HTTP only, no SSH. The instance is managed through Systems Manager and
# uploads backups to S3 over outbound HTTPS.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP only - no SSH, management via SSM"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound for SSM, S3 and package repos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# ---------------------------------------------------------------------------
# S3 backup bucket: private, encrypted, versioned, auto-expiring
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "backup" {
  bucket = local.bucket_name

  # Lets `terraform destroy` remove the bucket even though it holds backups
  force_destroy = true

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-log-backups"
    status = "Enabled"

    filter {
      prefix = "${var.backup_prefix}/"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.backup]
}

# Reject any non-TLS access to the backups
data "aws_iam_policy_document" "backup_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*",
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

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = data.aws_iam_policy_document.backup_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.backup]
}

# ---------------------------------------------------------------------------
# IAM: SSM management + least-privilege upload to the backup prefix
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${var.project_name}-web-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "backup_upload" {
  statement {
    sid       = "UploadLogBackups"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.backup.arn}/${var.backup_prefix}/*"]
  }

  statement {
    sid       = "ListLogBackups"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backup.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.backup_prefix}/*"]
    }
  }
}

resource "aws_iam_role_policy" "backup_upload" {
  name   = "${var.project_name}-backup-upload"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.backup_upload.json
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-profile"
  role = aws_iam_role.web.name
}

# ---------------------------------------------------------------------------
# Web server whose logs are backed up. user_data installs the backup script
# and cron daemon; the cron job itself is created via SSM (see README).
# ---------------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    bucket_name   = aws_s3_bucket.backup.bucket
    backup_prefix = var.backup_prefix
    aws_region    = var.aws_region
  })

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-web"
    Role = "backup-source"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy.backup_upload,
  ]
}
