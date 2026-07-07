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

# Used to build the fully-qualified telos-cluster ARN for the scoped bastion
# eks:DescribeCluster permission below.
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

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

# Account-wide read-only (Describe/Get/List across all services, no write).
# Lets `terraform apply` run from the bastion refresh existing state before
# targeting module.alb_controller.helm_release.this — the Helm release itself
# only calls the Kubernetes API and makes no AWS write calls, so read-only AWS
# access is sufficient for that plan/refresh.
resource "aws_iam_role_policy_attachment" "bastion_readonly" {
  role       = aws_iam_role.bastion.name
  policy_arn = "${local.managed_policy_prefix}/ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-ssm-profile"
  role = aws_iam_role.bastion.name

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-bastion-ssm-profile" })
}

# Minimal EKS control-plane permissions for the bastion:
#   * eks:DescribeCluster — required by `aws eks update-kubeconfig` and scoped to
#     the telos-cluster ARN specifically (not eks:* / not "*").
#   * eks:ListClusters    — convenience for `aws eks list-clusters`. This action
#     does NOT support resource-level scoping (it enumerates all clusters in the
#     region), so AWS requires Resource="*" for it — a specific ARN would make
#     the statement match nothing. Kept in its own statement for that reason.
# kubectl authorization itself is granted by the EKS access entry (modules/
# eks-access), not by IAM, so no eks:AccessKubernetesApi is needed here.
resource "aws_iam_role_policy" "bastion_eks_describe" {
  count = var.cluster_name != "" ? 1 : 0

  name = "${var.name_prefix}-bastion-eks-describe"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeTelosClusterOnly"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid      = "ListClustersRegionWide"
        Effect   = "Allow"
        Action   = ["eks:ListClusters"]
        Resource = "*"
      },
    ]
  })
}

# Terraform remote-backend access for the bastion: the bastion now runs
# `terraform apply` itself (it is the only host that can reach the private EKS
# API for the Helm/kubernetes providers), so its role needs to read/write the
# S3 state object and acquire/release the DynamoDB state lock.
#   * S3: GetObject/PutObject on the state KEY (bucket/*), ListBucket on the
#     BUCKET itself (ListBucket is a bucket-level action — its resource is the
#     bucket ARN, not the object ARN — so it lives in its own statement).
#   * DynamoDB: the four item/table actions the S3 backend uses for locking.
# Scoped to the specific state bucket + lock table ARNs (never "*").
resource "aws_iam_role_policy" "bastion_tf_backend" {
  count = var.tf_state_bucket_arn != "" && var.tf_lock_table_arn != "" ? 1 : 0

  name = "${var.name_prefix}-bastion-tf-backend"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateObjectReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${var.tf_state_bucket_arn}/*"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.tf_state_bucket_arn
      },
      {
        Sid      = "StateLockTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
        Resource = var.tf_lock_table_arn
      },
    ]
  })
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
