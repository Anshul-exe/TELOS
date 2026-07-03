variable "region" {
  description = "AWS region. The provider region is configured by the root module; accepted here for interface completeness."
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Existing infra uses 192.168.0.0/16."
  type        = string
  default     = "192.168.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread public/private subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6."
  }
}

variable "name_prefix" {
  description = "Prefix applied to resource Name tags."
  type        = string
  default     = "telos"
}

variable "cluster_name" {
  description = "EKS cluster name. When set, subnets get the kubernetes.io/cluster/<name>=shared tag required for EKS/ALB subnet auto-discovery. Leave empty to skip."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
