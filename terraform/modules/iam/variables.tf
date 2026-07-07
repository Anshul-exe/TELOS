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

variable "cluster_name" {
  description = "EKS cluster name the bastion role may eks:DescribeCluster (scopes the inline policy to that cluster's ARN). Empty string disables the bastion EKS policy."
  type        = string
  default     = ""
}

variable "enable_oidc_provider" {
  description = "Whether to create the IAM OIDC provider for IRSA. Kept as a STATIC toggle (not derived from cluster_oidc_issuer_url) so `count` is known at plan time even when the issuer URL is only known after the cluster is created. Set true once the eks module is wired in."
  type        = bool
  default     = false
}

variable "tf_state_bucket_arn" {
  description = "ARN of the S3 bucket holding Terraform remote state. Grants the bastion role GetObject/PutObject (on <arn>/*) and ListBucket (on <arn>). Empty string disables the backend policy."
  type        = string
  default     = "arn:aws:s3:::telos-tfstate-23c1b86e"
}

variable "tf_lock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking. Grants the bastion role GetItem/PutItem/DeleteItem/DescribeTable. Empty string disables the backend policy."
  type        = string
  default     = "arn:aws:dynamodb:ap-south-1:632377784699:table/telos-tf-locks"
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
