output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded cluster certificate authority data (for kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = aws_eks_cluster.this.version
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Feed into the iam module to create the OIDC provider for IRSA."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "ID of the additional control-plane security group created by this module."
  value       = aws_security_group.cluster.id
}

output "cluster_managed_security_group_id" {
  description = "ID of the EKS-managed cluster security group (node<->control-plane traffic)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
