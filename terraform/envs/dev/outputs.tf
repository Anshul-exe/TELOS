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

# SQS
output "sqs_queue_url" {
  description = "URL of the telos-task-events SQS queue."
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN of the telos-task-events SQS queue."
  value       = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  description = "URL of the telos-task-events dead-letter queue."
  value       = module.sqs.dlq_url
}

output "sqs_dlq_arn" {
  description = "ARN of the telos-task-events dead-letter queue."
  value       = module.sqs.dlq_arn
}

# IRSA — Phase 2 (async microservices)
output "task_service_irsa_role_arn" {
  description = "IRSA role ARN for task-service (annotate the K8s SA with eks.amazonaws.com/role-arn)."
  value       = module.iam.task_service_irsa_role_arn
}

output "notification_service_irsa_role_arn" {
  description = "IRSA role ARN for notification-service (annotate the K8s SA with eks.amazonaws.com/role-arn)."
  value       = module.iam.notification_service_irsa_role_arn
}

output "jenkins_irsa_role_arn" {
  description = "IRSA role ARN for Jenkins (annotate the K8s SA with eks.amazonaws.com/role-arn)."
  value       = module.iam.jenkins_irsa_role_arn
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
