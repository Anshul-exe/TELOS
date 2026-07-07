# ---------------------------------------------------------------------------
# alb-controller module — IRSA IAM role + policy + Helm install of the AWS
# Load Balancer Controller.
#
# SCOPE: this module manages the AWS IAM plane (the IRSA role, the AWS-published
# IAM policy, and their attachment) AND installs the Helm chart, which creates
# the annotated kube-system ServiceAccount itself (serviceAccount.create=true).
#
# APPLY FROM THE BASTION: the cluster endpoint is private-only
# (endpoint_public_access = false), so the Helm/kubernetes providers below can
# reach the API server ONLY when `terraform apply` runs from INSIDE the VPC —
# i.e. from the bastion. The providers authenticate with an exec plugin
# (`aws eks get-token`) using the bastion's instance-profile identity (which has
# an EKS Access Entry with ClusterAdmin — see module.eks_access). Running plan/
# apply from outside the VPC will fail to dial the private endpoint; that is the
# intended tradeoff of keeping the endpoint private.
#
# IAM policy source: kubernetes-sigs/aws-load-balancer-controller v3.4.0
#   docs/install/iam_policy.json (vendored verbatim as iam_policy.json — do not
#   hand-edit; re-fetch from the matching release tag when bumping the chart).
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Helm/kubernetes providers authenticate to the cluster with an exec plugin
# (`aws eks get-token`) rather than a static token, so credentials are minted
# per-invocation from the caller's AWS identity (the bastion instance profile).
provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

locals {
  # OIDC provider host/path without scheme, used to build the IRSA condition
  # keys (<issuer>:sub / <issuer>:aud). Handles a URL passed with or without
  # the https:// prefix.
  oidc_host = replace(var.oidc_provider_url, "https://", "")

  base_tags = merge(var.tags, { Module = "alb-controller" })
}

# Trust policy: allow the specific kube-system service account to assume this
# role via the cluster's OIDC provider (IRSA), audience sts.amazonaws.com.
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = merge(local.base_tags, { Name = var.role_name })
}

# AWS-published policy, vendored verbatim (not hand-rolled).
resource "aws_iam_policy" "this" {
  name        = var.role_name
  description = "AWS Load Balancer Controller policy (kubernetes-sigs v3.4.0), for the telos-cluster IRSA role."
  policy      = file("${path.module}/iam_policy.json")

  tags = merge(local.base_tags, { Name = var.role_name })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# Graph-ordering gate: consuming var.eks_access_policy_arn through a real
# resource makes helm_release (which depends_on this) wait for module.eks_access
# — i.e. the bastion's ClusterAdmin association — before the chart is applied.
# This replaces a module-level depends_on, which is not allowed on a module that
# configures its own providers. terraform_data is built-in (no provider needed).
resource "terraform_data" "eks_access_gate" {
  input = var.eks_access_policy_arn
}

# ---------------------------------------------------------------------------
# Helm install of the AWS Load Balancer Controller. serviceAccount.create=true
# lets the chart create the kube-system SA and annotate it with this module's
# IRSA role ARN (referenced internally — the role must exist and be attached
# before the controller pods start, hence the depends_on on the attachment).
# ---------------------------------------------------------------------------
resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = var.service_account_namespace

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.service_account_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.this.arn
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # The IRSA role + policy must be attached before the controller starts;
  # cluster readiness is implicit via cluster_endpoint/cluster_ca_data, and the
  # bastion's ClusterAdmin access via the eks_access_gate below.
  depends_on = [
    aws_iam_role_policy_attachment.this,
    aws_iam_policy.this,
    aws_iam_role.this,
    terraform_data.eks_access_gate,
  ]
}
