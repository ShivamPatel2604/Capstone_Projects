# Generate unique bucket suffix

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create S3 bucket

resource "aws_s3_bucket" "website" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
}

# Enable static website hosting

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
}

# Configure public access

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

# Configure public read policy

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [
    aws_s3_bucket_public_access_block.website
  ]

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# Upload HTML file

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/../website/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../website/index.html")
}

# Upload CSS file

resource "aws_s3_object" "stylesheet" {
  bucket       = aws_s3_bucket.website.id
  key          = "style.css"
  source       = "${path.module}/../website/style.css"
  content_type = "text/css"
  etag         = filemd5("${path.module}/../website/style.css")
}
