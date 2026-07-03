output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role."
  value       = aws_iam_role.cluster.arn
  # Ensure the AmazonEKSClusterPolicy attachment exists before the cluster is
  # created by any consumer of this ARN.
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

output "node_role_arn" {
  description = "ARN of the shared worker node IAM role (referenced by managed node groups)."
  value       = aws_iam_role.node.arn
  # Node groups must not launch until all node policies are attached.
  depends_on = [aws_iam_role_policy_attachment.node]
}

output "bastion_role_arn" {
  description = "ARN of the bastion IAM role."
  value       = aws_iam_role.bastion.arn
}

output "bastion_instance_profile_name" {
  description = "Name of the bastion instance profile (attach to the bastion EC2 instance)."
  value       = aws_iam_instance_profile.bastion.name
  # SSM policy attached before the profile is consumed by the bastion instance.
  depends_on = [aws_iam_role_policy_attachment.bastion_ssm]
}

output "bastion_instance_profile_arn" {
  description = "ARN of the bastion instance profile."
  value       = aws_iam_instance_profile.bastion.arn
}

output "oidc_provider_arn" {
  description = "ARN of the EKS IAM OIDC provider (null until cluster_oidc_issuer_url is provided). Used as the Federated principal for IRSA roles."
  value       = one(aws_iam_openid_connect_provider.this[*].arn)
}

output "oidc_provider_url" {
  description = "The OIDC provider URL (host/path form, null until created)."
  value       = one(aws_iam_openid_connect_provider.this[*].url)
}
