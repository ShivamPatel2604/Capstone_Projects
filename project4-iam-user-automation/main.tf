resource "aws_iam_user" "s3_user" {
  name = var.iam_username

  tags = {
    Name      = "shivam-terraform-s3-user"
    Project   = "Project-4"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "shivam-s3-read-only-policy"
  description = "Read-only access to S3 resources"
  policy      = var.s3_read_policy
}

resource "aws_iam_user_policy_attachment" "s3_attachment" {
  user       = aws_iam_user.s3_user.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}
