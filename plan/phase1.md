# TELOS — Phase 1 Status & Roadmap

> **Last updated:** 2026-07-07  
> **Current phase:** Phase 1 (Terraform IaC) — fully validated and complete  
> **Reference docs:** [plan.md](plan.md), [baseArch.md](plan/baseArch.md)

---

## 1. Project Status Summary

TELOS is a full DevOps portfolio platform built on AWS EKS, expanding an earlier manually-deployed three-tier TODO application into a Terraform-managed, microservice-oriented stack with Jenkins CI, ArgoCD CD, and Prometheus/Grafana/Loki observability — all designed to be spun up, demoed, and torn down within budget-gated sessions against a $115 AWS credit pool. **Phase 1 (Terraform IaC)** is fully validated and complete: 8 Terraform modules codify the full infrastructure (VPC, EKS, node groups, ECR, IAM, bastion, ALB controller, and EKS access entries). A total of 49 actual resources are managed by Terraform. A test manifest (nginx deploy + ALB ingress in `telos-test` namespace) was successfully applied and confirmed (ALB DNS populated twice — once before, once after ALB controller rework). No AWS resources are currently running as the environment has been successfully torn down.

---

## 2. What Was Actually Built in Phase 1

### 2.1 Terraform Modules

| Module | Provisions | Key Design Decisions |
|--------|-----------|---------------------|
| **vpc** | VPC (192.168.0.0/16), 3 public + 3 private subnets, IGW, single NAT GW + EIP, route tables | **Single NAT Gateway** (cost optimization, not per-AZ HA). Subnet CIDRs use `cidrsubnet(..., 8, i)` / `cidrsubnet(..., 8, i+128)`. Auto-tagged for EKS/ALB subnet discovery. |
| **eks** | EKS cluster, cluster security group, SG rules (API 443 from VPC CIDR) | **Private-only API endpoint** (public access disabled). `authentication_mode = API_AND_CONFIG_MAP`. `bootstrap_cluster_creator_admin_permissions = true`. Kubernetes v1.34. CloudWatch logging disabled by default (cost). |
| **node-groups** | Two managed node groups: `telos-general-ng` (public subnets) + `telos-db-api-ng` (private subnets, taint `dedicated=db-api:NoSchedule`, label `workload=db-api`) | **Both groups default to SPOT** capacity. `t3.small`, 2–4 nodes each. `lifecycle { ignore_changes = [desired_size] }` prevents TF fighting autoscaler. |
| **ecr** | ECR repos: `telos-frontend`, `telos-backend` | Scan-on-push enabled. Lifecycle: expire untagged after 3 days, keep last 10 tagged. Tag mutability: `MUTABLE` (default). |
| **iam** | EKS cluster role, shared node role (4 managed policies), bastion SSM role + instance profile, bastion inline policy (eks:DescribeCluster, S3/DynamoDB state access), ReadOnlyAccess for bastion, OIDC provider for IRSA | Bastion role gained AWS-managed `ReadOnlyAccess` (to refresh state) and an inline policy for S3/DynamoDB backend access (scoped to the exact bucket/table ARNs) to run Terraform locally. |
| **bastion** | EC2 instance (Amazon Linux 2023, `t3.micro`), SG (SSH from operator IP only), user_data bootstrap script | **IMDSv2 enforced**. User data installs kubectl (stable-1.34), `git`, and a pinned `terraform` binary (1.15.6). Curl calls to `dl.k8s.io` use `--http1.1` to fix HTTP/2 PROTOCOL_ERROR. Waits for cluster ACTIVE, writes shared kubeconfig. SSM-capable. |
| **alb-controller** | IRSA IAM role + AWS-published policy (v3.4.0) + `helm_release` of the AWS Load Balancer Controller | **Fully automated via Terraform.** Providers (helm/kubernetes) use exec-based auth (`aws eks get-token`) against the bastion's identity. Uses `terraform_data.eks_access_gate` to wait for the bastion's ClusterAdmin entry before applying the Helm chart. |
| **eks-access** | EKS access entry + policy association for bastion role → cluster | Uses **EKS Access Entry API** (modern, replaces deprecated aws-auth ConfigMap). Bastion gets `AmazonEKSClusterAdminPolicy` (write access for deploys). |

> **⚠️ Deviation from plan.md:** The `eks-access` module exists and is used but is **not listed** in plan.md's target directory structure (section 3). It's a necessary addition — without it, the bastion can't authenticate to the private-endpoint cluster. Plan.md's target structure should be updated to include it.

> **⚠️ Missing from plan.md target:** The `sqs` module listed in plan.md section 3 does **not exist yet** — correctly deferred to Phase 2.

> **⚠️ Workflow Constraint — The "Split Apply" Process:** Because the `alb-controller` module uses the `helm_release` resource against a private EKS endpoint, a full `terraform apply` from your local laptop will **fail** when it reaches the ALB controller (it will return a "Kubernetes cluster unreachable" error). To create the infrastructure from an empty state, you must:
> 1. Run `terraform apply` from your laptop. It will successfully provision the VPC, EKS, Node Groups, and Bastion, but will error out on the `alb-controller` Helm chart.
> 2. SSH into the newly created bastion, clone the repo, run `terraform init`, and run `terraform apply` again from inside the VPC to complete the Helm installation.
> 3. For any future updates or teardowns (`terraform destroy`), you must run them from the bastion.

### 2.2 Resource Naming Convention (post-rename)

All resources use `telos-*` naming via the `project = "telos"` variable:

| Resource | Actual Name |
|----------|------------|
| EKS Cluster | `telos-cluster` |
| VPC | `telos-vpc` |
| Public Subnets | `telos-public-<az>` |
| Private Subnets | `telos-private-<az>` |
| NAT Gateway | `telos-nat` |
| General Node Group | `telos-general-ng` |
| DB-API Node Group | `telos-db-api-ng` |
| ECR Repos | `telos-frontend`, `telos-backend` |
| Cluster IAM Role | `telos-eks-cluster-role` |
| Node IAM Role | `telos-eks-node-role` |
| Bastion Instance | `telos-bastion` |
| Bastion SG | `telos-bastion-sg-` (name_prefix) |
| Bastion IAM Role | `telos-bastion-ssm-role` |
| Bastion Instance Profile | `telos-bastion-ssm-profile` |
| ALB Controller Role | `telos-alb-controller` |
| OIDC Provider | `telos-eks-oidc` |
| S3 State Bucket | `telos-tfstate-23c1b86e` |
| DynamoDB Lock Table | `telos-tf-locks` |

### 2.3 State Backend

| Detail | Value |
|--------|-------|
| S3 Bucket | `telos-tfstate-23c1b86e` (random suffix for global uniqueness) |
| State Key | `envs/dev/terraform.tfstate` |
| DynamoDB Table | `telos-tf-locks` |
| Region | `ap-south-1` |
| Encryption | `true` (SSE-S3 / AES256) |
| Versioning | Enabled |
| Public Access | Fully blocked |

**Bootstrap is managed by local state** (`terraform/bootstrap/terraform.tfstate`) — this is the one component that persists across sessions and is **NOT torn down between sessions** (per plan.md ground rules). Both resources have `prevent_destroy = true`.

### 2.4 Codification Status vs baseArch.md

| baseArch.md Component | Terraform Status | Notes |
|-----------------------|-----------------|-------|
| VPC + subnets + IGW/NAT | ✅ Codified | Same CIDR (192.168.0.0/16), same AZ count. Subnet offset scheme differs cosmetically. |
| EKS cluster | ✅ Codified | Same version (1.34), same private-only endpoint. |
| Node groups (app + db-api) | ✅ Codified | Same topology (public/private), same taints/labels. **Changed:** SPOT (was ON_DEMAND), node group names differ. |
| ECR repos | ✅ Codified | **Changed:** `telos-frontend`/`telos-backend` (was `three-tier-lab-*`). |
| ACM cert | ❌ Referenced only | ACM cert ARN is hardcoded in manifests — not managed by Terraform (pre-existing). |
| Bastion | ✅ Codified | Same role (SSM + SSH). **Changed:** AMI is AL2023 (was unspecified), SSH restricted to operator IP via variable. |
| IAM roles | ✅ Codified | Same policies. **Changed:** node role uses `AmazonEC2ContainerRegistryPullOnly` (matches baseArch.md exactly). |
| Security groups | ✅ Codified | ALB SG created dynamically by ALB Controller. Cluster SG + bastion SG codified. |
| ALB Controller | ✅ Codified | IRSA IAM role/policy codified. Helm chart installed by Terraform using exec-based auth from the bastion's identity. |
| EKS access (kubectl auth) | ✅ Codified | **New:** Uses EKS Access Entry API (was manual aws-auth ConfigMap). |
| Manifests (app workloads) | ❌ Not in Terraform | Manifests are plain YAML, applied via kubectl from bastion. This is by design for Phase 1. |
| DNS (Route53/Cloudflare) | ❌ Not in Terraform | External DNS management, not codified. |

### 2.5 Environment Composition (`terraform/envs/dev/`)

Files: `main.tf`, `backend.tf`, `variables.tf`, `terraform.tfvars`, `terraform.tfvars.example`, `outputs.tf`

Module call order: `vpc` → `iam` → `ecr` → `eks` → `node_groups` → `bastion` → `eks_access` → `alb_controller`

Key: the `iam ↔ eks` dependency is intentionally **not a cycle** — `iam.cluster_role_arn` feeds into `eks`, while `eks.oidc_issuer_url` feeds back into `iam` for the OIDC provider (distinct resources). This is documented inline in `envs/dev/main.tf`.

---

## 3. Rename Audit: `three-tier-lab` / `three-tier` → `telos`

### 3.1 Completed Renames

| Location | Old Name | New Name | Status |
|----------|---------|----------|--------|
| Terraform — all modules | `three-tier-*` | `telos-*` | ✅ **Done** — zero `three-tier` references in any `.tf` file |
| Manifests — all namespaces | `three-tier` | `telos` | ✅ **Done** — all 10 YAML files use `namespace: telos` |
| Manifests — ECR image refs | `three-tier-lab-frontend/backend` | `telos-frontend/backend` | ✅ **Done** |
| Manifests — ingress host | `assignment.anshulfml.me` | `telos.anshulfml.me` | ✅ **Done** |
| Manifests — frontend env | `assignment.anshulfml.me/api/tasks` | `telos.anshulfml.me/api/tasks` | ✅ **Done** |
| Bootstrap — S3/DynamoDB | N/A (created fresh) | `telos-tfstate-*` / `telos-tf-locks` | ✅ **Done** |

### 3.2 Remaining Old References (Cleanup Checklist)

| Location | Line(s) | Content | Action Needed |
|----------|---------|---------|--------------|
| `manifests/Database/secrets.yaml` | 8 | Comment `#Three-Tier-Project` after password value | **Remove or update comment** |
| `README.md` | 5 | Title: `# Three-Tier End-to-End Production Infrastructure on AWS EKS` | **Update to TELOS branding** |
| `README.md` | 2 | `Expanding the older project [three-tier-lab]...` | Acceptable as historical context, but review wording |
| `README.md` | 47 | `...three-tier architecture...` | Architectural term — acceptable, but should match new narrative |
| `README.md` | 79 | `k8s-threetie-mainlb-*` in ASCII diagram | **Update ALB name in diagram** |
| `plan/baseArch.md` | 15–17, 30, 34, 39–41, 46, 51, 62, 64, 93–94 | All original `three-tier-*` resource names | **Expected** — baseArch.md documents the pre-Terraform manual build. Add a note at the top that these names have been superseded by `telos-*` in Terraform. _(Note: a header was already added at L1–3, but it could be more explicit.)_ |
| ACM Certificate | N/A | CN is `assignment.anshulfml.me` (hardcoded ARN in manifests) | **Confirm:** Is a new cert for `telos.anshulfml.me` provisioned, or does the existing wildcard/SAN cert cover it? The ingress references this same cert ARN but with host `telos.anshulfml.me`. |
| `manifests/Frontend/iam_policy.json` | — | Older/divergent copy of ALB controller IAM policy (242 lines vs 252 at root) | **Remove or mark deprecated** — the authoritative copy is `terraform/modules/alb-controller/iam_policy.json` (and `manifests/iam_policy.json` is also redundant now). |

---

## 4. Phase 1 Validation Checklist

### 4.1 Test Manifest Status

| Item | Status | Detail |
|------|--------|--------|
| nginx Deployment in `telos-test` ns | ✅ Validated | Created as a heredoc on the bastion and applied successfully. |
| ClusterIP Service for nginx | ✅ Validated | Same. |
| ALB Ingress for test | ✅ Validated | Same. DNS populated successfully, twice (before and after ALB controller rework). |
| Applied to cluster | ✅ Complete | Infra successfully tested and torn down. No AWS resources currently running. |

### 4.2 Validation Steps (to close out Phase 1)

> ⚠️ **Budget reminder:** This is a budget-gated session (plan.md ground rules). Target 2–3 hrs max. Validate fast, capture proof, destroy.

1. **`terraform apply` locally** from `terraform/envs/dev/` on your laptop. Let it run until it successfully creates the VPC, cluster, and bastion. Expect it to fail when it reaches the `alb-controller` Helm release (cluster unreachable).
2. **SSH to bastion** (`ssh -i ~/.keys/project-bastion-key.pem ec2-user@<bastion_ip>`).
3. **Finish the apply from the bastion:** Clone the repo, `cd terraform/envs/dev`, run `terraform init`, and `terraform apply` to complete the ALB controller installation.
4. **Verify cluster access:** `kubectl get nodes`, `kubectl get ns` — confirm nodes are Ready, `kube-system` pods are running.
5. **Apply test manifest** — create `telos-test` namespace, deploy nginx + ClusterIP + ALB ingress.
6. **Confirm ALB provisions:** watch `kubectl -n telos-test get ingress mainlb-test -w` until ADDRESS populates.
7. **Verify ALB Controller logs:** `kubectl -n kube-system logs deploy/aws-load-balancer-controller` — confirm no errors.
8. **Confirm target group health:** check AWS Console or `aws elbv2 describe-target-health`.
9. **Capture proof:** screenshot/copy `kubectl get all -n telos-test`, `kubectl get ingress -n telos-test`, `terraform output`, ALB Controller logs.
10. **Cleanup:** `kubectl delete ns telos-test`.
11. **`terraform destroy`** — confirm clean teardown (this must be run from the bastion to allow Helm provider destruction).
12. **Record approximate cost** for session (AWS Cost Explorer or billing dashboard).

### 4.3 Known Pre-Validation Concerns (Resolved)

- The test manifest was created on the bastion's filesystem and successfully applied.
- ~~ALB Controller Helm chart installation is a manual step~~ (Resolved: now fully automated by Terraform via `helm_release`).
- The bastion's SSH key (`project-bastion-key`) must exist locally at `~/.keys/project-bastion-key.pem`.

---

## 5. Architecture Diff: baseArch.md (Manual) vs Current Terraform

| Aspect | baseArch.md (Manual Build) | Terraform (Phase 1) | Delta |
|--------|--------------------------|---------------------|-------|
| **VPC CIDR** | 192.168.0.0/16 | 192.168.0.0/16 | Identical |
| **Subnet count** | 3 public + 3 private | 3 public + 3 private | Identical |
| **NAT Gateway** | 1 (single) | 1 (single) | Identical |
| **EKS version** | v1.34 | v1.34 | Identical |
| **API endpoint** | Private-only | Private-only | Identical |
| **Node groups** | `ng-7f9c0e2a` (public, ON_DEMAND) + `db-api-ng` (private, ON_DEMAND) | `telos-general-ng` (public, **SPOT**) + `telos-db-api-ng` (private, **SPOT**) | **Capacity type changed to SPOT** (cost optimization). Names changed. |
| **Node instance type** | t3.small (2–4 nodes each) | t3.small (2–4 nodes each) | Identical |
| **Taints/labels** | `dedicated=db-api:NoSchedule`, `workload=db-api` on db-api group | Same | Identical |
| **ECR repos** | `three-tier-lab-frontend`, `three-tier-lab-backend` | `telos-frontend`, `telos-backend` | **Renamed** |
| **ECR features** | Default config | Scan-on-push, lifecycle policy (keep 10, expire untagged 3d) | **Enhanced** |
| **Node IAM** | `AmazonEC2ContainerRegistryPullOnly` + 3 others | Same 4 policies | Identical |
| **Bastion** | `three-tier-bastion`, t3.micro(?), manual kubectl setup | `telos-bastion`, t3.micro, **auto-provisioned kubeconfig** via user_data | **Improved** — kubectl ready at boot |
| **Bastion AMI** | Unspecified (likely AL2) | Amazon Linux 2023 | **Updated** |
| **Bastion SSH** | Restricted to operator IP | Restricted to operator IP (via variable) | Identical intent |
| **IMDSv2** | Enforced | Enforced | Identical |
| **Cluster auth** | aws-auth ConfigMap (implicit) | **EKS Access Entry API** | **Modernized** |
| **ALB Controller** | Running in kube-system | IRSA IAM codified; Helm installed from bastion | Identical outcome, different provisioning path |
| **Ingress host** | `assignment.anshulfml.me` | `telos.anshulfml.me` | **Changed** |
| **K8s namespace** | `three-tier` | `telos` | **Renamed** |
| **State management** | None (manual) | S3 + DynamoDB remote backend | **New** |

---

## 6. Phase 2 Roadmap (Detailed, Actionable)

### 6.0 Prerequisite: Phase 0 Status Check

> ⚠️ **Phase 0 is entirely undone.** Plan.md's Phase 2 assumes Phase 0 (repo restructure + local docker-compose dev loop) is complete. The actual repo state is:

| Phase 0 Task | Status |
|-------------|--------|
| `backend/` → `services/task-service/` | ❌ `backend/` still at repo root |
| Scaffold `services/auth-service/` | ❌ Does not exist |
| Scaffold `services/notification-service/` | ❌ Does not exist |
| `docker-compose.yml` for local dev | ❌ Does not exist |
| All services running locally via `docker-compose up` | ❌ Not possible |

**Decision needed:** Do Phase 0 before Phase 2 (recommended by plan.md), or skip Phase 0 and scaffold services directly on EKS (burns AWS credits but avoids local setup). See Section 8.

### 6.1 Service Deployment (Plain Manifests)

Assuming Phase 0 is done or bypassed, the following manifests need to be created or modified:

| Service | Manifest Files to Create/Modify | Location |
|---------|-------------------------------|----------|
| **auth-service** | `deployment.yaml`, `service.yaml` (new) | `manifests/Auth/` or `services/auth-service/k8s/` |
| **task-service** | Modify existing `manifests/Backend/deployment.yaml` — add SQS publish env vars, update image to `telos-task-service` | Existing `manifests/Backend/` |
| **notification-service** | `deployment.yaml`, `service.yaml` (new) | `manifests/Notification/` or `services/notification-service/k8s/` |
| **Postgres (auth-service DB)** | `deployment.yaml`, `service.yaml`, `pvc.yaml`, `secret.yaml` (new) | `manifests/Postgres/` |
| **frontend** | Modify env `REACT_APP_BACKEND_URL` to use new API gateway paths | `manifests/Frontend/deployment.yaml` |

### 6.2 SQS Module (`terraform/modules/sqs/`)

Files to create:
- `main.tf` — `aws_sqs_queue.task_events` + DLQ (`aws_sqs_queue.task_events_dlq`) + redrive policy
- `variables.tf` — queue name, visibility timeout, message retention, DLQ max receive count
- `outputs.tf` — queue URL, queue ARN, DLQ URL, DLQ ARN

**IRSA policy shape:**

| Service | Permissions | Queue |
|---------|------------|-------|
| task-service (publisher) | `sqs:SendMessage` | task-events queue only |
| notification-service (consumer) | `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes`, `sqs:ChangeMessageVisibility` | task-events queue + DLQ |

Both roles need IRSA trust relationships scoped to their service accounts. The IAM module already has a TODO block (lines 186–212) documenting this exact pattern.

> ⚠️ **Known risk area (plan.md section 6):** SQS IAM permissions via IRSA are a common stumbling block — budget extra time for getting the service account → IAM role trust relationship right.

### 6.3 Ingress Path-Based Routing Changes

**Current state:** Single rule — host `telos.anshulfml.me`, path `/` → `frontend:3000`. No API routing.

**Target state:**
```yaml
rules:
  - host: telos.anshulfml.me
    http:
      paths:
        - path: /api/auth
          pathType: Prefix
          backend:
            service:
              name: auth-service
              port:
                number: 3500  # or whatever port auth-service uses
        - path: /api/tasks
          pathType: Prefix
          backend:
            service:
              name: api  # existing task-service
              port:
                number: 3500
        - path: /
          pathType: Prefix
          backend:
            service:
              name: frontend
              port:
                number: 3000
```

This is a **real change**, not just an addition — the current ingress has the frontend proxying `/api` internally via nginx. Moving to path-based routing at the ALB level means:
1. Frontend nginx.conf no longer needs the `/api` proxy block
2. Backend is now directly routable from the ALB (was previously ClusterIP-only behind nginx proxy)
3. Path ordering matters — `/api/auth` and `/api/tasks` must be before `/`

### 6.4 ECR Repos Needed

New repos to add to the ECR module's `repository_names` default:
- `telos-auth-service`
- `telos-notification-service`
- Optionally rename `telos-backend` → `telos-task-service` (or keep both for backward compat)

### 6.5 Definition of Done (Phase 2)

Adapted from plan.md, adjusted for actual state:

- [ ] Phase 0 complete (services scaffolded, docker-compose working locally) — **OR** decision made to skip
- [ ] All 3 services + frontend deployed to EKS via plain manifests in `telos` namespace
- [ ] SQS queue + DLQ provisioned via `terraform/modules/sqs/`
- [ ] IRSA roles for task-service (publish) and notification-service (consume) working
- [ ] Ingress updated with path-based routing (`/api/auth`, `/api/tasks`, `/`)
- [ ] End-to-end flow validated: register user → login → create task → notification-service logs/records the event
- [ ] Proof captured (kubectl output, browser screenshot, ALB console)
- [ ] `terraform destroy` clean teardown
- [ ] Cost logged

---

## 7. Remaining Phases at a Glance

| Phase | Scope | Key Risk (plan.md §6) | Session Budget |
|-------|-------|----------------------|---------------|
| **3 — Jenkins CI** | Jenkins (EC2 or in-cluster), shared library pipeline: secret scan → SAST → dep audit → unit test → build → image scan (Trivy) → sign (cosign) → push ECR → bump GitOps tag | Jenkins-to-ArgoCD handoff bugs (wrong path/key in GitOps repo) | 3–5 hrs |
| **4 — ArgoCD GitOps** | ArgoCD in-cluster, app-of-apps, auto-sync + self-heal, drift correction demo | Format mismatch between Jenkins tag update and ArgoCD Kustomize/Helm overlay | 2–3 hrs |
| **5 — Observability** | kube-prometheus-stack (Prometheus + Grafana + Alertmanager), Loki/Promtail, `/metrics` endpoints, 2 dashboards, alert rules | Resource hunger — defaults tuned for real clusters, not 2–4 node t3.small | 3–4 hrs |
| **6 — Docs & Portfolio** | README rewrite, runbook, screenshot/recording collection | Scope creep — resist adding features | N/A (local) |
| **Stretch** | HPA on SQS depth (KEDA), RDS migration, distributed tracing (Tempo/Jaeger), Argo Rollouts (blue/green), multi-env promotion | Only after Phase 6 is fully done | Variable |

**Overall budget consumed so far:** $[TBD - user to fill in] (Phase 1 validation sessions have now run real AWS time for `apply` and teardown).

---

## 8. Open Decisions / Things to Confirm Before Phase 2

| Decision | plan.md Recommendation | Current Status |
|----------|----------------------|---------------|
| **Postgres for auth-service: RDS vs in-cluster** | In-cluster Postgres pod + PVC (simpler teardown, zero extra AWS billing). Migrate to RDS as Phase 7 stretch goal. | **Open** — not yet implemented. Recommend confirming in-cluster. |
| **Jenkins: EC2 vs in-cluster** | EC2 is simpler for first pass; in-cluster is more "cloud-native." | **Open** — no Jenkins work started. EC2 is the pragmatic choice given private-endpoint complexity (same issue as ALB controller Helm provider). |
| **Phase 0: do it or skip it?** | Phase 0 (local docker-compose dev loop) should come before Phase 2. | **Open — and a real gap.** Phase 0 is entirely undone. Options: (A) Do Phase 0 properly (recommended — costs $0, gives fast local iteration), (B) Skip and scaffold services directly on EKS (burns AWS credits for every iteration). |
| **Repo structure: monorepo vs services/ split** | plan.md specifies `services/task-service/`, `services/auth-service/`, `services/notification-service/`. | **Open** — `backend/` is still at repo root. Splitting is a Phase 0 task. |
| **GitOps repo: telos-gitops (separate repo)** | plan.md section 3 recommends a separate `telos-gitops` repo for ArgoCD. | **Open** — not created yet. Needed by Phase 4 at the latest, but manifest structure decisions in Phase 2 should anticipate it (Kustomize base + overlays). |
| **ACM cert: does `telos.anshulfml.me` resolve?** | Ingress host changed from `assignment.anshulfml.me` to `telos.anshulfml.me`, but the ACM cert ARN still references the `assignment.anshulfml.me` cert. | **Needs confirmation** — either the cert is a wildcard/SAN covering `telos.anshulfml.me`, or a new cert + DNS record is needed. |
| **Manifest location for new services** | plan.md shows `services/<name>/` with K8s manifests; current manifests are in `manifests/Backend/`, `manifests/Frontend/`, `manifests/Database/`. | **Open** — decide whether new service manifests go in `manifests/<ServiceName>/` (consistent with current layout) or move everything to `services/<name>/k8s/` (plan.md's target). |
| **Duplicate `iam_policy.json` files** | Three copies exist: `terraform/modules/alb-controller/iam_policy.json` (authoritative, v3.4.0), `manifests/iam_policy.json` (newer/broader, 252 lines), `manifests/Frontend/iam_policy.json` (older, 242 lines). | **Cleanup needed** — Terraform's copy is authoritative. The two manifest copies are legacy from the manual build and should be removed or clearly marked deprecated. |
| **`secrets.yaml` in git** | Real base64 credentials (`password123` / `admin`) committed to git. `.gitignore` has `secrets.yaml` but the file was tracked before the rule was added. | **Security concern** — noted in baseArch.md §12. Not blocking for portfolio, but should be addressed (rotate creds, use `secrets.example.yaml` template, untrack the real file). |
