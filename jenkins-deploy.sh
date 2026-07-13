#!/usr/bin/env bash
###############################################################################
# TELOS — jenkins-deploy.sh
# -----------------------------------------------------------------------------
# Jenkins CI deployment wrapper. Installs the official jenkins/jenkins Helm
# chart with predefined values and a pre-configured PersistentVolume.
#
# BASTION-ONLY. The EKS API endpoint is PRIVATE.
###############################################################################
set -euo pipefail

# --- Config -----------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/terraform/envs/dev}"
VALUES_TEMPLATE="${REPO_ROOT}/manifests/helm/jenkins-values.yaml"
GENERATED_VALUES="/tmp/jenkins-values-generated.yaml"
PV_MANIFEST="${REPO_ROOT}/manifests/helm/jenkins-pv.yaml"
RELEASE="jenkins"
NAMESPACE="jenkins"
KUBE_TIMEOUT="${KUBE_TIMEOUT:-10s}"

# --- Pretty output ----------------------------------------------------------
step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Parse args -------------------------------------------------------------
MODE="deploy"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destroy) MODE="destroy"; shift ;;
    -h|--help)
      echo "Usage: ./jenkins-deploy.sh [--destroy | -h]"
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# --- Preflight --------------------------------------------------------------
step "Preflight — checking required tools"
for bin in helm kubectl terraform envsubst; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found on PATH."
  ok "$bin: $(command -v "$bin")"
done

step "Preflight — verifying EKS API is reachable (bastion context)"
if ! kubectl version -o yaml --request-timeout="$KUBE_TIMEOUT" >/dev/null 2>&1; then
  cat >&2 <<EOF
Could not reach the Kubernetes API within ${KUBE_TIMEOUT}.
This script must run from the bastion (inside the VPC), with a kubeconfig pointing at the cluster.
EOF
  die "EKS API not reachable — refusing to continue (not on bastion?)."
fi
API_HOST="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo '?')"
ok "Reached cluster API: ${API_HOST}"

# --- Destroy path -----------------------------------------------------------
if [[ "$MODE" == "destroy" ]]; then
  step "Destroy — uninstalling Helm release '${RELEASE}'"
  if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
    helm uninstall "$RELEASE" -n "$NAMESPACE"
    ok "Release '${RELEASE}' uninstalled."
  else
    info "No release '${RELEASE}' found."
  fi
  kubectl delete -f "$PV_MANIFEST" --ignore-not-found
  ok "Destroy complete."
  exit 0
fi

# --- Read terraform outputs -------------------------------------------------
step "Reading dynamic values from terraform outputs ($TF_DIR)"
JENKINS_IRSA_ROLE_ARN="$(terraform -chdir="$TF_DIR" output -raw jenkins_irsa_role_arn 2>/dev/null || true)"
[[ -n "$JENKINS_IRSA_ROLE_ARN" ]] || die "terraform output 'jenkins_irsa_role_arn' is empty/missing. Did you apply terraform?"
ok "jenkins_irsa_role_arn = ${JENKINS_IRSA_ROLE_ARN}"

export JENKINS_IRSA_ROLE_ARN

step "Generating values file"
envsubst < "$VALUES_TEMPLATE" > "$GENERATED_VALUES"
ok "Rendered ${VALUES_TEMPLATE} into ${GENERATED_VALUES}"

# --- Deploy Jenkins ---------------------------------------------------------
step "Applying Jenkins PV"
kubectl apply -f "$PV_MANIFEST"

step "Adding Jenkins Helm repo"
helm repo add jenkins https://charts.jenkins.io
helm repo update jenkins

step "Deploying Jenkins via Helm"
helm upgrade --install "$RELEASE" jenkins/jenkins \
  -n "$NAMESPACE" --create-namespace \
  -f "$GENERATED_VALUES"

# --- Manual Browser Steps Output --------------------------------------------
step "Post-Deploy Checklist & Next Steps"
cat <<EOF
Jenkins deployment initiated! (It may take a few minutes for the pod to become ready).

Because Jenkins is NOT exposed via an external ALB (Phase 3 Spec), you MUST access it via kubectl port-forward from the bastion.

1) Connect to the bastion with local port forwarding:
   aws ssm start-session --region ap-south-1 --target \$(terraform -chdir=$TF_DIR output -raw bastion_instance_id) --profile mir-first \\
     --document-name AWS-StartPortForwardingSessionToRemoteHost \\
     --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
   (Or port-forward from the bastion's own kubectl: kubectl port-forward svc/jenkins -n jenkins 8080:8080)

2) Initial Admin Password Retrieval:
   Run the following on the bastion:
   kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo

3) Manual Browser Steps:
   - Navigate to http://localhost:8080
   - Enter the admin password retrieved above.
   - Proceed with the initial setup wizard. Since 'installPlugins' is configured via values, the necessary plugins (kubernetes, git, workflow-aggregator, configuration-as-code) will be pre-installed.
   - Go to Manage Jenkins -> Configuration as Code to verify JCasC is active.

Note: DO NOT build the shared library or Jenkinsfiles yet. Wait until Jenkins is fully up and running.
EOF
