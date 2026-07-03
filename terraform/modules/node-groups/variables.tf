variable "cluster_name" {
  description = "Name of the EKS cluster these node groups join."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the shared worker node IAM role (from the iam module)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the general node group."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the db-api node group."
  type        = list(string)
}

variable "instance_types" {
  description = "Instance types for both node groups."
  type        = list(string)
  default     = ["t3.small"]
}

variable "scaling" {
  description = "Autoscaling sizes applied to both node groups."
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 2
    max_size     = 4
    desired_size = 2
  }
}

# Capacity type per group. Defaults to SPOT for cost; flip either to ON_DEMAND
# if spot capacity for t3.small is unavailable in ap-south-1 during testing.
variable "general_capacity_type" {
  description = "Capacity type for the general node group (SPOT or ON_DEMAND)."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.general_capacity_type)
    error_message = "general_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "db_api_capacity_type" {
  description = "Capacity type for the db-api node group (SPOT or ON_DEMAND)."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.db_api_capacity_type)
    error_message = "db_api_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "general_node_group_name" {
  description = "Name of the general node group."
  type        = string
  default     = "telos-general-ng"
}

variable "db_api_node_group_name" {
  description = "Name of the db-api node group."
  type        = string
  default     = "telos-db-api-ng"
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
