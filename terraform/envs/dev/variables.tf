variable "region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, used as a prefix/tag across resources."
  type        = string
  default     = "telos"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name. Shared between the vpc (subnet discovery tags), eks, and node-groups modules."
  type        = string
  default     = "telos-cluster"
}

variable "operator_ip_cidr" {
  description = "CIDR allowed to SSH to the bastion (your public IP as /32). No default — set it in terraform.tfvars. Passed through to modules/bastion."
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_ip_cidr, 0))
    error_message = "operator_ip_cidr must be a valid CIDR, e.g. 49.36.138.18/32."
  }
}
