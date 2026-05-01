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


OpenBao (KV v2)
↓
External Secrets Operator (ESO)
↓
Kubernetes Secret (runtime only)
↓
Application (envFrom)


### Components

#### 1. OpenBao
- Stores secrets under:

secret/apps/recipes

- Example keys:
- `SECRET_KEY`
- `POSTGRES_PASSWORD`

#### 2. External Secrets Operator
- Uses `ClusterSecretStore` named `openbao`
- Authenticates via Kubernetes auth
- Syncs secrets into Kubernetes

#### 3. ExternalSecret

File:

kubernetes/apps/recipes/external-secrets/recipes-secret.yaml


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

4. Kubernetes Secret (runtime only)
recipes-secret (namespace: apps)
Created automatically by ESO
Never stored in Git
Rotates via OpenBao updates
5. Application Consumption

Deployment uses:

envFrom:
  - secretRef:
      name: recipes-secret

No secretKeyRef usage is allowed.

Design Principles
No plaintext secrets in Git
OpenBao is the only source of truth
Kubernetes secrets are ephemeral
Applications consume secrets via envFrom
Avoid mixing env + secretKeyRef for the same values
What was removed
Static Kubernetes secret: recipes
All secretKeyRef references in deployment
Hardcoded passwords
Verification Commands
flux get kustomizations

kubectl get externalsecret -n apps

kubectl get secret recipes-secret -n apps -o jsonpath='{.data}' | jq 'keys'

Expected:

POSTGRES_PASSWORD
SECRET_KEY
Future Improvements
Move to dynamic database credentials via OpenBao
Add TLS to OpenBao ingress
Restrict access via Traefik middleware (IP allowlist / auth)
Rotate secrets automatically
