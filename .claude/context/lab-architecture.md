# Lab Architecture Context

Purpose:
GitOps-managed Kubernetes homelab using FluxCD and k3s.

Primary Nodes:
- zion -> control/admin
- samson -> worker
- niner -> worker

Core Stack:
- FluxCD
- k3s
- MetalLB
- Traefik
- OpenBao
- External Secrets
- Grafana/Loki/Promtail
- Forgejo

Networking:
- 10.99.0.0/24 MetalLB pool

Practices:
- copy-first changes
- validate-first deployments
- avoid destructive moves/deletes
- GitOps as source of truth
