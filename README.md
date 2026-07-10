> [!NOTE]
> Expanding the older project [three-tier-lab](https://github.com/Anshul-exe/3Tier-End-to-End-Prod-Infra) with Jenkins, ArgoCD, microservice architecture, Terraform IaC, Observability and Monitoring.
> Had to shift all of it's code here to not disturb that repo because it's linked in my Resume and don't want to showcase a project which is under development. I'll update the link to this project when this is completed, but it might take A LOT OF WORK!!!

# Three-Tier End-to-End Production Infrastructure on AWS EKS

> A production-grade, cloud-native application deployed on Amazon EKS with private control plane, ALB Ingress, horizontal pod autoscaling, and hardened network segmentation across public and private subnet tiers.

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/eks/)
[![Terraform](https://img.shields.io/badge/IaC-Manifests-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![React](https://img.shields.io/badge/Frontend-React-61DAFB?style=flat-square&logo=react&logoColor=black)](https://reactjs.org/)
[![Node.js](https://img.shields.io/badge/Backend-Node.js-339933?style=flat-square&logo=node.js&logoColor=white)](https://nodejs.org/)
[![MongoDB](https://img.shields.io/badge/Database-MongoDB-47A248?style=flat-square&logo=mongodb&logoColor=white)](https://www.mongodb.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Complete Infra](#complete-infra)
  - [High-Level Architecture](#high-level-architecture)
  - [Traffic Flow Diagram](#traffic-flow-diagram)
  - [Kubernetes Workload Layout](#kubernetes-workload-layout)
- [Tech Stack](#tech-stack)
- [Infrastructure Deep-Dive](#infrastructure-deep-dive)
  - [Network Topology](#network-topology)
  - [Node Scheduling Model](#node-scheduling-model)
  - [Access Model](#access-model)
- [Security Posture](#security-posture)
- [Autoscaling](#autoscaling)
- [Build & Deployment Workflow](#build--deployment-workflow)
- [Application Wiring](#application-wiring)
- [Health Checks](#health-checks)
- [Storage](#storage)
- [Key Highlights](#key-highlights)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Contributing](#contributing)

---

## Overview

This project demonstrates a **full production-grade deployment** of a TODO application across a three-tier architecture on **Amazon EKS**, covering every layer from DNS/TLS termination at the ALB, through private Kubernetes workloads, down to a persistent MongoDB datastore. It is purpose-built to reflect real-world DevOps and cloud infrastructure patterns used at scale.

**Key engineering decisions made in this project:**

- Private EKS control plane endpoint with bastion-gated administration
- Subnet-level workload isolation using node taints, tolerations, and node affinity
- Internet-facing ALB with ACM-managed TLS and HTTPS redirect enforcement
- Horizontal Pod Autoscaler on the API tier, driven by real CPU metrics via metrics-server
- Multi-stage Docker builds for minimal production image footprint
- ECR as the private image registry with IAM-policy-based pull authorization (no stored credentials)

---

## Architecture

### Complete Infra

<img width="1644" height="1744" alt="arch" src="https://github.com/user-attachments/assets/af50c595-ccec-491b-8308-789b092064ee" />

### High-Level Architecture

```
                          Internet
                             │
                    ┌────────▼────────┐
                    │  Route 53 / DNS │
                    │  assignment.    │
                    │  anshulfml.me   │
                    └────────┬────────┘
                             │  HTTPS (443)
                    ┌────────▼────────────────┐
                    │   Internet-Facing ALB   │
                    │  k8s-threetie-mainlb-*  │
                    │  TLS Termination (ACM)  │
                    │  HTTPS Redirect Enabled │
                    └────────┬────────────────┘
                             │  HTTP (forwarded)
              ┌──────────────▼───────────────────┐
              │         AWS EKS Cluster          │
              │       telos-cluster         │
              │         (Kubernetes v1.34)       │
              │                                  │
              │  ┌─────────────────────────────┐ │
              │  │     Namespace: telos   │ │
              │  │                             │ │
              │  │  ┌──────────────────────┐   │ │
              │  │  │  Frontend (Nginx)    │   │ │
              │  │  │  React App : 3000    │   │ │
              │  │  │  1 replica           │   │ │
              │  │  │  Public Subnet Node  │   │ │
              │  │  └──────────┬───────────┘   │ │
              │  │             │  /api proxy   │ │
              │  │  ┌──────────▼───────────┐   │ │
              │  │  │  Backend API         │   │ │
              │  │  │  Node.js/Express     │   │ │
              │  │  │  Port 3500           │   │ │
              │  │  │  HPA: 2-6 replicas   │   │ │
              │  │  │  Private Subnet Node │   │ │
              │  │  └──────────┬───────────┘   │ │
              │  │             │  mongodb-svc  │ │
              │  │  ┌──────────▼───────────┐   │ │
              │  │  │  MongoDB 4.4.6       │   │ │
              │  │  │  Port 27017          │   │ │
              │  │  │  PVC: 1Gi (hostPath) │   │ │
              │  │  │  Private Subnet Node │   │ │
              │  │  └──────────────────────┘   │ │
              │  └─────────────────────────────┘ │
              └──────────────────────────────────┘
```

---

### Traffic Flow Diagram

```
User Browser
    │
    │  DNS lookup: telos.anshulfml.me
    ▼
DNS Resolution (Cloudflare / Route 53)
    │
    │  Resolves to ALB DNS endpoint
    ▼
Internet-Facing ALB  ──── ACM Certificate (TLS)
    │                     HTTP → HTTPS redirect
    │  ALB Ingress rules (AWS Load Balancer Controller)
    ▼
Ingress: mainlb (class: alb)
    │
    │  Route: /  →  frontend service (ClusterIP :3000)
    ▼
Frontend Pod (Nginx)
    │
    │  Nginx reverse proxy: /api → api service (ClusterIP :3500)
    ▼
Backend API Pod (Node.js/Express)
    │
    │  MONGO_CONN_STR: mongodb://mongodb-svc:27017/todo
    │  Auth: mongo-sec (K8s Secret)
    ▼
MongoDB Pod
    │
    │  PVC: mongo-volume-claim → PV: mongo-pv (1Gi, hostPath /data/db)
    ▼
Persistent Storage (node-local)
```

---

### Kubernetes Workload Layout

```
Cluster: telos-cluster (ap-south-1)
│
├── Node Group: ng-7f9c0e2a  [PUBLIC SUBNETS]
│   ├── Instance type: t3.small
│   ├── Scale: 2-4 nodes
│   ├── Public IPs: Yes
│   └── Workloads:
│       └── frontend (1 replica, no affinity constraint)
│
└── Node Group: telos-db-api-ng  [PRIVATE SUBNETS]
    ├── Instance type: t3.small
    ├── Scale: 2-4 nodes
    ├── Public IPs: No (NAT Gateway for egress)
    ├── Taint: dedicated=db-api:NoSchedule   ◄── [HIGHLIGHTED: workload isolation]
    ├── Label: workload=db-api
    └── Workloads:
        ├── api  (HPA: 2-6 replicas, nodeAffinity: workload=db-api)
        └── mongodb  (1 replica, nodeAffinity: workload=db-api)


kube-system namespace:
├── aws-node (DaemonSet)          — VPC CNI networking
├── kube-proxy (DaemonSet)        — iptables/ipvs rules
├── metrics-server (Deployment)   — CPU/memory metrics for HPA
└── aws-load-balancer-controller  — ALB provisioning & lifecycle
```

---

## Tech Stack

### Application Layer

| Component       | Technology        | Version |
| --------------- | ----------------- | ------- |
| Frontend        | React             | Latest  |
| Frontend Server | Nginx             | Alpine  |
| Backend         | Node.js / Express | 14      |
| Database        | MongoDB           | 4.4.6   |

### Infrastructure & Cloud

| Component               | Technology      | Details                            |
| ----------------------- | --------------- | ---------------------------------- |
| Cloud Provider          | AWS             | ap-south-1                         |
| Container Orchestration | Amazon EKS      | Kubernetes v1.34                   |
| Load Balancer           | AWS ALB         | Internet-facing, TLS-terminated    |
| Container Registry      | Amazon ECR      | Private, IAM pull-only             |
| TLS Certificates        | AWS ACM         | `telos.anshulfml.me`          |
| Networking              | AWS VPC         | `192.168.0.0/16`                   |
| NAT Egress              | AWS NAT Gateway | Public subnet, private node egress |
| Bastion                 | AWS EC2         | IMDSv2 enforced, SSM-enabled       |

### Kubernetes Components

| Component                    | Role                                     |
| ---------------------------- | ---------------------------------------- |
| AWS Load Balancer Controller | ALB lifecycle management via Ingress     |
| metrics-server               | CPU/memory metrics provider for HPA      |
| aws-node (VPC CNI)           | Pod networking with VPC-native IPs       |
| kube-proxy                   | Service networking (iptables)            |
| Horizontal Pod Autoscaler    | API-tier autoscaling (2–6 pods, CPU 60%) |

### DevOps Toolchain

| Area              | Tool                             |
| ----------------- | -------------------------------- |
| Image Build       | Docker (multi-stage)             |
| Manifests         | Kubernetes YAML                  |
| Access Control    | IAM Roles for Node Groups        |
| Secret Management | Kubernetes Secrets (`mongo-sec`) |
| Remote Access     | SSH + AWS SSM (bastion)          |

---

## Infrastructure Deep-Dive

### Network Topology

```
VPC: vpc-0b70c2b1be52e7138  (192.168.0.0/16)
│
├── PUBLIC SUBNETS (x3 AZs)  ── tag: kubernetes.io/role/elb
│   ├── Internet Gateway attached
│   ├── NAT Gateway (egress for private subnets)
│   ├── ALB deployed here
│   └── ng-7f9c0e2a nodes (Frontend workloads)
│
└── PRIVATE SUBNETS (x3 AZs) ── tag: kubernetes.io/role/internal-elb
    ├── No direct internet access
    ├── Outbound via NAT Gateway (ECR pulls, OS updates)
    └── telos-db-api-ng nodes (API + MongoDB workloads)
```

**Security Groups:**
| SG | Purpose |
|----|---------|
| ALB SG | Controls inbound HTTP/HTTPS to the load balancer |
| Cluster SG | Control plane ↔ worker node communication |
| Shared Node SG | Inter-node and node ↔ API server traffic |
| Bastion SG (`sg-032d6fc9e56d9f582`) | SSH restricted to operator public IP only |

---

### Node Scheduling Model

> **`BENCHMARK PATTERN`** — Node taints + tolerations + nodeAffinity is the production-standard approach for workload isolation in multi-tenant and multi-tier Kubernetes clusters.

The `telos-db-api-ng` node group is **tainted** to prevent general workloads from landing on database/API nodes:

```yaml
# Applied at node group level
taint:
  key: dedicated
  value: db-api
  effect: NoSchedule
```

API and MongoDB pods carry the matching **toleration and nodeAffinity**:

```yaml
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "db-api"
    effect: "NoSchedule"

affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workload
              operator: In
              values:
                - db-api
```

This enforces that **only** API and database workloads land on private-subnet nodes. The frontend, with no affinity or toleration set, runs exclusively on the public-subnet general node group.

---

### Access Model

> **`SECURITY BEST PRACTICE`** — Private EKS API endpoint eliminates control-plane attack surface from the public internet entirely.

```
Operator machine (public IP)
        │
        │  SSH (port 22, SG-restricted to operator IP)
        ▼
Bastion Host: telos-bastion
├── Public IP:  15.206.68.60
├── Private IP: 192.168.78.240
├── IMDSv2 enforced (HttpTokens: required)
├── Instance profile: telos-bastion-ssm-profile
└── SSM Session Manager available as secondary access
        │
        │  kubectl (private VPC endpoint)
        ▼
EKS API Server (private-only endpoint)
        │
        ▼
Kubernetes Control Plane
```

**All cluster administration is performed from inside the VPC via the bastion.** Direct `kubectl` from the public internet is blocked by design.

```bash
# Copy manifest to bastion
scp -i ~/.keys/project-bastion-key.pem <manifest.yaml> \
    ec2-user@15.206.68.60:/home/ec2-user/

# SSH into bastion
ssh -i ~/.keys/project-bastion-key.pem ec2-user@15.206.68.60

# Apply from inside the VPC
kubectl apply -f /home/ec2-user/<manifest.yaml>
```

---

## Security Posture

> This section maps implemented controls to production security standards.

### Network Security

| Control                | Implementation                             | Status      |
| ---------------------- | ------------------------------------------ | ----------- |
| Private EKS endpoint   | Public access disabled on control plane    | Implemented |
| Subnet isolation       | DB/API on private subnets, no public IPs   | Implemented |
| ALB TLS termination    | ACM certificate, HTTPS redirect enabled    | Implemented |
| Bastion SG restriction | SSH locked to operator IP via SG rule      | Implemented |
| NAT Gateway egress     | Private nodes reach internet outbound-only | Implemented |

### Identity & Access

| Control                   | Implementation                                                                   | Status      |
| ------------------------- | -------------------------------------------------------------------------------- | ----------- |
| ECR pull via IAM          | `AmazonEC2ContainerRegistryPullOnly` on node role                                | Implemented |
| No static ECR credentials | IAM instance profile handles auth                                                | Implemented |
| IMDSv2 enforcement        | `HttpTokens: required` on bastion EC2                                            | Implemented |
| SSM access                | Bastion has `AmazonSSMManagedInstanceCore`, no need for open port 22 as fallback | Implemented |

### Known Gaps (Production Recommendations)

> These are acknowledged limitations.

| Gap                                | Risk                               | ToDo                                                       |
| ---------------------------------- | ---------------------------------- | ---------------------------------------------------------- |
| `mongo-sec` stored in Git (base64) | Secret exposure in version control | Migrate to AWS Secrets Manager + External Secrets Operator |
| HostPath PVC for MongoDB           | Data loss if node is replaced      | Migrate to EBS-backed PersistentVolume (`gp3`)             |
| No cluster autoscaler              | Node count is static               | Add Karpenter or Cluster Autoscaler                        |
| Frontend on public subnet node     | Increased blast radius             | Move behind private ALB if not serving external users      |

---

## Autoscaling

> **`RESUME HIGHLIGHT`** — HPA with a real metrics pipeline (metrics-server → Kubernetes Metrics API → HPA controller) is a core production Kubernetes pattern.

### Horizontal Pod Autoscaler — API Tier

```
metrics-server
    │  scrapes node/pod CPU & memory
    ▼
Kubernetes Metrics API
    │
    ▼
HPA Controller (api-hpa)
    │  target: CPU utilization = 60%
    │  min replicas: 2
    │  max replicas: 6
    ▼
API Deployment (scales 2 → 6 pods)
```

| Parameter         | Value           |
| ----------------- | --------------- |
| HPA Name          | `api-hpa`       |
| Target Deployment | `api`           |
| Min Replicas      | 2               |
| Max Replicas      | 6               |
| Scale Metric      | CPU Utilization |
| Target Threshold  | 60%             |

**No HPA** is configured for frontend (static, low-compute) or MongoDB (stateful — horizontal scaling of MongoDB requires replica sets, not HPA).

---

## Build & Deployment Workflow

```
Developer Workstation
        │
        │  1. Write code (frontend / backend)
        ▼
Local Docker Build
        │
        │  2a. docker build -t telos-backend ./backend
        │  2b. docker build -t telos-frontend ./frontend
        │       (multi-stage: Node build → Nginx serve)
        ▼
Amazon ECR (Private Registry)
        │
        │  3. aws ecr get-login-password | docker login
        │     docker push 632377784699.dkr.ecr.ap-south-1.amazonaws.com/telos-*
        ▼
Bastion Host (inside VPC)
        │
        │  4. scp manifests/ to bastion
        │     kubectl apply -f manifests/ -n telos
        ▼
EKS (telos-cluster)
        │
        │  5. Nodes pull images from ECR via IAM
        │     AWS LB Controller provisions/updates ALB
        ▼
Live at https://telos.anshulfml.me
```

### Dockerfile Strategy

**Backend** (`backend/Dockerfile`):

- Base: `node:14`
- Single-stage, minimal dependency install
- Runs Express server on port 3500

**Frontend** (`frontend/Dockerfile`):

> **`BEST PRACTICE`** — Multi-stage builds separate build dependencies from the runtime image, drastically reducing final image size and attack surface.

```dockerfile
# Stage 1: Build
FROM node:14 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Serve
FROM nginx:alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 3000
```

The Nginx config in the final image handles:

- Serving the React static build
- Proxying `/api` requests to the backend service

---

## Application Wiring

### Service Discovery (Kubernetes DNS)

All inter-service communication uses Kubernetes DNS — no hardcoded IPs.

```
frontend  →  api service      →  api.telos.svc.cluster.local:3500
api       →  mongodb service  →  mongodb-svc.telos.svc.cluster.local:27017
```

### Environment Configuration

**Backend:**

```
MONGO_CONN_STR=mongodb://mongodb-svc:27017/todo?directConnection=true
MONGO_USERNAME   → from secret: mongo-sec
MONGO_PASSWORD   → from secret: mongo-sec
```

**Frontend:**

```
REACT_APP_BACKEND_URL=https://telos.anshulfml.me/api/tasks
```

### Secrets

```yaml
# mongo-sec (Kubernetes Secret, telos namespace)
apiVersion: v1
kind: Secret
metadata:
  name: mongo-sec
  namespace: telos
type: Opaque
data:
  username: <base64>
  password: <base64>
```

---

## Health Checks

> **`BEST PRACTICE`** — Liveness and readiness probes are mandatory in production. They prevent traffic from reaching unready pods and enable Kubernetes to self-heal by restarting failed containers.

### Backend Probes

```yaml
livenessProbe:
  httpGet:
    path: /ok
    port: 3500
  initialDelaySeconds: 10
  periodSeconds: 15

readinessProbe:
  httpGet:
    path: /ok
    port: 3500
  initialDelaySeconds: 5
  periodSeconds: 10
```

| Probe     | Endpoint        | Effect on Failure                               |
| --------- | --------------- | ----------------------------------------------- |
| Liveness  | `GET /ok :3500` | Pod is killed and restarted                     |
| Readiness | `GET /ok :3500` | Pod removed from Service endpoints (no traffic) |

Frontend and MongoDB do not have custom health check endpoints configured; adding them is a recommended enhancement.

---

## Storage

```
mongo-volume-claim  (PVC, 1Gi, ReadWriteOnce)
        │
        ▼
mongo-pv  (PV, hostPath: /data/db, Retain)
        │
        ▼
Node-local disk on telos-db-api-ng node
```

| Property           | Value                 |
| ------------------ | --------------------- |
| PVC Name           | `mongo-volume-claim`  |
| PV Name            | `mongo-pv`            |
| Capacity           | 1Gi                   |
| Access Mode        | ReadWriteOnce         |
| Reclaim Policy     | Retain                |
| Backend            | hostPath (`/data/db`) |
| StorageClass `gp2` | Exists but unused     |

> **Production Note:** HostPath volumes are node-local. If the MongoDB pod is rescheduled to a different node, data will not follow. For production, replace with an EBS-backed dynamic PersistentVolume using the `gp3` StorageClass and the EBS CSI driver.

---

## Key Highlights

The following patterns implemented in this project are directly relevant to my **DevOps Engineer** roles and represent real production standards:

---

### `PRIVATE EKS CONTROL PLANE + BASTION ARCHITECTURE`

**What:** EKS API server endpoint is private-only. Public access is disabled. All `kubectl` commands are issued from a bastion host inside the VPC.
**Why it matters:** Eliminates the Kubernetes API server from the internet-facing attack surface. Standard in regulated and enterprise environments.

---

### `WORKLOAD ISOLATION VIA NODE TAINTS + TOLERATIONS + NODE AFFINITY`

**What:** The database/API node group is tainted (`dedicated=db-api:NoSchedule`). Only pods with the matching toleration and node affinity can schedule there.
**Why it matters:** Demonstrates multi-tier workload isolation without a service mesh. Prevents noisy-neighbor interference between frontend and stateful backend workloads.

---

### `MULTI-STAGE DOCKER BUILDS`

**What:** Frontend image uses a two-stage Dockerfile — Node.js build stage discarded, only Nginx + static assets shipped.
**Why it matters:** Reduces final image size significantly. Removes build toolchain from the production container, shrinking attack surface. Industry-standard practice.

---

### `IAM-BASED ECR AUTHORIZATION (NO STATIC CREDENTIALS)`

**What:** EKS nodes pull from ECR using the `AmazonEC2ContainerRegistryPullOnly` IAM policy attached to the node instance role. No Docker credentials stored.
**Why it matters:** Credential-free image pull using AWS IAM is the AWS-recommended approach. Eliminates secret rotation overhead and static credential exposure risk.

---

### `AWS LOAD BALANCER CONTROLLER + ALB INGRESS`

**What:** The AWS Load Balancer Controller running in `kube-system` provisions and manages the ALB lifecycle declaratively via Kubernetes Ingress annotations.
**Why it matters:** Kubernetes-native infrastructure management. The ALB is fully managed through GitOps-compatible YAML manifests.

---

### `HORIZONTAL POD AUTOSCALER WITH METRICS-SERVER`

**What:** `api-hpa` scales the API deployment from 2 to 6 replicas based on CPU utilization (60% threshold), using real metrics from `metrics-server`.
**Why it matters:** Shows understanding of the full HPA pipeline — metrics collection, Metrics API, HPA controller, and pod scaling. A required component in production API deployments.

---

### `IMDSv2 ENFORCEMENT ON EC2`

**What:** The bastion EC2 instance enforces IMDSv2 (`HttpTokens: required`), blocking SSRF-based metadata theft attacks.
**Why it matters:** Prevents SSRF attacks that exploit IMDSv1 to steal IAM credentials from the instance metadata endpoint. Required by AWS security baselines.

---

### `PRIVATE SUBNET ISOLATION FOR STATEFUL WORKLOADS`

**What:** API and MongoDB pods run exclusively on the `telos-db-api-ng` node group, which lives in private subnets with no public IP assignment. Outbound internet access flows through a NAT Gateway.
**Why it matters:** Stateful services (databases, APIs with DB access) should never have a path to direct internet exposure. This is VPC design as a security control.

---

### `ACM TLS + HTTPS REDIRECT AT THE ALB`

**What:** TLS is terminated at the ALB using an ACM-managed certificate. HTTP traffic is redirected to HTTPS automatically.
**Why it matters:** Offloads TLS overhead from application pods. Centralized certificate management with automatic renewal via ACM.

---

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate credentials
- `kubectl` installed
- Docker installed
- SSH key for bastion access

### 1. Configure ECR Access

```bash
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS \
  --password-stdin 632377784699.dkr.ecr.ap-south-1.amazonaws.com
```

### 2. Build and Push Images

```bash
# Backend
docker build -t telos-backend ./backend
docker tag telos-backend:latest \
  632377784699.dkr.ecr.ap-south-1.amazonaws.com/telos-backend:latest
docker push 632377784699.dkr.ecr.ap-south-1.amazonaws.com/telos-backend:latest

# Frontend
docker build -t telos-frontend ./frontend
docker tag telos-frontend:latest \
  632377784699.dkr.ecr.ap-south-1.amazonaws.com/telos-frontend:latest
docker push 632377784699.dkr.ecr.ap-south-1.amazonaws.com/telos-frontend:latest
```

### 3. Deploy to EKS (via Bastion)

```bash
# Copy manifests to bastion
scp -i ~/.keys/project-bastion-key.pem -r manifests/ \
    ec2-user@15.206.68.60:/home/ec2-user/

# SSH into bastion
ssh -i ~/.keys/project-bastion-key.pem ec2-user@15.206.68.60

# Apply all manifests
kubectl apply -f /home/ec2-user/manifests/ -n telos

# Verify deployments
kubectl get pods -n telos
kubectl get ingress -n telos
kubectl get hpa -n telos
```

### 4. Verify the Stack

```bash
# Check all resources in the telos namespace
kubectl get all -n telos

# Watch HPA scaling behavior
kubectl get hpa -n telos --watch

# Describe ALB Ingress
kubectl describe ingress mainlb -n telos
```

---

## Automated Deployment — `deploy.sh` + Helm (Phase 2)

> The manual `kubectl apply` flow above is the legacy path. The current stack
> (auth / task / notification services + databases) is deployed from the Helm
> chart at [`manifests/helm/telos/`](manifests/helm/telos/README.md) via the
> `deploy.sh` wrapper at the repo root. This replaces the old
> `export ... ; envsubst < *.yaml | kubectl apply` dance.

### Prerequisites

- **Run from the bastion only.** The EKS API endpoint is private; `deploy.sh`
  hard-fails early if it cannot reach the cluster API (i.e. if run from a
  laptop). SSH into the bastion and run it there.
- **`terraform apply` for `terraform/envs/dev` must already be done** this
  session — the script reads live values (`sqs_queue_url`,
  `task_service_irsa_role_arn`, `notification_service_irsa_role_arn`) from
  `terraform output`.
- `helm`, `kubectl`, and `terraform` on PATH, with a kubeconfig pointing at
  `telos-cluster` (`aws eks update-kubeconfig --name telos-cluster --region ap-south-1`).

### What it does

1. Preflight: checks `helm`/`kubectl`/`terraform` exist and that the **private
   EKS API is reachable** (the bastion gate).
2. Reads the dynamic values from `terraform output`.
3. Writes a **gitignored** `generated-values.yaml` (IRSA ARNs + SQS URL).
4. Validates the render with `helm template` — this trips the chart's
   `telos.assertNoPlaceholder` guard if any `${...}` placeholder survived.
5. `helm upgrade --install telos manifests/helm/telos/ -f generated-values.yaml -n telos --create-namespace`.
6. Prints a post-deploy checklist (pods, ingress URL, notification log tail).

### Usage

```bash
# On the bastion, from the repo root:
./deploy.sh              # full deploy (read TF outputs -> helm upgrade --install)
./deploy.sh --dry-run    # render only (writes generated-values.yaml, no cluster writes)
./deploy.sh --destroy    # helm uninstall telos
./deploy.sh --help
```

Provide real secrets (don't ship the chart's dev defaults) either by extending
`generated-values.yaml` or via env-driven `--set` — see the
[chart README](manifests/helm/telos/README.md#common-overrides).

### Post-deploy checklist (printed by the script)

```bash
kubectl get pods -n telos
kubectl get ingress mainlb -n telos                       # ALB address; app at http://telos.anshulfml.me/
kubectl logs -n telos -l app=notification-service -f --tail=50   # watch SQS events get consumed
```

---

## Project Structure

```
.
├── backend/
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│       ├── index.js          # Express app entrypoint
│       └── routes/           # API route handlers
│
├── frontend/
│   ├── Dockerfile            # Multi-stage: Node build → Nginx
│   ├── nginx.conf            # /api proxy config
│   ├── package.json
│   └── src/
│       └── App.js            # React entrypoint
│
├── manifests/
│   ├── Backend/
│   │   ├── deployment.yaml   # Backend API Deployment (nodeAffinity + toleration)
│   │   ├── hpa.yaml          # HPA: 2-6 replicas, CPU 60%
│   │   └── service.yaml      # Backend API Service
│   │
│   ├── Database/
│   │   ├── deployment.yaml   # MongoDB Deployment
│   │   ├── pv.yaml           # PersistentVolume (hostPath)
│   │   ├── pvc.yaml          # PersistentVolumeClaim
│   │   ├── secrets.yaml      # MongoDB Secret
│   │   └── service.yaml      # MongoDB Service
│   │
│   ├── Frontend/
│   │   ├── deployment.yaml   # Frontend Deployment
│   │   ├── iam_policy.json   # IAM policy for frontend resources
│   │   └── service.yaml      # Frontend Service
│   │
│   ├── iam_policy.json       # ALB / AWS Load Balancer Controller IAM Policy
│   └── ingress.yaml          # ALB Ingress (class: alb)
│
└── README.md
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m 'Add: description'`)
4. Push to the branch (`git push origin feature/your-feature`)
5. Open a Pull Request

---

> This project is intended as a reference implementation of production-grade Kubernetes deployment patterns on AWS. Infrastructure details reflect a real deployed environment in `ap-south-1`.
