# ThreeTierLab → Full DevOps Platform: Master Plan

**Owner:** Mir (Anshul Singh Chauhan)
**Purpose:** Blueprint for expanding ThreeTierLab from a static 3-tier EKS app into a full DevOps portfolio platform — Terraform IaC, async microservices, Jenkins CI, ArgoCD CD, Prometheus/Grafana/Loki observability.
**Primary goal:** DevOps proof-of-work for Junior DevOps / Cloud Engineer applications. Service code quality is secondary — pipeline, infra, and ops maturity is what's being sold.
**Constraints locked in for this plan:** $115 AWS credit, project will NOT run continuously for a month, free-tier instance-type/quota limits apply. Every phase below is designed to be built, demoed, screenshotted, and torn down — not left running.

---

## 0. Ground rules before touching anything

1. **This is a burst project, not an always-on service.** Budget every phase in hours of cluster uptime, not calendar days. Build → validate → capture proof (screenshots, terminal recordings, Grafana dashboards, `kubectl get all` outputs) → `terraform destroy`. Never leave EKS running overnight by accident — it is the single biggest way to burn the $115.
2. **Everything must be reproducible from Terraform in one `apply`.** If you can't destroy and rebuild the whole stack in under 30 minutes, the "IaC" claim on your resume is weak. Treat rebuild speed as a hard requirement, not a nice-to-have.
3. **Free-tier and quota reality check (do this before Phase 1):**
   - EKS control plane is **never free-tier** — flat ~$0.10/hr (~$73/month if left running). Your $115 buys ~1,150 hours (~48 days) of _control plane alone_ if nothing else ran — but node EC2, NAT Gateway, EBS volumes, and data transfer all stack on top. Realistic all-in burn rate with 3-4 small nodes + NAT + EBS is closer to $0.30-0.50/hr while running. Plan sessions of 3-5 hours, not "leave it up for a weekend."
   - NAT Gateway is billed hourly + per-GB regardless of free tier (~$0.045/hr + data). This is often the silent budget killer people forget about. Consider a single NAT Gateway (not one per AZ) for this project — you don't need multi-AZ HA for a portfolio piece.
   - Default AWS account vCPU quotas for on-demand instances are often low (e.g., 5-32 vCPUs depending on account history). Running EKS nodes + Jenkins EC2 + bastion simultaneously can hit this. Check `Service Quotas → EC2 → Running On-Demand Standard instances` before Phase 1 and request an increase early (approval can take a day) if you're near the limit.
   - Stick to `t3.small`/`t3.medium` for nodes and `t3.micro`/`t3.small` for Jenkins/bastion. Avoid anything bigger unless a specific step (e.g. running the full observability stack) genuinely needs it.
   - **Use Spot for worker nodes** where the workload tolerates interruption (everything except maybe the observability node group) — meaningfully stretches the credit.
4. **One Terraform apply = one billable session.** Get in the habit of: `terraform apply` → do the work for that phase → capture artifacts → `terraform destroy`. Keep a running note of `$ spent so far` after each session (even a rough estimate) so you don't get a surprise bill.

---

## 1. Target architecture (end state)

```
                                   ┌─────────────────────────────┐
                                   │   Route53 / DNS (existing)  │
                                   └───────────────┬─────────────┘
                                                    │
                                        ┌───────────▼───────────┐
                                        │   ALB (ACM TLS term.)  │
                                        └───────────┬───────────┘
                                                    │
                              ┌─────────────────────▼─────────────────────┐
                              │            EKS Ingress → Gateway            │
                              │     (nginx/ALB ingress routes by path)     │
                              └───────┬───────────────────┬────────────────┘
                                      │                   │
                         ┌────────────▼───────┐  ┌────────▼──────────┐
                         │   frontend (React)  │  │   auth-service     │
                         │   node group: app    │  │   node group: app  │
                         └──────────┬───────────┘  └────────┬───────────┘
                                    │                        │  (Postgres, own DB)
                        ┌───────────▼────────────┐           │
                        │      task-service        │◄─────────┘ (JWT verify)
                        │  node group: db-api       │
                        │  (Mongo, own DB — existing│
                        │   backend logic reused)   │
                        └───────────┬───────────────┘
                                    │  publishes "task.created" / "task.completed"
                                    ▼
                           ┌──────────────────┐
                           │   SQS Queue        │  ← async boundary (kept deliberately simple)
                           └────────┬───────────┘
                                    ▼
                        ┌───────────────────────────┐
                        │   notification-service      │
                        │   node group: app            │
                        │   (consumes SQS, logs/writes │
                        │   a notification record)     │
                        └───────────────────────────┘

   Observability (separate node group or same "platform" group):
   Prometheus + Grafana + Loki/Promtail + Alertmanager — scrape all above, dashboards + alerts

   CI/CD:
   Jenkins (EC2 or in-cluster) → build/scan/sign/push each service → updates GitOps repo
   ArgoCD (in-cluster) → watches GitOps repo → syncs to EKS
```

### Why this shape

- **Async boundary is exactly one hop** (task-service → SQS → notification-service). This is intentionally the _only_ async piece — enough to legitimately say "event-driven microservices" in an interview, without needing a message broker you have to self-host, tune, and debug (Kafka/RabbitMQ would be significant extra ops surface for close to zero extra resume value at this stage).
- **SQS over self-hosted broker**: managed, near-zero idle cost, no extra pod to keep healthy, and it's a real AWS service you can speak to (IAM policy for queue access, DLQ configuration, visibility timeout tuning) — all good interview material.
- **auth-service gets its own datastore (Postgres via RDS free-tier `db.t3.micro`, or even simpler: Postgres as a pod with a PVC if you want to avoid another AWS bill line)**. Decision point below.
- **task-service is your existing backend, minimally modified** — you are not rewriting business logic, you're extracting it into a clearly-bounded service and adding an SQS publish call on task create/complete. This keeps "DevOps work" the majority of the effort, per your priority.

### Decision point: Postgres for auth-service — RDS vs in-cluster

| Option                                                      | Pros                                                         | Cons                                                                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| RDS `db.t3.micro` (free tier eligible if <12mo old account) | Real managed-DB experience, IAM auth option, resume-relevant | Another resource to remember to destroy; free tier only applies if account is within first 12 months |
| Postgres pod + PVC in-cluster                               | Zero extra AWS billing surface, simpler teardown             | hostPath/EBS PVC lifecycle to manage yourself; less "real world" but still fine for a portfolio      |

**Recommendation:** Start with **in-cluster Postgres** (matches your existing hostPath/PVC pattern from Mongo, keeps everything torn down by one `terraform destroy` + `kubectl delete`). Migrate to RDS only if you specifically want an RDS bullet point later — treat it as a Phase 7 stretch goal, not a blocker.

---

## 2. Microservice boundaries (final)

1. **auth-service**
   - Owns: user records, password hashing, JWT issuing/verification
   - Datastore: Postgres (in-cluster pod, see above)
   - Exposes: `POST /auth/register`, `POST /auth/login`, `GET /auth/verify`
   - Kept intentionally minimal — this service exists to prove the _pattern_ (separate datastore, separate deploy, separate scaling), not to be a feature-complete auth system

2. **task-service** (your current backend, extracted)
   - Owns: task CRUD — this is your existing `backend/` code almost as-is
   - Datastore: MongoDB (already have this working — reuse the manifests)
   - New addition: on task create/complete, publish a message to SQS (`{ taskId, event, timestamp }`)
   - Exposes: existing `/api/tasks` routes, now behind gateway auth check

3. **notification-service**
   - Owns: consuming the SQS queue, doing _something_ observable with each event — simplest defensible version: log it structured + write a row to a small "notifications" table/collection (reuse Mongo or a lightweight SQLite/Postgres table) so you can show a `/notifications` endpoint proving consumption happened
   - This is the smallest service by design — its entire purpose is to demonstrate the async consumer pattern, health probes, and independent scaling (HPA scaling on queue depth is a great advanced demo if you get to it — see Phase 7)

4. **frontend** — mostly unchanged, but now calls auth-service for login and task-service for tasks (behind the gateway/ingress path routing)

**Explicitly not doing:** API gateway as its own custom service, service mesh (Istio/Linkerd), gRPC, Kafka. All of these add real ops complexity for comparatively low incremental portfolio value at your current stage — call them out as "future work" in your README instead, which itself is a good interview talking point ("I scoped this deliberately, here's what I'd add next and why").

---

## 3. Target repo/directory structure

Your current single repo becomes a multi-repo GitOps setup. Recommended split:

```
three-tier-lab/                  (existing repo, becomes the "app monorepo")
├── services/
│   ├── auth-service/
│   ├── task-service/            ← current backend/ moves here almost unchanged
│   └── notification-service/
├── frontend/                    ← unchanged location
├── terraform/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks/
│   │   ├── node-groups/
│   │   ├── ecr/
│   │   ├── iam/
│   │   ├── alb-controller/
│   │   ├── bastion/
│   │   └── sqs/
│   ├── envs/
│   │   └── dev/                 ← only one env needed for a portfolio project
│   └── bootstrap/                ← S3 backend + DynamoDB lock table (created once, manually, before everything else)
├── jenkins/
│   ├── Jenkinsfile.auth-service
│   ├── Jenkinsfile.task-service
│   ├── Jenkinsfile.notification-service
│   ├── Jenkinsfile.terraform
│   └── shared-library/           ← common pipeline steps (scan, build, push) as a Jenkins shared library
├── observability/
│   ├── prometheus-values.yaml
│   ├── loki-values.yaml
│   └── grafana-dashboards/
└── README.md

three-tier-lab-gitops/            (NEW, separate repo — ArgoCD watches this one)
├── apps/
│   ├── root-app.yaml             ← app-of-apps entrypoint
│   ├── auth-service/
│   ├── task-service/
│   ├── notification-service/
│   ├── frontend/
│   └── observability/
└── base/ + overlays/dev/          ← Kustomize structure per service
```

**Why two repos:** this is the single clearest "I understand GitOps" signal you can put on a resume — separating "code + CI" from "desired cluster state." Jenkins never touches the cluster directly; it only ever updates an image tag in the GitOps repo. ArgoCD is the only thing with cluster-write access from a pipeline perspective.

---

## 4. Phased build plan

Each phase lists: what you build, in what order, roughly how long a session should take, and what "done" looks like for your resume/portfolio. Phases are designed to be independently demoable — you can stop after any phase and already have something to show.

### Phase 0 — Repo restructure (no AWS cost, do this locally)

- Split `backend/` into `services/task-service/`, scaffold `services/auth-service/` and `services/notification-service/`
- Update Dockerfiles per service, get all three building and running locally via `docker-compose` (add a `docker-compose.yml` for local dev — this also gives you a fast local loop so you're not burning AWS credits just to test service wiring)
- **Done when:** all three services + frontend run together locally via `docker-compose up`, task creation flows through to a visible "notification logged" output, using a local SQS-compatible stub (e.g. LocalStack) or just a temporary real SQS queue (SQS itself costs pennies even active — this is not the expensive part)

### Phase 1 — Terraform: codify what already exists

- Write Terraform for your **current, already-working** infra first: VPC, subnets, IGW/NAT, EKS cluster, the two node groups (with taints/labels), ECR repos, ACM cert reference, bastion, IAM roles/policies, security groups
- No architecture changes yet — the goal is proving you can `destroy` and `apply` your _existing_ app identically
- Remote state: create the S3 bucket + DynamoDB lock table manually once (`terraform/bootstrap/`, run outside normal apply/destroy cycle — this is the one thing that persists across sessions, and it costs essentially nothing idle)
- **Done when:** `terraform apply` from empty account brings up the exact current 3-tier app end to end, `terraform destroy` tears it back down cleanly, and you can screenshot a full `apply` run for your portfolio

### Phase 2 — Microservice cutover on real infra

- Deploy the 3 services + frontend via plain manifests first (not ArgoCD yet — keep one variable changing at a time)
- Add the SQS queue via Terraform (`modules/sqs/`), wire IAM policy for task-service (publish) and notification-service (consume) via IRSA
- Update Ingress rules for new path-based routing (`/api/auth`, `/api/tasks`, frontend at `/`)
- **Done when:** you can register a user, log in, create a task, and see the notification-service log/record the event — full request flow across 3 real services on EKS

### Phase 3 — Jenkins CI with security hardening

- Stand up Jenkins (either on a small EC2 instance in the same VPC, or as an in-cluster deployment via the Kubernetes plugin — EC2 is simpler to reason about for a first pass, in-cluster is more "cloud-native" if you want the extra credit)
- Build the shared library with reusable stages: checkout → secret scan (gitleaks) → SAST (Semgrep) → dependency audit (npm audit) → unit tests → build image → image scan (Trivy, fail on HIGH/CRITICAL) → sign (cosign) → push to ECR → bump tag in GitOps repo
- Per-service Jenkinsfile just calls the shared library with service-specific params
- **Done when:** a commit to any service triggers its pipeline, a deliberately-introduced vulnerable dependency gets caught and fails the build (screenshot this — it's a great portfolio artifact), and a clean commit results in the GitOps repo being auto-updated

### Phase 4 — ArgoCD GitOps cutover

- Install ArgoCD in-cluster, point it at `three-tier-lab-gitops` repo
- Set up app-of-apps: one root Application managing child Applications for each service + observability
- Enable auto-sync + self-heal; demonstrate drift correction (manually `kubectl edit` a deployment, show ArgoCD reverting it — another great screenshot/demo moment)
- Lock down ArgoCD UI access behind the bastion/port-forward, not a public LB
- **Done when:** the only way changes reach the cluster is via a merge to the GitOps repo; manual kubectl is "break-glass only" and you can articulate why

### Phase 5 — Observability

- `kube-prometheus-stack` via Helm (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics)
- Loki + Promtail (or Grafana Alloy) for logs
- Instrument each service with a `/metrics` endpoint (prom-client for Node services) — this is the one piece of actual application code you'll touch in this phase
- Build 2 Grafana dashboards minimum: (1) per-service request rate/latency/error rate, (2) cluster health (node CPU/mem, HPA scaling events, pod restarts)
- Alertmanager rule set: pod crash-looping, HPA maxed at ceiling, high 5xx rate, node disk pressure — route to a webhook or email
- **Done when:** you can trigger a synthetic failure (kill a pod, spike load with a quick load-test script) and watch it show up in Grafana + fire an alert — record this as a short demo clip, it's extremely strong interview material

### Phase 6 — Documentation & portfolio packaging

- Update root `README.md` with the full architecture diagram (regenerate from `plan.md` once built), a "what I'd do differently at scale" section, and a clear list of what's deliberately out of scope and why
- Write a one-page "runbook": how to bring the whole stack up from zero and tear it down (this doubles as your own operational memory and as an artifact you can literally show in an interview)
- Capture all screenshots/recordings gathered in Phases 1-5 into a `docs/portfolio/` folder or a short write-up (blog-post style) — this is what actually gets read by recruiters/interviewers, more than the code itself

---

## 5. Session/cost budgeting cheat sheet

Rough guide — validate actual costs in AWS Cost Explorer after your first session and adjust:

| Phase | Approx session length          | What's running                                               | Rough hourly burn |
| ----- | ------------------------------ | ------------------------------------------------------------ | ----------------- |
| 0     | N/A (local only)               | Docker Compose locally                                       | $0                |
| 1     | 2-3 hrs                        | EKS + VPC + NAT + bastion, no extra workloads                | ~$0.20-0.25/hr    |
| 2     | 3-4 hrs                        | Phase 1 + 3 services + SQS                                   | ~$0.25-0.30/hr    |
| 3     | 3-5 hrs (spread over sessions) | Phase 2 + Jenkins EC2                                        | ~$0.30-0.35/hr    |
| 4     | 2-3 hrs                        | Phase 2 + ArgoCD (drop Jenkins EC2 if idle between sessions) | ~$0.28-0.32/hr    |
| 5     | 3-4 hrs                        | Everything + Prometheus/Grafana/Loki (heavier EBS use)       | ~$0.40-0.50/hr    |

**Practical habit:** destroy Jenkins EC2 between CI sessions (rebuild is a 10-minute `terraform apply` if it's properly modularized) — it's the one component with no reason to persist across sessions once the shared library is written and version-controlled.

---

## 6. Risks and things that will likely go wrong

- **Cost creep from forgetting to destroy.** Set a phone reminder at the start of every session. This is the single most common way portfolio projects like this blow past a credit budget.
- **NAT Gateway + EBS volumes are the "invisible" cost lines** people forget when estimating — they don't show up as dramatically as EC2/EKS but add up over multi-hour sessions, especially once Prometheus/Loki are creating persistent volumes.
- **vCPU/quota limits** blocking a node group scale-up mid-demo — check quotas before Phase 1, not during.
- **SQS IAM permissions (IRSA) are a common stumbling block** — budget extra time in Phase 2 for getting the service account → IAM role trust relationship right; this is a very common real-world debugging exercise, so it's fine (even good) if it takes a couple of iterations.
- **Jenkins-to-ArgoCD handoff bugs** — a classic mistake is Jenkins pushing an image tag update to the GitOps repo in a format ArgoCD's Kustomize/Helm overlay doesn't actually read (wrong path, wrong key). Test this handoff with a trivial no-op change before wiring the full pipeline.
- **Observability resource hunger** — kube-prometheus-stack's defaults are tuned for real clusters, not 2-4 node t3.small setups. You will likely need to reduce Prometheus retention, resource requests, and scrape frequency to fit your node budget — this itself is a legitimate "right-sizing observability for constrained environments" story for an interview.
- **Scope creep is the biggest risk to actually finishing.** The plan above deliberately excludes service mesh, Kafka, multi-env (staging/prod), and RDS — resist adding these until Phase 6 is done and documented. A finished, well-documented 6-phase project beats an unfinished 10-phase one every time in an interview.

---

## 7. Stretch goals (only after Phase 6 is fully done and documented)

- HPA scaling notification-service on SQS queue depth (via KEDA) instead of CPU — genuinely impressive, event-driven autoscaling
- Migrate auth-service's Postgres to RDS
- Add distributed tracing (Grafana Tempo or Jaeger) now that there are real cross-service calls worth tracing
- Blue/green or canary rollout via Argo Rollouts instead of plain ArgoCD sync
- Move Terraform state/backend and CI into a proper multi-env (dev/staging) setup if you want to demonstrate promotion workflows

---

_This document is the single source of truth for what gets built and in what order. Update it as decisions change — treat deviations from this plan as something to consciously note (and be ready to explain why) rather than silent drift._
