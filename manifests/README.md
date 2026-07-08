# Manifests Deployment Guide

## Injecting Dynamic Values (SQS_QUEUE_URL)
The `task-service.yaml` and `notification-service.yaml` manifests contain a templated variable `${SQS_QUEUE_URL}` because this value is dynamic and comes from Terraform outputs.

Before applying these manifests, you must export the URL from Terraform and inject it using `envsubst`:

```bash
# Export the URL from your terraform outputs
export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)

# Apply the manifests with substitution
envsubst < Backend/task-service.yaml | kubectl apply -f -
envsubst < Backend/notification-service.yaml | kubectl apply -f -
```

*(Note: As planned in Phase 4 of `plan.md`, this substitution approach is a candidate for conversion to ArgoCD/Kustomize/Helm overlays, which will natively handle these dynamic configurations via GitOps in the future.)*
