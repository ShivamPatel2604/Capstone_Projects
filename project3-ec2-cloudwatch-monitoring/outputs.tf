
output "ec2_instance_id" {
  value = aws_instance.monitoring_ec2.id
}

output "ec2_public_ip" {
  value = aws_instance.monitoring_ec2.public_ip
}

output "cloudwatch_alarm_name" {
  value = aws_cloudwatch_metric_alarm.cpu_alarm.alarm_name
}

output "aws_region" {
  value = var.aws_region
}

