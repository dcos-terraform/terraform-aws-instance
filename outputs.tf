output "instances" {
  description = "List of instance IDs"
  value       = aws_instance.instance[*].id
}

output "public_ips" {
  description = "List of public ip addresses created by this module"
  value       = aws_instance.instance[*].public_ip
}

output "private_ips" {
  description = "List of private ip addresses created by this module"
  value       = aws_instance.instance[*].private_ip
}

output "os_user" {
  description = "The OS user to be used"
  value       = module.dcos-tested-oses.user
}

output "password_data" {
  description = "Return a list of encrypted password data for Windows instances"
  value       = aws_instance.instance[*].password_data
}

