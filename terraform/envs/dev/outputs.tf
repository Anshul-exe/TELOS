# Network
output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

# Cluster
output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (private)."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  description = "Base64 cluster CA data (for kubeconfig)."
  value       = module.eks.cluster_ca_data
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA (null if disabled)."
  value       = module.iam.oidc_provider_arn
}

output "node_group_names" {
  description = "Managed node group names."
  value       = module.node_groups.node_group_names
}

# ECR
output "ecr_repository_urls" {
  description = "ECR repository URLs, keyed by repo name."
  value       = module.ecr.repository_urls
}

# ALB Controller (IRSA) — annotate the aws-load-balancer-controller service
# account with this ARN during the helm install on the bastion.
output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller service account."
  value       = module.alb_controller.role_arn
}

# Bastion
output "bastion_public_ip" {
  description = "Public IP of the bastion (SSH from operator_ip_cidr)."
  value       = module.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID."
  value       = module.bastion.instance_id
}
