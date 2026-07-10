#!/usr/bin/env bash
###############################################################################
# TELOS — deploy.sh
# -----------------------------------------------------------------------------
# One-shot deploy wrapper for the Helm chart at manifests/helm/telos/.
# Replaces the old `export ... ; envsubst < *.yaml | kubectl apply` dance
# (see plan/phase2.md §3).
#
# BASTION-ONLY. The EKS API endpoint is PRIVATE, so this script must run from
# inside the VPC (the bastion). It fails early if the cluster API is not
# reachable from where it is invoked.
#
# What it does:
#   1. Sanity-checks tools + that we can reach the private EKS API.
#   2. Reads the dynamic values from `terraform output` (SQS URL + IRSA ARNs)
#      and the ACM cert ARN from the CERTIFICATE_ARN env var (not a TF output;
#      see plan/phase2.md — HTTPS restore). Empty CERTIFICATE_ARN => HTTP-only.
#   3. Writes a gitignored generated-values.yaml.
#   4. Validates it via `helm template` (trips the chart's assertNoPlaceholder
#      guard if any ${...} placeholder survived).
#   5. `helm upgrade --install telos ... -n telos --create-namespace`.
#   6. Prints a post-deploy checklist.
#
# Flags:
#   --dry-run    Render only (helm template). No cluster writes.
#   --destroy    `helm uninstall telos` (+ reminder about cluster-scoped PVs).
#   -h|--help    Usage.
#
# Prereqs: `terraform apply` for terraform/envs/dev already done (this session),
#          helm + kubectl on PATH, kubeconfig pointing at telos-cluster.
###############################################################################
set -euo pipefail

# --- Config (override via env) ----------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/terraform/envs/dev}"
CHART_DIR="${CHART_DIR:-${REPO_ROOT}/manifests/helm/telos}"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/generated-values.yaml}"
RELEASE="${RELEASE:-telos}"
NAMESPACE="${NAMESPACE:-telos}"
KUBE_TIMEOUT="${KUBE_TIMEOUT:-10s}"
# ACM certificate ARN for the ALB HTTPS listener (telos.anshulfml.me). This is
# NOT a terraform-managed resource, so it cannot be read from `terraform output`
# — supply it via the CERTIFICATE_ARN env var (or edit the default below).
# When empty the chart falls back to the old HTTP-only ingress.
CERTIFICATE_ARN="${CERTIFICATE_ARN:-arn:aws:acm:ap-south-1:632377784699:certificate/cbe8b152-372d-47d9-b6bb-74df194e4c81}"

# --- Pretty output ----------------------------------------------------------
step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

MODE="deploy"

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<EOF

Usage: ./deploy.sh [--dry-run | --destroy | -h]

  (no flag)   Full deploy: read terraform outputs -> generated-values.yaml ->
              helm upgrade --install.
  --dry-run   helm template only; writes generated-values.yaml but does NOT
              touch the cluster.
  --destroy   helm uninstall ${RELEASE} from namespace ${NAMESPACE}.
  -h, --help  This help.
EOF
}

# --- Parse args -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --destroy) MODE="destroy"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

# --- Preflight: required tools ----------------------------------------------
step "Preflight — checking required tools"
for bin in helm kubectl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found on PATH."
  ok "$bin: $(command -v "$bin")"
done
# terraform is only needed when we have to read outputs (deploy / dry-run).
if [[ "$MODE" != "destroy" ]]; then
  command -v terraform >/dev/null 2>&1 || die "'terraform' not found on PATH."
  ok "terraform: $(command -v terraform)"
  [[ -d "$TF_DIR" ]] || die "Terraform dir not found: $TF_DIR"
fi
[[ -d "$CHART_DIR" ]] || die "Chart dir not found: $CHART_DIR"

# --- Preflight: bastion / private EKS API reachability ----------------------
# The cluster endpoint is private (plan/phase2.md §2.1). From a laptop this call
# times out; from the bastion it returns 'ok'. This is our "are we on the
# bastion?" gate.
step "Preflight — verifying EKS API is reachable (bastion context)"
if ! kubectl version -o yaml --request-timeout="$KUBE_TIMEOUT" >/dev/null 2>&1; then
  cat >&2 <<EOF
Could not reach the Kubernetes API within ${KUBE_TIMEOUT}.

The TELOS EKS endpoint is PRIVATE — this script must run from the bastion
(inside the VPC), with a kubeconfig pointing at the cluster. Typical fixes:

  * SSH into the bastion and run this script there.
  * Refresh kubeconfig on the bastion:
      aws eks update-kubeconfig --name telos-cluster --region ap-south-1
EOF
  die "EKS API not reachable — refusing to continue (not on bastion?)."
fi
API_HOST="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo '?')"
ok "Reached cluster API: ${API_HOST}"

# --- Destroy path -----------------------------------------------------------
if [[ "$MODE" == "destroy" ]]; then
  step "Destroy — uninstalling Helm release '${RELEASE}' from namespace '${NAMESPACE}'"
  if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
    helm uninstall "$RELEASE" -n "$NAMESPACE"
    ok "Release '${RELEASE}' uninstalled."
  else
    info "No Helm release named '${RELEASE}' in namespace '${NAMESPACE}' — nothing to uninstall."
  fi
  cat <<EOF

Note: cluster-scoped hostPath PVs are NOT removed by 'helm uninstall'. If you
want a clean slate for the databases:

    kubectl delete pv mongo-pv postgres-pv

Full session teardown is still 'terraform destroy' from the bastion.
EOF
  ok "Destroy complete."
  exit 0
fi

# --- Read terraform outputs -------------------------------------------------
step "Reading dynamic values from terraform outputs ($TF_DIR)"
tf_out() {
  # $1 = output name. Fails loudly if the output is missing/empty.
  local name="$1" val
  val="$(terraform -chdir="$TF_DIR" output -raw "$name" 2>/dev/null || true)"
  [[ -n "$val" ]] || die "terraform output '$name' is empty/missing. Has 'terraform apply' completed in $TF_DIR?"
  printf '%s' "$val"
}

SQS_QUEUE_URL="$(tf_out sqs_queue_url)"
TASK_IRSA_ARN="$(tf_out task_service_irsa_role_arn)"
NOTIF_IRSA_ARN="$(tf_out notification_service_irsa_role_arn)"

ok "sqs_queue_url                    = ${SQS_QUEUE_URL}"
ok "task_service_irsa_role_arn       = ${TASK_IRSA_ARN}"
ok "notification_service_irsa_role_arn = ${NOTIF_IRSA_ARN}"

# --- ACM certificate (HTTPS) ------------------------------------------------
# Not a terraform output — sourced from the CERTIFICATE_ARN env var / default.
if [[ -n "$CERTIFICATE_ARN" ]]; then
  ok "certificate_arn (ACM, env)       = ${CERTIFICATE_ARN}"
  TLS_ENABLED="true"
else
  info "CERTIFICATE_ARN empty — ingress will deploy HTTP-only (no HTTPS listener)."
  TLS_ENABLED="false"
fi

# --- Generate values file ---------------------------------------------------
step "Writing generated values file -> ${VALUES_FILE}"
cat > "$VALUES_FILE" <<EOF
# ============================================================================
# GENERATED by deploy.sh — DO NOT EDIT, DO NOT COMMIT (see .gitignore).
# Sourced from: terraform -chdir=${TF_DIR} output  +  CERTIFICATE_ARN env var
# Regenerate:   ./deploy.sh   (or ./deploy.sh --dry-run)
# ============================================================================
terraformOutputs:
  sqsQueueUrl: "${SQS_QUEUE_URL}"
  taskServiceIrsaArn: "${TASK_IRSA_ARN}"
  notificationServiceIrsaArn: "${NOTIF_IRSA_ARN}"
ingress:
  tls:
    enabled: ${TLS_ENABLED}
    certificateArn: "${CERTIFICATE_ARN}"
EOF
ok "Wrote $(wc -l < "$VALUES_FILE") lines."

# --- Validate (trips the chart's assertNoPlaceholder guard) -----------------
step "Validating chart render with generated values"
if ! helm template "$RELEASE" "$CHART_DIR" -f "$VALUES_FILE" -n "$NAMESPACE" >/dev/null 2>/tmp/telos-helm-tmpl.err; then
  echo "---- helm template output ----" >&2
  cat /tmp/telos-helm-tmpl.err >&2
  die "Chart failed to render. If the message above mentions a literal \${...} placeholder, a terraform output did not resolve."
fi
ok "Render OK — no unresolved placeholders."

# --- Dry-run stops here -----------------------------------------------------
if [[ "$MODE" == "dry-run" ]]; then
  step "Dry-run — rendered manifests (helm template)"
  helm template "$RELEASE" "$CHART_DIR" -f "$VALUES_FILE" -n "$NAMESPACE"
  echo
  ok "Dry-run complete. No changes were applied to the cluster."
  info "generated-values.yaml left in place: ${VALUES_FILE}"
  exit 0
fi

# --- Deploy -----------------------------------------------------------------
step "Deploying — helm upgrade --install '${RELEASE}'"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  -f "$VALUES_FILE" \
  -n "$NAMESPACE" --create-namespace \
  --wait --timeout 5m
ok "Helm release '${RELEASE}' applied."

# --- Post-deploy checklist --------------------------------------------------
INGRESS_HOST="$(helm get values "$RELEASE" -n "$NAMESPACE" -a -o json 2>/dev/null \
  | grep -o '"host":"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
INGRESS_HOST="${INGRESS_HOST:-telos.anshulfml.me}"

cat <<EOF

$(printf '\033[1;32m========================================================================\033[0m')
$(printf '\033[1;32m  TELOS deploy complete — post-deploy checklist\033[0m')
$(printf '\033[1;32m========================================================================\033[0m')

  1. Pods (wait for all Running / Ready):
       kubectl get pods -n ${NAMESPACE}

  2. Ingress / ALB address (grab the ADDRESS column, may take ~1-2 min):
       kubectl get ingress mainlb -n ${NAMESPACE}
       kubectl describe ingress mainlb -n ${NAMESPACE}   # confirm 80 + 443 listeners
     App URL (HTTPS): https://${INGRESS_HOST}/
     HTTP should 301 -> HTTPS:  curl -sI http://${INGRESS_HOST}/

  3. Confirm IRSA annotations landed on the SQS service accounts:
       kubectl get sa task-service notification-service -n ${NAMESPACE} \\
         -o jsonpath='{range .items[*]}{.metadata.name}{"\\t"}{.metadata.annotations.eks\\.amazonaws\\.com/role-arn}{"\\n"}{end}'

  4. Tail the notification-service log (watch SQS events get consumed):
       kubectl logs -n ${NAMESPACE} -l app=notification-service -f --tail=50

  5. End-to-end smoke test: register -> login -> create a task, then confirm
     it shows up at http://${INGRESS_HOST}/api/notifications

  Teardown for this release:  ./deploy.sh --destroy
EOF
