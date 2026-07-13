# TELOS — Phase 2 Status & Hard Constraints Reference

> **Last updated:** 2026-07-11  
> **Current phase:** Phase 2 (Microservice Cutover) — Fully completed.  
> **Reference docs:** [plan.md](plan.md)

---

## 1. Current Architecture (As Built)

TELOS has evolved from a monolithic backend into a decoupled, event-driven microservices architecture on AWS EKS.

- **`frontend` (React)**
  - Expanded beyond original scope: now includes full registration/login flow and a notifications panel polling `GET /api/notifications` every 15s.
  - Auth token storage: **In-memory only** (deliberate limitation to reduce scope).
- **`auth-service` (Node.js/Express)**
  - Scaffolds a new authentication service managing JWT issuance.
  - **Datastore:** In-cluster Postgres (using `hostPath` PV).
- **`task-service` (Node.js/Express)**
  - The legacy backend monolith migrated and isolated.
  - **Datastore:** In-cluster MongoDB.
  - **Auth Enforcement:** **None.** It currently lacks JWT verification and is fully open (explicitly documented known limitation).
  - **Async Event:** Publishes `task.created` and `task.completed` payloads to an SQS queue via AWS SDK, using IRSA for permissions.
- **`notification-service` (Node.js/Express)**
  - Scaffolds a new consumer service that long-polls the SQS queue and writes unstructured notifications to a MongoDB `notifications` collection.
  - Serves `GET /api/notifications` for the frontend.

**Infrastructure:**

- **SQS Wiring:** Queue `telos-task-events` managed via Terraform (`modules/sqs`). Publisher (`task-service`) and consumer (`notification-service`) both authenticate natively using **IRSA** (IAM Roles for Service Accounts) tied to their EKS ServiceAccounts.
- **Ingress:** ALB path-based routing splits traffic (`/api/auth`, `/api/tasks`, `/api/notifications`, and `/`).
- **TLS:** Ingress is currently **HTTP-only** (`listen-ports: '[{"HTTP": 80}]'`) pending a fresh ACM certificate.

---

## 2. Hard Constraints Discovered

1. **Bastion vs. Laptop Split Apply:** The EKS control plane endpoint is strictly private. Thus, `terraform apply` cannot run fully from a laptop.
   - **Laptop:** Must be used for IAM changes and ECR module updates.
   - **Bastion:** Must be used for EKS-API-dependent resources (like the `alb-controller` Helm chart).
2. **Ignored Configuration State:** `terraform.tfvars` and `secrets.yaml` are correctly `.gitignore`'d for security but must be manually recreated from templates at the start of every session.
3. **Dynamic Operator IP:** The Bastion SSH security group rules depend on the operator's dynamic IP, which requires frequent updating in `terraform.tfvars`.
4. **hostPath PV Non-persistence:** The in-cluster Postgres and Mongo databases use `hostPath` PVs. Since the EKS Node Groups utilize Spot instances, node churn results in irrecoverable data loss for these stores. This is acceptable for a demo environment but must be known.
5. **Budget & Lifecycle Discipline:** The $115 budget limit remains absolute. The EKS cluster must be destroyed via `terraform destroy` (from the bastion, to properly tear down Helm releases) at the end of every active session.

---

## 3. Known Bug Classes & Workarounds

### The Placeholder-Substitution Bug Class

Raw Kubernetes manifests for `task-service` and `notification-service` contained un-interpolated bash-style variables (e.g., `${SQS_QUEUE_URL}`, `${TASK_SERVICE_IRSA_ARN}`, `${NOTIFICATION_SERVICE_IRSA_ARN}`). Applying these directly resulted in AWS STS ValidationErrors because the AWS SDK interpreted the literal string `${TASK_SERVICE_IRSA_ARN}` as a role ARN.

**Current Workaround:**
Deployment requires manual pipeline-style substitution using `envsubst` to inject Terraform outputs before applying:

```bash
export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)
export TASK_SERVICE_IRSA_ARN=$(terraform output -raw task_service_irsa_arn)
export NOTIFICATION_SERVICE_IRSA_ARN=$(terraform output -raw notification_service_irsa_arn)
envsubst < Backend/task-service.yaml | kubectl apply -f -
envsubst < Backend/notification-service.yaml | kubectl apply -f -
```

**Permanent Fix Needed:**
A conversion to **Helm** or Kustomize to handle these dynamic variables cleanly as part of GitOps.

---

## 4. Explicitly Documented Known Limitations

- **Task-Service Authentication:** The `task-service` does not verify JWTs. It is entirely open to the internet via its ingress paths.
- **Auth Token Storage:** The `frontend` application holds JWTs strictly in memory, resetting on every refresh.
- ~~**HTTP-Only Ingress:** The ALB is stripped of ACM certificates and HTTPS redirection to speed up deployments, remaining HTTP-only for the time being.~~ **CLOSED (2026-07-13).** HTTPS restored: ALB now listens on 80 + 443 with the ACM cert for `telos.anshulfml.me` and 301-redirects HTTP → HTTPS. Validated end-to-end (TLS handshake, cert CN/SAN match, redirect) — see [docs/validation/https-cutover.md](../docs/validation/https-cutover.md).

---

## 5. Exact Current Deployment Procedure

To provision from zero to fully operational Phase 2:

1. **Initial Setup (Laptop):**
   - Ensure `terraform.tfvars` has the correct `operator_ip_cidr`.
   - Run `terraform apply` locally. It will build VPC, EKS, Node Groups, Bastion, and ECR, but will fail on `alb-controller`.
2. **Finalize Infra (Bastion):**
   - SSH into the Bastion.
   - Run `terraform apply` from the Bastion to complete the `alb-controller` Helm release.
3. **Database & Secrets (Bastion):**
   - Create `manifests/Database/secrets.yaml` from `secrets.example.yaml` and apply it.
   - Apply Postgres and MongoDB PV/PVC and Deployments (`manifests/Database/*`).
4. **Deploy Services (Bastion):**
   - Export TF variables:
     ```bash
     export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)
     export TASK_SERVICE_IRSA_ARN=$(terraform output -raw task_service_irsa_arn)
     export NOTIFICATION_SERVICE_IRSA_ARN=$(terraform output -raw notification_service_irsa_arn)
     ```
   - Substitute and apply:
     ```bash
     envsubst < Backend/task-service.yaml | kubectl apply -f -
     envsubst < Backend/notification-service.yaml | kubectl apply -f -
     kubectl apply -f Frontend/deployment.yaml
     kubectl apply -f ingress.yaml
     ```

---

## 6. What Remains from the Original Roadmap

The architectural foundation is now complete. The remaining phases are strictly focused on operational maturity and deployment automation:

- **Phase 3 (Jenkins CI):** Stand up Jenkins, build shared library, implement scanning (Gitleaks, Semgrep, Trivy) and auto-push to ECR/GitOps repo.
- **Phase 4 (ArgoCD GitOps):** Install ArgoCD, establish app-of-apps pattern, demonstrate drift correction, and eliminate manual `kubectl apply` commands.
- **Phase 5 (Observability):** Deploy `kube-prometheus-stack` and Loki, instrument services, and build Grafana dashboards/alerts.

---

## 7. Priority "What To Do Next" List

This combines the next logical roadmap step with technical debt surfaced during Phase 2:

1. **Helm Conversion (Automation Debt):** Convert the plain YAML manifests into Helm charts to permanently fix the placeholder-substitution bug class and eliminate the `envsubst` workaround.
2. **Wrapper Script (Automation Debt):** Create a `deploy.sh` wrapper script to automate the cumbersome multi-step export and apply process for local testing.
3. **External Secrets Operator:** Replace the manual, error-prone `secrets.yaml` creation step by using ESO (or Sealed Secrets) for cluster secret management.
4. **End-to-End Notification Validation:** Explicitly test the notification pipeline post-IRSA-fix by triggering the flow and watching `notification-service` logs, as it is the most fragile piece.
5. ~~**Restore HTTPS:** Request a new ACM certificate (or retrieve the existing one) and re-enable HTTPS listeners on the ALB ingress.~~ **DONE (2026-07-13).** ACM cert wired; ALB serves 80 + 443 with HTTP → HTTPS 301 redirect. Validated — see [docs/validation/https-cutover.md](../docs/validation/https-cutover.md).
6. **Commence Phase 3 (Jenkins CI):** Begin scaffolding the Jenkins server and pipelines as defined in the roadmap.

## 8. Tech Debt Clearing Session (2026-07-11) — Status

### Completed

1. **Helm Conversion**: Raw manifests converted to Helm chart at manifests/helm/telos/ — one template per service (auth-service, task-service, notification-service, frontend, database/mongo, database/postgres, ingress, namespace). Placeholders (${SQS*QUEUE_URL} etc.) replaced with terraformOutputs: values block, mapped to actual TF output names (task_service_irsa_role_arn, notification_service_irsa_role_arn — note the \_role* segment). Added \_helpers.tpl `telos.assertNoPlaceholder` guard that hard-fails render on any leftover ${...}. Fixed a pre-existing bug: Postgres PVC was missing storageClassName: "" (was binding via default StorageClass instead of the intended hostPath PV) — now pinned to match Mongo's binding behavior.
2. **deploy.sh wrapper**: Created at repo root. Bastion-only guard (fails early if EKS API unreachable). Pulls terraform outputs into gitignored generated-values.yaml. Validates via helm template + placeholder guard before applying. Supports --dry-run and --destroy. Prints post-deploy checklist.
3. **E2E Notification Pipeline Validation**: Full task.created -> SQS -> notification-service -> MongoDB -> GET /api/notifications flow validated live on cluster. All 6 steps passed, zero errors. Logged at docs/validation/e2e-notification-pipeline.md.
4. **HTTPS/ACM wiring (code complete, NOT yet deployed)**: ACM cert issued — arn:aws:acm:ap-south-1:632377784699:certificate/cbe8b152-372d-47d9-b6bb-74df194e4c81
   Chart updated: ingress.tls block in values.yaml (enabled, certificateArn, sslRedirectPort), conditional listen-ports/certificate-arn/ssl-redirect annotations in ingress.yaml, values.schema.json updated, deploy.sh sources CERTIFICATE_ARN env var. Code is committed and pulled onto bastion but **deployment has not succeeded yet** (see blocker below).

### Discovered issue: Helm missing from bastion

Bastion ($(terraform output -raw bastion_instance_id)) lost helm despite cluster being continuously live — root cause: helm was manually installed in an earlier ad-hoc session and was never part of IaC bootstrap (user_data.sh.tftpl only installs kubectl/aws-cli/git/terraform). If the bastion instance itself is ever replaced (independent of cluster uptime), manually-installed tools are lost.
**Fix applied**:

- terraform/modules/bastion/user_data.sh.tftpl updated to install Helm v3.15.4 in bootstrap (not yet applied via terraform — would require bastion replacement, deferred to next legitimate infra change).
- Helm v3.15.4 manually reinstalled on current running bastion at /usr/local/bin to unblock immediate work.

### Blocker — RESOLVED (2026-07-13)

The anticipated adoption conflict **did not occur**. The `telos` namespace was
**empty** at the start of this session (fresh cluster — nodes ~75 min old, ALB
controller freshly deployed), so option (b)/adoption was moot and option (a) was
effectively already the starting state. There were **no pre-existing manually-applied
resources** for Helm to fight over.

Instead, the first real `./deploy.sh` surfaced **two latent chart/wrapper bugs**,
both now fixed and validated by a clean teardown + redeploy:

1. **Namespace double-ownership.** The chart shipped its own
   `templates/namespace.yaml` **and** `deploy.sh` passed `--create-namespace`.
   Helm's `--create-namespace` pre-creates the namespace *without* release
   ownership metadata, which then collides with the chart's own Namespace object
   → release marked `failed` (`namespaces "telos" already exists`), even though
   the workloads themselves came up. **Fix:** removed `templates/namespace.yaml`;
   the namespace is created solely by `--create-namespace`. (Helm must have the
   namespace exist to store its release Secret, so the chart cannot own it — a
   chart-creates-its-own-install-namespace anti-pattern.)

2. **Non-deterministic hostPath PV binding.** `mongo-pv` (1Gi) and `postgres-pv`
   (5Gi) both used `storageClassName: ""` with no `claimRef`/selector, so binding
   was by size/access-mode only. Mongo's 1Gi claim is satisfiable by *either* PV
   and once grabbed the 5Gi `postgres-pv`, stranding the 5Gi
   `postgres-volume-claim` with only a 1Gi PV available → Postgres stuck
   `Pending`, `deploy.sh --wait` timed out. This was a coin-flip: an earlier
   attempt happened to bind correctly by luck. **Fix:** added a `claimRef` to each
   PV template pinning it to its specific PVC (exclusive, order-independent
   binding). Note: this is distinct from — and supersedes — the earlier
   `storageClassName: ""` fix in Completed §1, which addressed dynamic-provisioner
   binding but not the two-identical-PVs race.

> These two fixes live in the bastion working tree only (`manifests/helm/telos/templates/database/mongo.yaml`, `.../postgres.yaml` modified; `.../namespace.yaml` deleted) and are **not yet committed** — commit/push before the bastion is replaced or the repo re-cloned, or they will be lost.

### HTTPS verification — DONE (2026-07-13)

- ✅ `https://telos.anshulfml.me` serves a valid cert (CN + SAN match, issuer Amazon RSA 2048 M01), HTTP/2 200.
- ✅ HTTP → HTTPS 301 redirect (`Location: https://telos.anshulfml.me:443/`).
- ✅ `kubectl describe ingress mainlb -n telos` shows `listen-ports: [{"HTTP":80},{"HTTPS":443}]` + cert-arn + ssl-redirect.
- ✅ `docs/validation/https-cutover.md` written (TLS handshake, cert CN/SAN, redirect evidence).
- ✅ "HTTP-Only Ingress" limitation closed in §4 and §7 above.

### Standing operational notes for any LLM resuming this project

- EKS API is PRIVATE ONLY. No local kubectl access is possible, ever.
- All kubectl/helm/terraform commands MUST run inside the bastion via:
  `aws ssm start-session --region ap-south-1 --target $(terraform output -raw bastion_instance_id) --profile mir-first`
- Once connected, run all kubectl/helm/git commands as `ssm-user`, not root:
  `sudo -iu ssm-user`
  (root has no kubeconfig; ssm-user owns /home/ssm-user/.kube/config and the repo clone at /home/ssm-user/TELOS)
- Bastion repo clone can go stale — always `git pull` (with `git config --global --add safe.directory /home/ssm-user/TELOS` if needed) before assuming local edits are present on the bastion.
- Bastion-installed tooling not in user_data.sh.tftpl is NOT guaranteed to survive bastion replacement — verify tool availability at start of each session rather than assuming continuity from cluster uptime.
