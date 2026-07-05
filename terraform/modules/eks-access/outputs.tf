output "access_entry_arn" {
  description = "ARN of the created EKS access entry."
  value       = aws_eks_access_entry.this.access_entry_arn
}

output "principal_arn" {
  description = "IAM principal ARN granted cluster access."
  value       = aws_eks_access_entry.this.principal_arn
}

output "access_policy_arn" {
  description = "EKS access policy associated with the principal."
  value       = aws_eks_access_policy_association.this.policy_arn
}
