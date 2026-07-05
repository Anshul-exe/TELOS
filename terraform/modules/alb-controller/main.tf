# ---------------------------------------------------------------------------
# alb-controller module — IRSA IAM role + policy for the AWS Load Balancer
# Controller.
#
# SCOPE: this module manages ONLY the AWS IAM plane (the IRSA role, the
# AWS-published IAM policy, and their attachment). It intentionally does NOT
# install the Helm chart or create the Kubernetes ServiceAccount, because the
# cluster endpoint is private-only (endpoint_public_access = false): the Helm/
# kubernetes Terraform providers cannot reach the API server from where this
# stack is applied. The chart is installed with `helm` from the bastion, which
# creates the annotated ServiceAccount itself (serviceAccount.create=true).
# See the module README / the plan output notes for the exact helm command.
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
