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
# Module graph (Phase 1+2). Textual order: vpc -> iam -> ecr -> sqs -> eks
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

  # Phase 2 — IRSA for async microservices. The SQS ARNs gate role creation:
  # roles are only created when both OIDC is enabled and an ARN is supplied.
  task_service_sqs_queue_arn         = module.sqs.queue_arn
  notification_service_sqs_queue_arn = module.sqs.queue_arn

  # Phase 3 — IRSA for Jenkins
  jenkins_ecr_repo_arns = [
    for name, repo_arn in module.ecr.repository_arns : repo_arn
    if contains(["auth-service", "task-service", "notification-service", "frontend"], name)
  ]
}

module "ecr" {
  source = "../../modules/ecr"
  # No dependencies. Defaults create frontend, task, auth, notification repos.
}

module "sqs" {
  source = "../../modules/sqs"
  # No dependencies. Defaults create telos-task-events + DLQ.
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

  # Write access: the bastion now deploys Helm charts (e.g. the LB controller
  # CRDs), which require cluster-scoped create permissions. ClusterAdmin grants
  # full cluster-admin; AdminViewPolicy (read-only) is insufficient for applies.
  access_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

# AWS Load Balancer Controller — IRSA IAM role + AWS-published policy AND the
# Helm chart install. The chart's Helm/kubernetes providers use exec-based auth
# (aws eks get-token) against the PRIVATE cluster endpoint, so this stack must
# be applied from the bastion (inside the VPC). See the module header.
module "alb_controller" {
  source = "../../modules/alb-controller"

  oidc_provider_arn = module.iam.oidc_provider_arn
  oidc_provider_url = module.iam.oidc_provider_url

  # Helm install inputs. Passing the eks cluster_name/endpoint/ca_data already
  # makes alb_controller implicitly depend on module.eks — no depends_on needed
  # (and a module with its own provider blocks cannot use depends_on anyway).
  region           = var.region
  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_ca_data  = module.eks.cluster_ca_data
  vpc_id           = module.vpc.vpc_id

  # Order the Helm release AFTER the bastion's ClusterAdmin access entry: the
  # module consumes this value through a terraform_data gate so the dependency
  # is a real graph edge (again, without a module-level depends_on).
  eks_access_policy_arn = module.eks_access.access_policy_arn
}
