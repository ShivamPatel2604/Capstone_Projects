output "tf_state_bucket" {
  description = "Value for the TF_STATE_BUCKET repository variable"
  value       = aws_s3_bucket.tf_state.bucket
}

output "plan_role_arn" {
  description = "Value for the AWS_PLAN_ROLE_ARN repository variable"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Value for the AWS_APPLY_ROLE_ARN repository variable"
  value       = aws_iam_role.apply.arn
}

output "gh_variable_commands" {
  description = "Run these on the VM to configure the GitHub repository variables"
  value       = <<-EOT
    gh variable set TF_STATE_BUCKET    --repo ${var.github_repository} --body "${aws_s3_bucket.tf_state.bucket}"
    gh variable set AWS_PLAN_ROLE_ARN  --repo ${var.github_repository} --body "${aws_iam_role.plan.arn}"
    gh variable set AWS_APPLY_ROLE_ARN --repo ${var.github_repository} --body "${aws_iam_role.apply.arn}"
  EOT
}
