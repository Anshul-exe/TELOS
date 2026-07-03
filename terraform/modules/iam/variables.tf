variable "name_prefix" {
  description = "Prefix applied to IAM role/profile names."
  type        = string
  default     = "telos"
}

variable "cluster_oidc_issuer_url" {
  description = "The EKS cluster's OIDC issuer URL (from the eks module output). Required when enable_oidc_provider = true. Its value may be known-only-after-apply on the first run, which is fine — it does not gate any count/for_each."
  type        = string
  default     = ""
}

variable "enable_oidc_provider" {
  description = "Whether to create the IAM OIDC provider for IRSA. Kept as a STATIC toggle (not derived from cluster_oidc_issuer_url) so `count` is known at plan time even when the issuer URL is only known after the cluster is created. Set true once the eks module is wired in."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
