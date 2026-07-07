# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

GitOps-managed Kubernetes homelab using FluxCD and k3s. Git is the single source of truth — Flux continuously reconciles cluster state. Manual `kubectl apply` changes are reverted by Flux.

Nodes: `zion` (control plane), `samson` and `niner` (workers).

## Before Making Changes

- Read `.claude/context/lab-architecture.md` for full context
- Prefer copy-first and validate-first changes
- Do not delete or move existing Flux/Kubernetes files unless explicitly asked
- Explain risky changes before applying them
- No secrets, tokens, real credentials, kubeconfigs, or private infrastructure data may be committed

## Homelab Rules

- This repository is GitOps-managed with Flux.
- Never apply manifests directly with `kubectl` unless explicitly requested.
- Prefer editing manifests in Git and letting Flux reconcile.
- Never store plaintext secrets in Git.
- Use SOPS with age encryption for all secrets.
- Existing External Secrets backed by OpenBao should remain in use unless migrating intentionally.
- Always preserve Flux directory structure.
- Validate manifests with `kubectl kustomize` before committing.

## Editor

Use vim for all terminal editing. Do not use nano unless explicitly requested.

## Local Tooling PATH

Tools are installed via Linuxbrew, not standalone binaries. Before running shell commands, use this PATH:

```bash
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
```

Required tools expected on PATH:

- `brew`
- `kubectl`
- `flux`
- `sops`
- `age`
- `cloudflared`
- `gh`
- `pnpm`

Before assuming a tool is missing, run:

```bash
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
which brew kubectl flux sops age cloudflared gh pnpm

kubectl version --client
flux --version
sops --version
age --version
cloudflared --version
gh --version
pnpm --version
```

Do not download standalone binaries unless the user confirms. Use `brew` to install missing tools.

## Key Operational Commands

```bash
# Flux status
flux get kustomizations
flux reconcile kustomization apps --with-source
flux logs --kind=Kustomization --name=apps -n flux-system

# Cluster state
kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingress -A

# External Secrets debugging
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | jq 'keys'

# Force External Secret re-sync
kubectl annotate externalsecret <name> -n <namespace> force-sync="$(date +%s)" --overwrite

# Restart a deployment after a secret change
kubectl rollout restart deployment <name> -n <namespace>
kubectl rollout status deployment <name> -n <namespace>
```

## Repository Layout

```
kubernetes/
├── clusters/
│   ├── production/        # Flux entrypoint; defines reconciliation order and dependencies
│   └── staging/
├── apps/
│   ├── base/              # Reusable app definitions (HelmRelease, source, kustomization)
│   ├── staging/           # Overlay per app: patches base + adds ExternalSecret + Ingress
│   └── production/
├── infrastructure/
│   ├── base/              # MetalLB, Traefik, OpenBao, External Secrets, ESO stores
│   └── production/        # Production overlay
├── namespaces/            # Namespace manifests
├── observability/         # Grafana, Loki, Promtail
└── _archived/             # Deprecated/replaced components (do not re-enable without review)
docs/                      # Architecture, networking, runbooks, troubleshooting
```

## GitOps Reconciliation Order

Flux applies layers in strict dependency order (defined in `kubernetes/clusters/production/`):

1. `flux-system` — Flux itself
2. `namespaces` — Namespace definitions
3. `infrastructure` — Platform services (MetalLB, Traefik, OpenBao, ESO)
4. `apps` — Application workloads
5. `observability` — Grafana, Loki, Promtail

CRDs from infrastructure must be ready before apps can reference them. Never add app resources to the infrastructure layer.

## App Overlay Pattern

Apps follow a base/overlay Kustomize pattern:

- `kubernetes/apps/base/<app>/` — HelmRelease, HelmRepository source, base kustomization
- `kubernetes/apps/staging/<app>/` — Overlay that includes the base, adds namespace, ExternalSecret, and Ingress patches

When adding a new app, create the base first, then the overlay. Reference the base with a relative path (`../../base/<app>`).

## Secrets Architecture

No plaintext secrets in Git. All secrets live in OpenBao (Vault-compatible KV v2) and are synced at runtime by External Secrets Operator (ESO).

```
OpenBao (KV v2, path: secret/apps/<app>)
  ↓  ClusterSecretStore "openbao"  (ESO, Kubernetes auth, role: eso-apps)
  ↓  ExternalSecret in app namespace
  ↓  Kubernetes Secret (runtime only, never in Git)
  ↓  Application (envFrom or secretKeyRef)
```

`ClusterSecretStore` is defined at `kubernetes/infrastructure/base/external-secrets-stores/openbao-clustersecretstore.yaml`. It authenticates to OpenBao at `http://openbao.openbao.svc.cluster.local:8200` using the `eso-apps` Kubernetes auth role.

When adding secrets for a new app:
1. Store the secret in OpenBao under `secret/apps/<app>`
2. Add an `ExternalSecret` manifest referencing `ClusterSecretStore: openbao`
3. Reference the resulting Kubernetes Secret in the HelmRelease or Deployment — `envFrom` is preferred over `secretKeyRef` where possible
4. Include a `secret.example.yaml` in the base to document expected secret keys without values

## Networking

MetalLB pool: `10.99.0.0/24`. All `LoadBalancer` services get IPs from this range. Traefik handles ingress routing. Applications are accessed via hostname matching local DNS or `/etc/hosts`.

## Cloudflare Tunnel

All public applications are exposed through Cloudflare Tunnel.

When adding a new application:

1. Add an ingress rule to `cloudflared-config`.
2. Create the DNS Tunnel record in Cloudflare.
3. Ensure the Kubernetes Ingress hostname matches.
4. Commit changes.
5. Allow Flux to reconcile.
6. Verify with:
   ```bash
   curl -I https://hostname
   ```
