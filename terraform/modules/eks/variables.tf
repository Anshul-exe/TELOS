variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "telos-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version."
  type        = string
  default     = "1.34"
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role (from the iam module)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the control plane ENIs. Pass both public and private subnets (spread across AZs)."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID the cluster security group is created in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR allowed to reach the private API endpoint on 443 (e.g. from the bastion)."
  type        = string
  default     = "192.168.0.0/16"
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint access."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint access. Disabled to match baseArch.md (bastion-only admin)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint. Only relevant when endpoint_public_access = true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to ship to CloudWatch. Empty by default to avoid cost; enable (e.g. [\"api\",\"audit\"]) when needed."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
