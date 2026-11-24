output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "https_url" {
  description = "Secure URL of the app"
  value       = "https://${local.app_host}"
}

output "http_url" {
  description = "Plain HTTP URL (should be blocked or redirected)"
  value       = "http://${local.app_host}"
}

output "certificate_mode" {
  description = "Which kind of ACM certificate is attached to the HTTPS listener"
  value       = local.certificate_mode
}

output "certificate_arn" {
  description = "ARN of the ACM certificate used by the HTTPS listener"
  value       = local.certificate_arn
}

output "http_mode" {
  description = "How plain HTTP is handled"
  value       = var.http_mode
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer (used to list its listeners)"
  value       = aws_lb.app.arn
}

output "instance_id" {
  description = "Web server instance ID"
  value       = aws_instance.web.id
}

output "acm_console_url" {
  description = "ACM console view of the certificate"
  value       = "https://${var.aws_region}.console.aws.amazon.com/acm/home?region=${var.aws_region}#/certificates/${element(split("/", local.certificate_arn), 1)}"
}
