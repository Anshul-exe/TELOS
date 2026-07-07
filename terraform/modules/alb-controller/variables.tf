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

# ---------------------------------------------------------------------------
# Helm install inputs. cluster_name/cluster_endpoint/cluster_ca_data/vpc_id are
# required (no defaults) so the wiring is explicit at the module call; the first
# three are known-only-after-apply module.eks outputs, vpc_id is a module.vpc
# output. cluster_endpoint/cluster_ca_data feed the exec-auth provider blocks.
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "EKS cluster name. Set as the chart's clusterName value and used by the exec-auth plugin (aws eks get-token)."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint (module.eks.cluster_endpoint). Used by the helm/kubernetes provider connection."
  type        = string
}

variable "cluster_ca_data" {
  description = "Base64-encoded cluster CA data (module.eks.cluster_ca_data). Decoded for the helm/kubernetes provider TLS trust."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the cluster runs in (module.vpc.vpc_id). Set as the chart's vpcId value."
  type        = string
}

variable "region" {
  description = "AWS region for the controller (chart `region` value) and the exec-auth get-token call."
  type        = string
  default     = "ap-south-1"
}

variable "eks_access_policy_arn" {
  description = "ARN of the EKS access policy association granting the applying identity (the bastion) ClusterAdmin. Consumed only as a graph-ordering gate (terraform_data.eks_access_gate) so the Helm release waits for cluster write access WITHOUT a module-level depends_on, which a module with provider blocks cannot use. Empty string disables the gate."
  type        = string
  default     = ""
}
