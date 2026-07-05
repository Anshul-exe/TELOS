# ---------------------------------------------------------------------------
# eks-access module — grants an IAM principal kubectl access to the cluster
# through EKS Access Entries (the modern replacement for the aws-auth
# ConfigMap). Purpose: let the bastion run kubectl on its OWN instance-profile
# identity, so no human IAM user credentials are ever placed on the host.
#
# Requires the cluster's authentication_mode to be API or API_AND_CONFIG_MAP
# (set explicitly in modules/eks). Managed node groups create their own
# EC2_LINUX access entries automatically; this STANDARD entry is independent.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_eks_access_entry" "this" {
  cluster_name      = var.cluster_name
  principal_arn     = var.principal_arn
  type              = "STANDARD"
  kubernetes_groups = var.kubernetes_groups

  tags = merge(var.tags, { Module = "eks-access" })
}

resource "aws_eks_access_policy_association" "this" {
  cluster_name  = var.cluster_name
  principal_arn = var.principal_arn
  policy_arn    = var.access_policy_arn

  # "cluster" scope is required for cluster-scoped resources like `nodes`
  # (a "namespace" scope cannot see nodes, breaking `kubectl get nodes`).
  access_scope {
    type = var.access_scope_type
  }

  # AWS rejects a policy association before the access entry exists.
  depends_on = [aws_eks_access_entry.this]
}
