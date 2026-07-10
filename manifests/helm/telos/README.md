# TELOS Helm chart

Single umbrella chart that deploys the full Phase 2 stack — `auth-service`,
`task-service`, `notification-service`, `frontend`, plus the in-cluster
`mongodb` and `postgres` databases and the ALB ingress.

This chart **replaces the old `envsubst < *.yaml | kubectl apply` workflow**.
The three values that used to be substituted by hand —
`${SQS_QUEUE_URL}`, `${TASK_SERVICE_IRSA_ARN}`, `${NOTIFICATION_SERVICE_IRSA_ARN}` —
are now first-class Helm values under the [`terraformOutputs`](#terraform-sourced-values)
key.

> Persistence is intentionally **unchanged** from Phase 2: Mongo and Postgres
> still use `hostPath` PVs (non-persistent across Spot node churn) — tracked as a
> follow-up in `plan/phase2.md`.
>
> **HTTPS is now restored** (closes the "HTTP-Only Ingress" limitation). The ALB
> terminates TLS with an ACM cert and redirects HTTP→HTTPS. The cert ARN is a
> Helm value (`ingress.tls.certificateArn`) supplied at install time — see
> [TLS / HTTPS](#tls--https) below.

---

## Layout

```
manifests/helm/telos/
├── Chart.yaml
├── values.yaml                # all tunables incl. terraformOutputs:
├── values.schema.json         # validates values on lint/template/install
├── README.md                  # this file
└── templates/
    ├── _helpers.tpl           # labels, image ref, ${...} placeholder guard
    ├── namespace.yaml
    ├── NOTES.txt              # post-install summary
    ├── auth-service.yaml
    ├── task-service.yaml      # IRSA + SQS wired from terraformOutputs
    ├── notification-service.yaml
    ├── frontend.yaml
    ├── ingress.yaml           # ALB, HTTPS (ACM) + HTTP->HTTPS redirect
    └── database/
        ├── mongo.yaml         # Secret + hostPath PV/PVC + Deploy + Svc
        └── postgres.yaml      # hostPath PV/PVC + Deploy + Svc
```

---

## Terraform-sourced values

These **must** be populated before a real install. They map 1:1 to outputs in
`terraform/envs/dev` (run from the bastion, where the state lives for this
session):

| values.yaml key                              | `terraform output -raw ...`            | Old placeholder                    |
| -------------------------------------------- | -------------------------------------- | ---------------------------------- |
| `terraformOutputs.sqsQueueUrl`               | `sqs_queue_url`                        | `${SQS_QUEUE_URL}`                 |
| `terraformOutputs.taskServiceIrsaArn`        | `task_service_irsa_role_arn`           | `${TASK_SERVICE_IRSA_ARN}`         |
| `terraformOutputs.notificationServiceIrsaArn`| `notification_service_irsa_role_arn`   | `${NOTIFICATION_SERVICE_IRSA_ARN}` |

**Behaviour when left empty** (so `helm template`/`lint` still pass with bare
defaults):

- Empty `*IrsaArn` → the ServiceAccount's `eks.amazonaws.com/role-arn`
  annotation is **omitted**. Fine for a dry render, but the pod then has no SQS
  permissions at runtime.
- Empty `sqsQueueUrl` → `SQS_QUEUE_URL` is left unset; the service code
  (`sqs.js` / `consumer.js`) already no-ops with a warning instead of crashing.

**Guard rail:** if any of these is left as a literal `${...}` string (a
copy-paste of the old placeholder), the chart **hard-fails at render time** with
a clear message — this is the exact STS `ValidationError` foot-gun documented in
`plan/phase2.md`, now caught before anything reaches the cluster.

Other secrets (`secrets.mongo.*`, `secrets.auth.jwtSecret`) live under the
`secrets:` key and are still plain values for now — replacing them with External
Secrets Operator / Sealed Secrets is the next debt item in `plan/phase2.md §7`.

---

## TLS / HTTPS

The ALB terminates TLS with an **ACM certificate** and redirects all HTTP
traffic to HTTPS. This is controlled by the `ingress.tls` block:

| values.yaml key                  | Meaning                                                            |
| -------------------------------- | ----------------------------------------------------------------- |
| `ingress.tls.enabled`            | Master switch for HTTPS (default `true`).                          |
| `ingress.tls.certificateArn`     | ACM cert ARN for `telos.anshulfml.me`. **Empty by default.**      |
| `ingress.tls.sslRedirectPort`    | Port the HTTP→HTTPS redirect targets (default `"443"`).           |

When `tls.enabled` is `true` **and** a non-empty `certificateArn` is supplied,
the ingress template emits:

```yaml
alb.ingress.kubernetes.io/certificate-arn: <arn>
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
alb.ingress.kubernetes.io/ssl-redirect: '443'
```

If the ARN is left blank the chart **falls back to HTTP-only**
(`listen-ports: '[{"HTTP": 80}]'`), so `helm template`/`lint` still pass with
bare defaults. A literal `${...}` placeholder in the ARN is **hard-rejected**
at render time by the same guard used for the terraform outputs.

### Why the cert ARN is not in `values.yaml` / terraform

The ACM certificate is **not** a terraform-managed resource in this repo (there
is no `aws_acm_certificate` in `terraform/`, therefore no `terraform output` to
source it from). To avoid baking a single cert ARN permanently into the chart,
it is supplied **at install time** — either:

- `deploy.sh` picks it up from the `CERTIFICATE_ARN` env var (it has the current
  cert ARN as its default), writes it into `generated-values.yaml`, then installs; **or**
- pass it directly on any `helm` invocation:

```bash
helm upgrade --install telos manifests/helm/telos \
  --namespace telos --create-namespace \
  --set ingress.tls.certificateArn="arn:aws:acm:ap-south-1:632377784699:certificate/cbe8b152-372d-47d9-b6bb-74df194e4c81"
```

---

## Install / upgrade from the bastion

Prereqs on the bastion: `helm`, `kubectl` with a working kubeconfig (the bastion
already gets one via user-data), and the `terraform/envs/dev` workspace
initialised so `terraform output` works.

### 1. Populate values from terraform outputs

Two options — pick one.

**Option A — inline `--set` (quickest, nothing written to disk):**

```bash
cd /path/to/telos            # repo root on the bastion
TF=terraform/envs/dev

helm upgrade --install telos manifests/helm/telos \
  --namespace telos --create-namespace \
  --set terraformOutputs.sqsQueueUrl="$(terraform -chdir=$TF output -raw sqs_queue_url)" \
  --set terraformOutputs.taskServiceIrsaArn="$(terraform -chdir=$TF output -raw task_service_irsa_role_arn)" \
  --set terraformOutputs.notificationServiceIrsaArn="$(terraform -chdir=$TF output -raw notification_service_irsa_role_arn)"
```

**Option B — generated overrides file (auditable, reusable):**

```bash
cd /path/to/telos
TF=terraform/envs/dev

cat > /tmp/telos-tf.yaml <<EOF
terraformOutputs:
  sqsQueueUrl: "$(terraform -chdir=$TF output -raw sqs_queue_url)"
  taskServiceIrsaArn: "$(terraform -chdir=$TF output -raw task_service_irsa_role_arn)"
  notificationServiceIrsaArn: "$(terraform -chdir=$TF output -raw notification_service_irsa_role_arn)"
EOF

helm upgrade --install telos manifests/helm/telos \
  --namespace telos --create-namespace \
  -f /tmp/telos-tf.yaml
```

> `--create-namespace` is optional — the chart also renders the `telos`
> Namespace itself. Either works; using both is harmless.

Provide real secrets the same way (don't ship the dev defaults):

```bash
  --set secrets.auth.jwtSecret="$SOME_STRONG_SECRET" \
  --set secrets.mongo.username="$MONGO_USER" \
  --set secrets.mongo.password="$MONGO_PASS"
```

### 2. Verify before applying (recommended)

```bash
# Render locally and eyeball the IRSA annotations + SQS_QUEUE_URL:
helm template telos manifests/helm/telos -f /tmp/telos-tf.yaml | less

# Server-side dry run against the live cluster:
helm upgrade --install telos manifests/helm/telos \
  -n telos -f /tmp/telos-tf.yaml --dry-run=server
```

### 3. Post-install checks

```bash
kubectl -n telos get pods
kubectl -n telos get ingress mainlb          # grab the ALB address
kubectl -n telos get sa task-service notification-service -o \
  jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}{end}'
```

Then walk the end-to-end flow: register a user → log in → create a task →
confirm `notification-service` logs the SQS event and it appears at
`GET /api/notifications`.

---

## Common overrides

| Need                                | Flag                                                        |
| ----------------------------------- | ---------------------------------------------------------- |
| Different ECR account/region        | `--set global.imageRegistry=...` / `--set global.awsRegion=...` |
| Pin a specific image tag            | `--set taskService.image.tag=<sha>`                        |
| Disable a service (e.g. frontend)   | `--set frontend.enabled=false`                             |
| Change ingress host                 | `--set ingress.host=telos.example.com`                     |
| Supply / rotate the ACM cert (HTTPS)| `--set ingress.tls.certificateArn=arn:aws:acm:...`         |
| Disable HTTPS (fall back to HTTP)   | `--set ingress.tls.enabled=false`                          |
| Skip the ECR pull secret on frontend| `--set frontend.imagePullSecret=""`                        |

> The frontend's `imagePullSecret` (`ecr-registry-secret`) is **not** created by
> this chart — it must already exist in the `telos` namespace, exactly as in the
> pre-Helm workflow.

---

## Uninstall

```bash
helm uninstall telos -n telos
# hostPath PVs are cluster-scoped and are NOT garbage-collected by uninstall:
kubectl delete pv mongo-pv postgres-pv
```

Full session teardown remains `terraform destroy` from the bastion (tears down
EKS + Helm-managed ALB controller), per `plan/phase2.md §2.5`.

---

## Validation

```bash
helm lint manifests/helm/telos
helm template telos manifests/helm/telos            # renders with empty defaults
helm template telos manifests/helm/telos \          # renders fully wired
  --set terraformOutputs.sqsQueueUrl=... \
  --set terraformOutputs.taskServiceIrsaArn=... \
  --set terraformOutputs.notificationServiceIrsaArn=...
```

All three pass. `values.schema.json` is enforced automatically on every
lint/template/install.
