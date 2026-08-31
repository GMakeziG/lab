# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

GitOps-managed Kubernetes homelab using FluxCD and k3s. Git is the single source of truth — Flux continuously reconciles cluster state. Manual `kubectl apply` changes are reverted by Flux.

Nodes: `zion` (control plane), `samson` and `niner` (workers).

## Nova / Agent Operating Model

When Nova is operating in this repository, Nova remains the orchestrator.

Before substantial work, read:

`/home/gerso/Development/ninjatronics-ai/AGENTS.md`

Then follow the authoritative routing and orchestration policy referenced there:

`/home/gerso/Development/ninjatronics-ai/shared/standards/agent-routing.md`

These instructions define:

- when Nova handles work directly
- when work should be delegated to Claude Code, Codex, or specialist agents
- Herdr orchestration behavior
- concurrency and worktree requirements
- validation, escalation, and final coordination responsibilities

This repository's `CLAUDE.md` adds homelab-specific GitOps, Kubernetes, Flux, OpenBao, networking, and validation requirements.

If repository-specific instructions conflict with the authoritative Nova orchestration policy, stop and ask the user rather than silently choosing one.

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
- Use OpenBao + External Secrets Operator for runtime application secrets when supported by the existing secrets architecture.
- Use SOPS with age encryption for bootstrap secrets or other Git-managed secrets that intentionally require encrypted storage in Git.
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

- `kubernetes/apps/base/<app>/` — reusable application resources such as HelmRelease, HelmRepository, Deployment, Service, PVC, ConfigMap, and supporting manifests as appropriate
- `kubernetes/apps/staging/<app>/` — staging overlay that references the base and adds environment-specific resources such as ExternalSecret and Ingress
- `kubernetes/apps/production/<app>/` — production overlay that references the base and adds environment-specific resources such as ExternalSecret and Ingress

When adding a new application:

1. Inspect existing applications before choosing an implementation pattern.
2. Create reusable resources under `kubernetes/apps/base/<app>/`.
3. Create the required environment overlay under `kubernetes/apps/<environment>/<app>/`.
4. Reference the base using the repository's existing relative-path convention.
5. Add the application to the appropriate environment-level `kustomization.yaml`.
6. Validate the application base, environment overlay, environment application layer, and cluster entrypoint with `kubectl kustomize`.
7. Do not assume every application requires Helm; follow the application's supported deployment model and existing repository conventions.

Production applications must use `kubernetes/apps/production/<app>/`. Do not place production-only resources in the staging overlay.

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

## Second Brain Integration

Nova's canonical Second Brain is:

`/home/gerso/Development/ninjatronics-ai/vault`

For substantial homelab work, follow the persistence and vault policies defined by:

`/home/gerso/Development/ninjatronics-ai/AGENTS.md`

and the vault-specific instructions in:

`/home/gerso/Development/ninjatronics-ai/vault/AGENTS.md`

Homelab discoveries worth preserving commonly include:

- deployed application architecture
- namespaces, services, storage, and dependency relationships
- GitOps implementation decisions
- OpenBao secret paths and expected property names, but never secret values
- networking, Traefik, TLS, and Cloudflare patterns
- troubleshooting root causes and fixes
- operational runbooks
- validation procedures
- known limitations and remaining work

Repository documentation should remain in this repository. The vault should preserve durable operational knowledge and may link to repository documentation rather than duplicating it.

## Nova Second Brain Inbox Workflow

At the beginning of substantial homelab work and before completing a work session, inspect:

`/home/gerso/Development/ninjatronics-ai/vault/1_Inbox/`

Any `*.md` file there represents pending work that must be reviewed and triaged.

For each inbox item:

1. Read it.
2. Determine whether it can be handled directly, delegated under the agent-routing policy, requires a plan, requires user approval, or is blocked.
3. Do not interpret an inbox item as authorization for destructive, production, security-sensitive, DNS, secret-management, or external-service changes.
4. Follow the normal approval requirements before implementation.
5. When completed, preserve durable knowledge according to the canonical vault policy.
6. Archive or remove the inbox item only after its work has been completed and documented.
7. Preserve unresolved or blocked items and record what is required to continue.

Do not silently ignore pending inbox Markdown files.
