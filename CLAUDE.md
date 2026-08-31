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
## Nova Second Brain Documentation

Zion hosts Nova's canonical Second Brain vault at:

`/home/gerso/Development/ninjatronics-ai/vault`

The vault is synchronized through Obsidian Sync for consumption by other Obsidian clients.

After completing and verifying meaningful homelab work, record durable operational knowledge from the work in the canonical vault.

Before modifying the vault:

1. Read `/home/gerso/Development/ninjatronics-ai/vault/AGENTS.md`.
2. Follow the organization and documentation rules defined there.
3. Inspect existing notes before creating new ones.
4. Update existing system, project, runbook, or reference notes when they already cover the subject.
5. Do not duplicate information unnecessarily.

Use the appropriate vault locations:

- `2_Systems/` — current architecture, application, host, and system state
- `3_Projects/` — project-specific work, milestones, and decisions
- `4_Runbooks/` — repeatable operational and troubleshooting procedures
- `5_References/` — reusable technical concepts, patterns, and implementation knowledge
- `6_Daily/YYYY-MM-DD.md` — chronological record of meaningful work performed that day

### Daily notes

Daily notes are cumulative.

When today's daily note already exists:

- Read it first.
- Preserve all existing content.
- Append the new activity as a new `##` section.
- Never replace earlier activities with the current task.

### What to record

Capture information that will help future troubleshooting, maintenance, upgrades, migrations, or architectural decisions, including:

- what was implemented or changed
- why the chosen architecture was used
- important paths, namespaces, services, and relationships
- problems encountered and their root causes
- unsuccessful approaches when they provide useful troubleshooting knowledge
- fixes and important gotchas
- validation performed
- significant decisions and their reasoning
- remaining work or known limitations

Do not merely copy terminal output into the vault. Convert the work into concise, reusable operational knowledge.

### Security

Never record:

- passwords
- API tokens
- private keys
- secret values
- kubeconfigs
- authentication cookies
- recovery codes
- other sensitive credentials

References to secret locations such as OpenBao paths and expected property names are acceptable when they do not expose secret values.

### Completion

For substantial homelab work, documentation in the canonical Second Brain is part of completing the task.

After updating the vault:

1. Verify the files were written successfully.
2. Preserve useful cross-links between related notes.
3. Report which vault notes were created or updated.

## Nova Second Brain Inbox Workflow

Nova's canonical Second Brain inbox is:

`/home/gerso/Development/ninjatronics-ai/vault/1_Inbox`

Markdown files placed in `1_Inbox/` represent pending work, questions, research items, implementation ideas, troubleshooting tasks, or documentation that requires processing.

At the beginning of substantial work, and before declaring a work session complete:

1. Inspect `1_Inbox/` for `*.md` files.
2. Read each pending Markdown file.
3. Determine whether the item:
   - can be completed safely without infrastructure changes,
   - requires research or a proposed implementation plan,
   - requires user approval before execution,
   - belongs in another permanent vault location,
   - or is blocked and requires more information.
4. Do not silently ignore inbox items.
5. Do not treat the presence of an inbox file as authorization to make destructive, security-sensitive, production, DNS, secret, or infrastructure changes.

For inbox items requiring changes to the homelab:

1. Research and inspect the current environment.
2. Prepare the proposed implementation plan.
3. Explain risks, required secrets, external actions, validation, and rollback.
4. Stop and obtain approval before making changes unless the user has already explicitly authorized implementation.

When an inbox item is completed:

1. Preserve the useful knowledge in the appropriate permanent vault note.
2. Update the relevant daily note.
3. Record how the work was validated.
4. Remove or archive the inbox item only after its work has been completed and documented.
5. Never delete an unresolved inbox item merely because it has been reviewed.

If an inbox item is blocked, preserve it and clearly document what is required to continue.
