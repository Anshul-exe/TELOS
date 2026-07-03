output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public (ELB-tagged) subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private (internal-ELB-tagged) subnets."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs the subnets are spread across."
  value       = local.azs
}

output "nat_gateway_id" {
  description = "ID of the single NAT Gateway."
  value       = aws_nat_gateway.this.id
}
