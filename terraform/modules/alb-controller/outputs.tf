output "role_arn" {
  description = "ARN of the IRSA role. Annotate the aws-load-balancer-controller service account with this (eks.amazonaws.com/role-arn) via the Helm install."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role."
  value       = aws_iam_role.this.name
}

output "policy_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM policy."
  value       = aws_iam_policy.this.arn
}

output "service_account_name" {
  description = "Service account name the Helm chart should create in kube-system."
  value       = var.service_account_name
}

output "service_account_namespace" {
  description = "Namespace for the controller service account."
  value       = var.service_account_namespace
}
