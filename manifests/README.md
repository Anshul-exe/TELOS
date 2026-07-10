# Manifests Deployment Guide

## Injecting Dynamic Values

The `task-service.yaml` and `notification-service.yaml` manifests contain templated variables because these values are dynamic and come from Terraform outputs. The required variables are:

- `SQS_QUEUE_URL`: The URL of the SQS queue used for task events.
- `TASK_SERVICE_IRSA_ARN`: The IAM Role ARN for the task service ServiceAccount (required for SQS publish permissions).
- `NOTIFICATION_SERVICE_IRSA_ARN`: The IAM Role ARN for the notification service ServiceAccount (required for SQS consume permissions).

Before applying these manifests, you must export these values (e.g., from your Terraform outputs) and inject them using `envsubst`:

```bash
# Export the dynamic values from your terraform outputs
export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)
export TASK_SERVICE_IRSA_ARN=$(terraform output -raw task_service_irsa_arn)
export NOTIFICATION_SERVICE_IRSA_ARN=$(terraform output -raw notification_service_irsa_arn)

# Apply the manifests with substitution
envsubst < Backend/task-service.yaml | kubectl apply -f -
envsubst < Backend/notification-service.yaml | kubectl apply -f -
```

_(Note: As planned in Phase 4 of `plan.md`, this substitution approach is a candidate for conversion to ArgoCD/Kustomize/Helm overlays, which will natively handle these dynamic configurations via GitOps in the future.)_
