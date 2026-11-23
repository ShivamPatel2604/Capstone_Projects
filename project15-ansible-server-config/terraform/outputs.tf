output "node_instance_ids" {
  description = "Instance IDs Ansible connects to through SSM"
  value       = aws_instance.node[*].id
}

output "ssm_bucket" {
  description = "S3 bucket used by the aws_ssm connection plugin"
  value       = aws_s3_bucket.ansible_ssm.bucket
}

output "web_urls" {
  description = "Public URLs to verify the web servers after running the playbook"
  value       = [for ip in aws_instance.node[*].public_ip : "http://${ip}"]
}
