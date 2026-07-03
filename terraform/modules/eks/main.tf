# ---------------------------------------------------------------------------
# EKS module — the telos-cluster control plane (baseArch.md).
# Private-only endpoint: admin is done from the bastion inside the VPC.
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
    Module = "eks"
  })
}

# Additional control-plane security group. EKS also creates its own managed
# "cluster security group"; this explicit SG documents and controls API access
# on 443 from inside the VPC (bastion), matching baseArch.md's SG setup.
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS control plane SG — API access from within the VPC (bastion)."
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, { Name = "${var.cluster_name}-cluster-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_vpc" {
  security_group_id = aws_security_group.cluster.id
  description       = "HTTPS to the private API endpoint from inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound from the control plane ENIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(local.base_tags, { Name = var.cluster_name })
}
