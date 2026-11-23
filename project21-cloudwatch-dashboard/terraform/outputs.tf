output "alb_url" {
  description = "Public URL of the monitored app"
  value       = "http://${aws_lb.app.dns_name}"
}

output "instance_ids" {
  description = "Instance IDs of the monitored web servers"
  value       = aws_instance.web[*].id
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "Console URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_names" {
  description = "CloudWatch alarms shown on the dashboard"
  value = concat(
    aws_cloudwatch_metric_alarm.high_cpu[*].alarm_name,
    aws_cloudwatch_metric_alarm.high_memory[*].alarm_name,
    [
      aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
      aws_cloudwatch_metric_alarm.high_latency.alarm_name,
      aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
    ]
  )
}
