output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "alb_url" {
  description = "Public URL of the load-balanced app"
  value       = "http://${aws_lb.app.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group (used to check target health)"
  value       = aws_lb_target_group.web.arn
}

output "instance_ids" {
  description = "Instance IDs of the web servers behind the ALB"
  value       = aws_instance.web[*].id
}

output "instances" {
  description = "Web servers with their Availability Zone and private IP"
  value = {
    for i in aws_instance.web : i.tags["Name"] => {
      id         = i.id
      az         = i.availability_zone
      private_ip = i.private_ip
    }
  }
}

output "target_group_console_url" {
  description = "EC2 console view of the target group and its health checks"
  value       = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#TargetGroup:targetGroupArn=${aws_lb_target_group.web.arn}"
}
