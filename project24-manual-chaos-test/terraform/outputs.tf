output "instance_id" {
  description = "EC2 instance running the service under test"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "app_url" {
  description = "Application page"
  value       = "http://${aws_instance.web.public_ip}/"
}

output "health_url" {
  description = "Health endpoint polled by scripts/monitor.sh"
  value       = "http://${aws_instance.web.public_ip}/health"
}

output "service_name" {
  description = "systemd unit under test"
  value       = "httpd"
}

output "aws_region" {
  description = "Region of the deployment"
  value       = var.aws_region
}

output "ssm_session_command" {
  description = "Open a shell on the instance (requires the Session Manager plugin)"
  value       = "aws ssm start-session --target ${aws_instance.web.id} --region ${var.aws_region}"
}

output "instance_console_url" {
  description = "EC2 console page for the instance"
  value       = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#InstanceDetails:instanceId=${aws_instance.web.id}"
}
