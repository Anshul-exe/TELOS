# ---------------------------------------------------------------------------
# Node groups module — two managed node groups per baseArch.md:
#   1. telos-general-ng : public subnets, no taints (frontend + general workloads)
#   2. telos-db-api-ng  : private subnets, labeled workload=db-api and tainted
#                   dedicated=db-api:NoSchedule (backend + mongodb pinned here)
# SPOT by default for cost; flip to ON_DEMAND per group via variables.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  base_tags = merge(var.tags, {
    Module = "node-groups"
  })
}

# General node group — public subnets, general scheduling.
resource "aws_eks_node_group" "general" {
  cluster_name    = var.cluster_name
  node_group_name = var.general_node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.public_subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.general_capacity_type

  scaling_config {
    min_size     = var.scaling.min_size
    max_size     = var.scaling.max_size
    desired_size = var.scaling.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.base_tags, { Name = var.general_node_group_name })

  # desired_size drifts as the cluster autoscaler / HPA-driven scaling acts;
  # don't let Terraform fight it on subsequent applies.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# db-api node group — private subnets, dedicated to backend + database pods.
resource "aws_eks_node_group" "db_api" {
  cluster_name    = var.cluster_name
  node_group_name = var.db_api_node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.db_api_capacity_type

  scaling_config {
    min_size     = var.scaling.min_size
    max_size     = var.scaling.max_size
    desired_size = var.scaling.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "db-api"
  }

  taint {
    key    = "dedicated"
    value  = "db-api"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.base_tags, { Name = var.db_api_node_group_name })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
