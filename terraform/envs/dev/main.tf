terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Module graph (Phase 1). Textual order: vpc -> iam -> ecr -> eks
#                                         -> node-groups -> bastion
#
# Dependency notes:
#   * eks depends on iam.cluster_role_arn (implicit). The iam cluster_role_arn
#     OUTPUT carries depends_on the AmazonEKSClusterPolicy attachment, so the
#     cluster waits for the attachment WITHOUT a module-level depends_on
#     (which would create a cycle against the OIDC provider — see below).
#   * iam consumes eks.oidc_issuer_url to register the OIDC provider for IRSA.
#     This is NOT a cycle: the cluster role and the OIDC provider are distinct
#     resources (iam.cluster_role -> eks.cluster -> iam.oidc_provider).
#     enable_oidc_provider is a STATIC bool so the provider's `count` is known
#     at plan time even though the issuer URL is known-only-after-apply.
#   * alb-controller is intentionally excluded here — it needs a live cluster
#     (Helm/kube provider) and is wired in a later phase.
# ---------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  region       = var.region
  name_prefix  = var.project
  cluster_name = var.cluster_name # tags subnets for EKS/ALB auto-discovery
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = var.project

  # Scope the bastion's eks:DescribeCluster permission to this cluster's ARN.
  # Plain var (not module.eks output) so the ARN is known at plan time and adds
  # no dependency cycle.
  cluster_name = var.cluster_name

  # IRSA: register the OIDC provider using the cluster's issuer URL. The URL is
  # known-only-after-apply on first run; the static toggle keeps `count` valid.
  enable_oidc_provider    = true
  cluster_oidc_issuer_url = module.eks.oidc_issuer_url
}

module "ecr" {
  source = "../../modules/ecr"
  # No dependencies. Defaults create telos-frontend / telos-backend repos.
}

module "eks" {
  source = "../../modules/eks"

  cluster_name     = var.cluster_name
  cluster_role_arn = module.iam.cluster_role_arn
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr

  # Control plane ENIs span all subnets (public + private) across AZs.
  subnet_ids = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)

  # Private-only endpoint (module defaults), matching baseArch.md.
}

module "node_groups" {
  source = "../../modules/node-groups"

  cluster_name       = module.eks.cluster_name
  node_role_arn      = module.iam.node_role_arn
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Explicit dependency on the cluster (in addition to the implicit
  # cluster_name reference) so node groups never race the control plane.
  depends_on = [module.eks]
}

module "bastion" {
  source = "../../modules/bastion"

  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.public_subnet_ids[0]
  instance_profile_name = module.iam.bastion_instance_profile_name
  operator_ip_cidr      = var.operator_ip_cidr

  # user_data bootstraps kubectl + kubeconfig at first boot.
  region       = var.region
  cluster_name = var.cluster_name

  # Create the bastion only AFTER the cluster is ACTIVE (the aws_eks_cluster
  # create returns once ACTIVE), so first-boot update-kubeconfig can succeed.
  # The user_data script also waits for ACTIVE as defense-in-depth.
  depends_on = [module.eks]
}

# Grant the bastion role kubectl access via an EKS Access Entry (not aws-auth),
# so kubectl runs on the bastion's own instance-profile identity — no human IAM
# user credentials ever land on the host. Read-only (AmazonEKSAdminViewPolicy)
# by default for validation; flip access_policy_arn to AmazonEKSClusterAdminPolicy
# when deploying manifests from the bastion. Depends on eks (cluster) + iam
# (bastion role); no cycle since the bastion role is independent of the cluster.
module "eks_access" {
  source = "../../modules/eks-access"

  cluster_name  = module.eks.cluster_name
  principal_arn = module.iam.bastion_role_arn
}

# AWS Load Balancer Controller — IRSA IAM role + AWS-published policy only.
# The Helm chart + service account are installed with `helm` from the bastion
# (the cluster endpoint is private-only, so the Helm/kubernetes providers can't
# reach the API from here). Purely additive; consumes existing iam OIDC outputs.
module "alb_controller" {
  source = "../../modules/alb-controller"

  oidc_provider_arn = module.iam.oidc_provider_arn
  oidc_provider_url = module.iam.oidc_provider_url
}
