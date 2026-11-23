output "artifacts_bucket" {
  description = "Application artifacts bucket"
  value       = aws_s3_bucket.artifacts.bucket
}

output "app_version_parameter" {
  description = "SSM parameter holding the deployed app version"
  value       = aws_ssm_parameter.app_version.name
}

output "feature_flags_parameter" {
  description = "SSM parameter holding the feature flags"
  value       = aws_ssm_parameter.feature_flags.name
}

output "deployed_app_version" {
  description = "App version currently deployed"
  value       = aws_ssm_parameter.app_version.insecure_value
}
