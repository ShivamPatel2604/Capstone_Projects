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
  account_id = data.aws_caller_identity.current.account_id

  # Account ID keeps the bucket names globally unique
  app_bucket_name        = "${var.project_name}-app-data-${local.account_id}"
  restricted_bucket_name = "${var.project_name}-restricted-${local.account_id}"
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

# No inbound rules at all: the instance is reached only through SSM.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "No inbound - management via SSM, outbound HTTPS to AWS APIs"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Outbound for SSM, S3 and package repos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# ---------------------------------------------------------------------------
# S3 buckets
#   app bucket        -> the EC2 role may use <allowed_prefix>/ only
#   restricted bucket -> the EC2 role has no access (proves least privilege)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "app" {
  bucket        = local.app_bucket_name
  force_destroy = true

  tags = {
    Name = local.app_bucket_name
  }
}

resource "aws_s3_bucket" "restricted" {
  bucket        = local.restricted_bucket_name
  force_destroy = true

  tags = {
    Name = local.restricted_bucket_name
  }
}

locals {
  buckets = {
    app        = aws_s3_bucket.app
    restricted = aws_s3_bucket.restricted
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.buckets

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Reject any non-TLS access
data "aws_iam_policy_document" "https_only" {
  for_each = local.buckets

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

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

resource "aws_s3_bucket_policy" "this" {
  for_each = local.buckets

  bucket = each.value.id
  policy = data.aws_iam_policy_document.https_only[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Seed objects so the tests have something to read (and be denied reading)
resource "aws_s3_object" "app_seed" {
  bucket       = aws_s3_bucket.app.id
  key          = "${var.allowed_prefix}/welcome.txt"
  content      = "Hello from ${local.app_bucket_name} - readable by the EC2 IAM role.\n"
  content_type = "text/plain"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.this]
}

resource "aws_s3_object" "app_outside_prefix" {
  bucket       = aws_s3_bucket.app.id
  key          = "admin/config.txt"
  content      = "Admin-only file outside ${var.allowed_prefix}/ - the EC2 role must NOT read this.\n"
  content_type = "text/plain"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.this]
}

resource "aws_s3_object" "restricted_seed" {
  bucket       = aws_s3_bucket.restricted.id
  key          = "secret.txt"
  content      = "Restricted data - the EC2 role has no access to this bucket.\n"
  content_type = "text/plain"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.this]
}

# ---------------------------------------------------------------------------
# IAM role for EC2 (the core of the project)
#   - trusted only by the EC2 service in this account
#   - SSM core for keyless management
#   - least-privilege S3 policy: list the app bucket, read/write <allowed_prefix>/
#     only, no delete, no other bucket
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

resource "aws_iam_role" "ec2_s3" {
  name                 = "${var.project_name}-ec2-s3-role"
  description          = "EC2 role with least-privilege access to ${local.app_bucket_name}/${var.allowed_prefix}/"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid       = "ListAppBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.app.arn]
  }

  statement {
    sid       = "ReadWriteAllowedPrefix"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.app.arn}/${var.allowed_prefix}/*"]
  }
}

resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-s3-app-data-access"
  description = "List ${local.app_bucket_name}, read/write ${var.allowed_prefix}/ only"
  policy      = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_s3.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_s3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-profile"
  role = aws_iam_role.ec2_s3.name
}

# ---------------------------------------------------------------------------
# EC2 instance with the role attached through the instance profile.
# No access keys are stored on the instance - the AWS CLI picks up temporary
# credentials from the instance metadata service (IMDSv2 only).
# ---------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3.name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-app"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm_core,
    aws_iam_role_policy_attachment.s3_access,
  ]
}
