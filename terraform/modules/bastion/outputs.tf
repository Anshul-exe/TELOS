output "instance_id" {
  description = "ID of the bastion EC2 instance."
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Public IP address of the bastion."
  value       = aws_instance.bastion.public_ip
}

output "security_group_id" {
  description = "ID of the bastion security group."
  value       = aws_security_group.bastion.id
}
