# Validation — HTTPS/ACM Cutover

**Date:** 2026-07-13 · **Cluster:** telos-cluster (ap-south-1) · **Release:** `telos` (Helm)
**ACM:** `...certificate/cbe8b152-372d-47d9-b6bb-74df194e4c81`
**ALB:** `k8s-telos-mainlb-21227f9266-1834613605.ap-south-1.elb.amazonaws.com`

Closes the "HTTP-Only Ingress" limitation (phase2.md §4/§7). **Result: PASS.**

## Evidence

- **Pods:** all 6 `1/1 Running` (auth, task, notification, frontend, mongodb, postgres).
- **PV binding:** `mongo-volume-claim→mongo-pv (1Gi)`, `postgres-volume-claim→postgres-pv (5Gi)`.
- **IRSA:** annotations present on `task-service` and `notification-service` SAs.
- **Ingress `mainlb`:** `listen-ports: [{"HTTP":80},{"HTTPS":443}]`, cert-arn set, `ssl-redirect: 443`, `SuccessfullyReconciled`.
- **TLS handshake:** `subject: CN=telos.anshulfml.me`, `subjectAltName` matches, issuer `Amazon RSA 2048 M01`, TLSv1.2, HTTP/2, `HTTP/2 200`.
- **Redirect:** `http://` → `301 Moved Permanently`, `Location: https://telos.anshulfml.me:443/`.

## Chart bugs fixed this session

1. **Namespace double-ownership** — chart's `templates/namespace.yaml` collided with `deploy.sh --create-namespace` → release `failed`. Fixed by removing the chart's namespace template (Helm needs the ns to pre-exist for its release Secret, so it can't own it).
2. **Non-deterministic hostPath PV binding** — both PVs used `storageClassName: ""` with no `claimRef`; mongo's 1Gi claim could grab the 5Gi `postgres-pv`, stranding Postgres in `Pending`. Fixed by adding a `claimRef` to each PV template.
