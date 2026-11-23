output "instance_id" {
  description = "Instance ID of the web server (log source)"
  value       = aws_instance.web.id
}

output "web_url" {
  description = "Public URL of the web server"
  value       = "http://${aws_instance.web.public_ip}"
}

output "agent_config_parameter" {
  description = "SSM parameter holding the CloudWatch agent configuration"
  value       = aws_ssm_parameter.agent_config.name
}

output "log_group_names" {
  description = "CloudWatch log groups receiving the forwarded logs"
  value       = { for key, lg in aws_cloudwatch_log_group.this : key => lg.name }
}

output "dashboard_url" {
  description = "CloudWatch log dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.logs.dashboard_name}"
}
