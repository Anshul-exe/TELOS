variable "role_name" {
  description = "Name of the IRSA IAM role and policy for the AWS Load Balancer Controller."
  type        = string
  default     = "telos-alb-controller"
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from the iam module's oidc_provider_arn output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (issuer), with or without the https:// prefix. Used to build the IRSA trust condition keys."
  type        = string
}

variable "service_account_namespace" {
  description = "Namespace of the controller's service account (the Helm chart default is kube-system)."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the controller's service account (the Helm chart default is aws-load-balancer-controller)."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "tags" {
  description = "Additional tags merged onto the IAM resources."
  type        = map(string)
  default     = {}
}
