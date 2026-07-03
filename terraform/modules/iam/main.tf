# ---------------------------------------------------------------------------
# IAM module — codifies the roles documented in baseArch.md:
#   - EKS cluster role
#   - shared node role (managed node groups reference this)
#   - bastion instance profile (SSM-only, least privilege)
#   - EKS OIDC provider (enables IRSA; role bindings deferred — see TODO below)
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Partition-aware managed-policy ARNs (aws / aws-cn / aws-us-gov).
data "aws_partition" "current" {}

locals {
  managed_policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"

  base_tags = merge(var.tags, {
    Module = "iam"
  })

  # Static toggle: keeps `count` plan-time-known even when the issuer URL is
  # only known after the cluster is created (avoids "count depends on values
  # that cannot be determined until apply").
  create_oidc = var.enable_oidc_provider
}

# ---------------------------------------------------------------------------
# EKS cluster role — assumed by the EKS control plane
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.managed_policy_prefix}/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Shared node role — assumed by EC2 worker nodes (managed node groups)
# Policies match baseArch.md's documented node role exactly.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-eks-node-role" })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryPullOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "${local.managed_policy_prefix}/${each.value}"
}

# ---------------------------------------------------------------------------
# Bastion role + instance profile — SSM only (least privilege)
# Matches baseArch.md's telos-bastion-ssm-profile.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  name = "${var.name_prefix}-bastion-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-bastion-ssm-role" })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "${local.managed_policy_prefix}/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-ssm-profile"
  role = aws_iam_role.bastion.name

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-bastion-ssm-profile" })
}

# ---------------------------------------------------------------------------
# EKS OIDC provider — foundation for IRSA (IAM Roles for Service Accounts).
# Created only once the cluster's OIDC issuer URL is known (passed from the
# eks module). The thumbprint is derived from the issuer's TLS cert.
# ---------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  count = local.create_oidc ? 1 : 0
  url   = var.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "this" {
  count = local.create_oidc ? 1 : 0

  url             = var.cluster_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-eks-oidc" })
}

# ---------------------------------------------------------------------------
# TODO (IRSA role bindings — deferred until the consuming services exist):
#
#   Phase 2 — async microservices:
#     * task-service role: sts:AssumeRoleWithWebIdentity trust scoped to its
#       service account, attached policy allowing sqs:SendMessage to the task
#       events queue.
#     * notification-service role: same trust pattern, policy allowing
#       sqs:ReceiveMessage / sqs:DeleteMessage / sqs:GetQueueAttributes on the
#       queue (+ DLQ).
#
#   Phase 4 (and ALB controller setup) — platform add-ons:
#     * aws-load-balancer-controller role: IRSA trust + the controller's IAM
#       policy (see modules/alb-controller/iam_policy.json).
#     * Any observability exporters needing AWS API access (e.g. CloudWatch).
#
# Each binding will follow the same shape:
#   data.aws_iam_policy_document.<svc>_assume {
#     principals { type = "Federated"
#                  identifiers = [aws_iam_openid_connect_provider.this[0].arn] }
#     condition  { test = "StringEquals"
#                  variable = "<oidc>:sub"
#                  values   = ["system:serviceaccount:<ns>:<sa>"] }
#   }
# These are intentionally omitted now because the service accounts / namespaces
# they must trust do not exist yet.
# ---------------------------------------------------------------------------
