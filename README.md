# k3s Lab

This repository is the source of truth for my Kubernetes-based lab environment.  
It follows a GitOps-driven approach to manage infrastructure, applications, and observability in a Rancher-managed k3s cluster.

---

## Purpose

- Build and validate real-world infrastructure patterns
- Practice GitOps workflows and automation
- Deploy and operate containerized applications
- Troubleshoot networking, storage, and cluster behavior
- Serve as a reproducible DevOps learning platform

---

## Core Stack

- Kubernetes (k3s)
- Rancher (cluster management)
- MetalLB (Layer 2 load balancing)
- Traefik (Ingress controller)
- Observability:
  - Grafana
  - Loki
  - Promtail
- Self-hosted Git service (primary + mirror)

---

## Architecture

- 1 control-plane node
- Multiple worker nodes
- Layer 2 load balancing via MetalLB
- Ingress routing via Traefik
- GitOps reconciliation via Flux

---

## GitOps Workflow

1. Changes are committed to this repository
2. Flux reconciles cluster state with Git
3. Kubernetes resources are applied automatically
4. Drift is detected and corrected


Git → Flux → Cluster


---

## Repository Layout

```bash
.
├── docs/              # Architecture, networking, troubleshooting
├── kubernetes/
│   ├── apps/          # Application deployments
│   ├── observability/ # Monitoring stack
│   ├── platform/      # Core infrastructure components
│   └── namespaces/    # Namespace definitions
├── scripts/           # Bootstrap and validation scripts
└── README.md
```
---
## Getting Started
### Prerequisites
- kubectl
- Helm
- Access to the cluster
- Git

```bash
### Basic Commands
# Check cluster state
kubectl get nodes

# View Flux status
flux get kustomizations

# Inspect workloads
kubectl get pods -A
```
---
## Security
- No secrets are stored in this repository
- Secrets are managed externally (e.g., external secret provider)
- Placeholder values are used for all sensitive configs
- Access is controlled via cluster RBAC
---
## Design Principles
- Git is the single source of truth
- Declarative over imperative
- Minimal manual changes in-cluster
- Reproducibility over convenience
- Observability built-in, not added later
---
## Roadmap
- External secrets integration
- Certificate automation
- Storage improvements
- CI validation for manifests
- Multi-environment structure (dev / prod split)
---
## Notes
This lab is intentionally designed to be broken and rebuilt.
Every failure is part of the learning process.
