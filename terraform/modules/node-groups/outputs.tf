output "node_group_names" {
  description = "Names of the created managed node groups."
  value = [
    aws_eks_node_group.general.node_group_name,
    aws_eks_node_group.db_api.node_group_name,
  ]
}

output "general_node_group_arn" {
  description = "ARN of the general node group."
  value       = aws_eks_node_group.general.arn
}

output "db_api_node_group_arn" {
  description = "ARN of the db-api node group."
  value       = aws_eks_node_group.db_api.arn
}
