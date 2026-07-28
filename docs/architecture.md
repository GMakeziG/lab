# Architecture

## Node Roles

- Control Plane Node
- Worker Nodes (compute)
- Future: Storage Node

## Platform Components

- Kubernetes (k3s)
- Rancher for cluster management
- Traefik for ingress routing
- MetalLB for LoadBalancer IP assignment

## Traffic Flow

Internal / LAN path:

Client → LoadBalancer IP → Ingress Controller → Service → Pod

Public path (Cloudflare Tunnel — how every published hostname is actually
reached):

```
Client (Internet)
  ↓  HTTPS to <app>.ninjatronics.io (Cloudflare edge, proxied DNS)
Cloudflare Tunnel  homelab-k3s / 381367a6-bdca-44e3-b78e-285166692048
  ↓  (cloudflared Deployment, namespace platform)
Traefik  https://traefik.kube-system.svc.cluster.local:443  (noTLSVerify)
  ↓  Ingress route (websecure), TLS via cert-manager ClusterIssuer
      letsencrypt-production-cloudflare
ClusterIP Service  →  Pod
```

- A **single shared tunnel** fronts all public hostnames (`draw`, `linkding`,
  `qr`, `grafana`, `audiobookshelf`). Hostnames are declared in
  `kubernetes/infrastructure/base/cloudflared/configmap.yaml`; the terminal
  `- service: http_status:404` rule must stay last.
- The tunnel credential (`cloudflared-tunnel-credentials`, namespace `platform`)
  is GitOps-managed via SOPS/age under `kubernetes/bootstrap-secrets/` (see
  `docs/sops-age-bootstrap-recovery.md`). It is a **shared-fate** secret — a bad
  value breaks every hostname on the tunnel.
- TLS is terminated **per host** by Traefik + cert-manager, so sharing the tunnel
  does not weaken per-app certificates.

## Design Goals

- Lightweight cluster
- Reproducible deployments
- Clear separation of platform vs application workloads

## Secrets Architecture (OpenBao + External Secrets)
### Overview
This environment uses OpenBao as the single source of truth for all sensitive data. Kubernetes does not store plaintext secrets in Git. Instead, secrets are dynamically synced at runtime.
### Flow
```
OpenBao (KV v2)  
↓  
External Secrets Operator (ESO)  
↓  
Kubernetes Secret (runtime only)  
↓  
Application (envFrom)
```
### Components
#### 1. OpenBao- Stores secrets under:
```
secret/apps/recipes
```
- Example keys:- `SECRET_KEY`- `POSTGRES_PASSWORD`
#### 2. External Secrets Operator
- Uses `ClusterSecretStore` named `openbao`
- Authenticates via Kubernetes auth
- Syncs secrets into Kubernetes
#### 3. ExternalSecretFile:
```
kubernetes/apps/recipes/external-secrets/recipes-secret.yaml
```
Maps OpenBao → Kubernetes Secret:
```yaml
spec:  
  data:    
    - secretKey: SECRET_KEY      
      remoteRef:        
        key: apps/recipes        
        property: SECRET_KEY    
    - secretKey: POSTGRES_PASSWORD      
      remoteRef:        
        key: apps/recipes        
        property: POSTGRES_PASSWORD
```

#### 4. Kubernetes Secret (runtime only)

```
recipes-secret (namespace: apps)
```

- Created automatically by ESO
- Never stored in Git
- Rotates via OpenBao updates

#### 5. Application Consumption

Deployment uses:

```
envFrom:  - secretRef:      name: recipes-secret
```

No `secretKeyRef` usage is allowed.

---

### Design Principles

- No plaintext secrets in Git
- OpenBao is the only source of truth
- Kubernetes secrets are ephemeral
- Applications consume secrets via `envFrom`
- Avoid mixing `env` + `secretKeyRef` for the same values

---

### What was removed

- Static Kubernetes secret: `recipes`
- All `secretKeyRef` references in deployment
- Hardcoded passwords

---

### Verification Commands

```
flux get kustomizationskubectl get externalsecret -n appskubectl get secret recipes-secret -n apps -o jsonpath='{.data}' | jq 'keys'
```

Expected:

```
POSTGRES_PASSWORDSECRET_KEY
```
---

## GitOps Architecture (Flux + Kustomize + Helm)

### Overview

This cluster is managed using a GitOps model where Git is the source of truth. Flux continuously reconciles the cluster state with the repository.

### Flow

```

GitHub Repo  
↓  
Flux Source Controller  
↓  
Kustomizations (cluster definitions)  
↓  
Resources (Namespaces → Platform → Apps → Observability)

```

---

### Repository Structure

```

kubernetes/  
├── clusters/  
│ └── home/  
│ ├── flux-system/  
│ ├── namespaces.yaml  
│ ├── platform.yaml  
│ ├── apps.yaml  
│ └── observability.yaml  
├── namespaces/  
├── platform/  
├── apps/  
└── observability/

````

---

### Reconciliation Order

Flux applies resources in dependency order:

1. **flux-system**
2. **namespaces**
3. **platform**
4. **apps**
5. **observability**

This ensures:

- CRDs exist before usage
- infrastructure is ready before apps
- apps are ready before monitoring

---

### Kustomizations

Each layer is defined as a Flux Kustomization:

```yaml
kind: Kustomization
spec:
  interval: 10m
  path: ./kubernetes/apps
  prune: true
  wait: true
```

---

### Platform Layer

Located in:

```
kubernetes/platform/
```

Includes:

- MetalLB
- Traefik (Ingress)
- cert-manager
- OpenBao
- External Secrets
- PostgreSQL

Purpose:

```
Provide shared infrastructure services
```

---

### Apps Layer

Located in:

```
kubernetes/apps/
````

Includes:

- recipes
- forgejo
- audiobookshelf (see below)
- future workloads

Principles:

- Apps depend on platform
- Apps consume secrets via External Secrets
- No app-specific infra in platform layer

#### Application inventory

| App            | Namespace | Base                                    | Overlay (production)                          | Public hostname                  |
| -------------- | --------- | --------------------------------------- | --------------------------------------------- | -------------------------------- |
| linkding       | apps      | —                                       | —                                             | linkding.ninjatronics.io         |
| audiobookshelf | apps      | `kubernetes/apps/base/audiobookshelf`   | `kubernetes/apps/production/audiobookshelf`   | audiobookshelf.ninjatronics.io   |

#### Audiobookshelf

Self-hosted audiobook/podcast server, onboarded via the base → production
overlay pattern (plain manifests, no Helm).

- **Namespace:** `apps` (shared with linkding).
- **Base** (`kubernetes/apps/base/audiobookshelf/`): ConfigMap
  `audiobookshelf-config`, four PVCs, Deployment, ClusterIP Service.
- **Overlay** (`kubernetes/apps/production/audiobookshelf/`): sets
  `namespace: apps`, layers base + the Traefik Ingress.
- **Image:** `ghcr.io/advplyr/audiobookshelf:2.36.0` pinned by digest.
- **Port:** container binds `:3005` because the ConfigMap sets `PORT=3005`
  (image default is `80`); the ConfigMap is consumed via `envFrom` — this is the
  real config mechanism. Service `:3005` → `targetPort http`.
- **Storage:** four `local-path` (RWO) PVCs — `/config` (2Gi), `/metadata`
  (10Gi), `/audiobooks` (100Gi), `/podcasts` (50Gi). Single replica + `Recreate`
  strategy (RWO-safe). Note: `local-path` PVs are `reclaimPolicy: Delete`, so
  pruning a PVC deletes its data.
- **Security:** runs non-root — `runAsNonRoot: true`, UID/GID `1000`,
  `fsGroup: 1000`, `seccompProfile: RuntimeDefault`,
  `allowPrivilegeEscalation: false`, all capabilities dropped.
- **Ingress/TLS:** `audiobookshelf.ninjatronics.io`, `ingressClassName: traefik`,
  `websecure`, cert-manager `letsencrypt-production-cloudflare`, TLS secret
  `audiobookshelf-ninjatronics-io-tls`; reached over the shared Cloudflare tunnel
  (see [Traffic Flow](#traffic-flow)).
- **Health:** `GET /ping` → `200 {"success":true}` (readiness + liveness).
- **Docs:** [validation runbook](runbooks/audiobookshelf-validation.md),
  [ADR 0001](decisions/0001-audiobookshelf-plain-manifests-shared-tunnel-sops-adoption.md),
  base [README](../kubernetes/apps/base/audiobookshelf/README.md). Security
  review **PH6-SEN-001 — PASS**.

---

### Helm via Flux

Flux Helm Controller manages Helm charts declaratively:

```yaml
kind: HelmRelease
spec:
  chart:
    spec:
      chart: traefik
```

Advantages:

- version controlled
- reproducible
- no manual helm commands

---

### Secrets Management

See:

```
OpenBao + External Secrets section

```

Key rule:

```
No secrets in Git
````

---

### Drift Control

Flux enforces desired state:

- Manual changes are reverted
- Deleted resources are recreated
- Git is the authority

---

### Operational Commands

```bash
flux get kustomizations
flux reconcile kustomization apps --with-source
flux logs --kind=Kustomization --name=apps -n flux-system
```

---

### Design Principles

- Git = source of truth
- Immutable infrastructure
- Layered architecture
- Separation of concerns
- No manual kubectl changes (except debugging)

---

### Future Improvements

- Multi-cluster support
- environment overlays (dev/stage/prod)
- automated image updates
- policy enforcement (OPA / Kyverno)

