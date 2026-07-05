variable "cluster_name" {
  description = "Name of the EKS cluster to grant access on."
  type        = string
}

variable "principal_arn" {
  description = "IAM principal (role/user) ARN to grant cluster access via an EKS access entry."
  type        = string
}

# Read-only by design: AmazonEKSAdminViewPolicy grants get/list/watch on ALL
# resources (including cluster-scoped `nodes` and `pods/log`), which covers the
# bastion's validation needs (get/describe/logs) without any write access.
#   * For deploying manifests from the bastion (kubectl apply), flip this to
#     arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy.
#   * Do NOT use AmazonEKSAdminPolicy for validation — its RBAC omits `nodes`,
#     so `kubectl get nodes` would return Forbidden.
variable "access_policy_arn" {
  description = "EKS access policy ARN to associate with the principal."
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
}

variable "access_scope_type" {
  description = "Access scope for the policy association: 'cluster' (all namespaces + cluster-scoped resources) or 'namespace'."
  type        = string
  default     = "cluster"

  validation {
    condition     = contains(["cluster", "namespace"], var.access_scope_type)
    error_message = "access_scope_type must be 'cluster' or 'namespace'."
  }
}

variable "kubernetes_groups" {
  description = "Optional Kubernetes groups to bind the principal to. Empty by default since access is granted via the policy association."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto the access entry."
  type        = map(string)
  default     = {}
}
