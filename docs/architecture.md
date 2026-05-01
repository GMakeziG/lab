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

Client → LoadBalancer IP → Ingress Controller → Service → Pod

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
- future workloads

Principles:

- Apps depend on platform
- Apps consume secrets via External Secrets
- No app-specific infra in platform layer

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

