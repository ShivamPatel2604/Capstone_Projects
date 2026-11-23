output "node_public_ips" {
  description = "Public IPs of the managed web server nodes"
  value       = aws_instance.node[*].public_ip
}

output "web_urls" {
  description = "URLs to verify the web server after running the playbook"
  value       = [for ip in aws_instance.node[*].public_ip : "http://${ip}"]
}

output "controller_cidr" {
  description = "CIDR allowed to SSH to the nodes"
  value       = local.controller_cidr
}

output "inventory_file" {
  description = "Generated Ansible inventory path"
  value       = abspath(local_file.inventory.filename)
}
