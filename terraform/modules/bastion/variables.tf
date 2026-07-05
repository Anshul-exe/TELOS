variable "name" {
  description = "Name tag for the bastion instance and related resources."
  type        = string
  default     = "telos-bastion"
}

variable "vpc_id" {
  description = "VPC ID the bastion security group is created in."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID to launch the bastion in."
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the SSM instance profile (from the iam module)."
  type        = string
}

variable "operator_ip_cidr" {
  description = "CIDR allowed to SSH to the bastion (e.g. \"203.0.113.4/32\"). No default — must be passed explicitly; do not open SSH to the world."
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_ip_cidr, 0))
    error_message = "operator_ip_cidr must be a valid CIDR, e.g. 203.0.113.4/32."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the bastion."
  type        = string
  default     = "t3.micro"
}

variable "region" {
  description = "AWS region, passed into user_data for aws eks update-kubeconfig."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name to wire kubeconfig to at first boot. Empty string skips all kubectl/kubeconfig bootstrap in user_data."
  type        = string
  default     = ""
}

variable "kubectl_minor_version" {
  description = "Kubernetes minor version channel for kubectl (resolves the latest patch via https://dl.k8s.io/release/stable-<minor>.txt). Should match the cluster version."
  type        = string
  default     = "1.34"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH. Leave null to rely on SSM Session Manager only."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
