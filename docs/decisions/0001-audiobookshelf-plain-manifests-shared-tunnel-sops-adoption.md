# ADR 0001 — Audiobookshelf: plain manifests, shared Cloudflare tunnel reuse, and SOPS adoption of the tunnel credential

- **Status:** Accepted
- **Date:** 2026-07-28
- **Deciders:** Gerso Robayo-Guillen (owner/operator); implementation + review under Phase 6 (PH6)
- **Security review:** PH6-SEN-001 — verdict **PASS** (0 BLOCKER, 0 HIGH; 3 MEDIUM residual/operational risks)

This ADR records three coupled decisions taken while onboarding
[Audiobookshelf](https://github.com/advplyr/audiobookshelf) (ABS) onto the
GitOps homelab (FluxCD + k3s). It complements — and does not replace — the
operational detail in
[`docs/runbooks/audiobookshelf-validation.md`](../runbooks/audiobookshelf-validation.md),
the app facts in
[`kubernetes/apps/base/audiobookshelf/README.md`](../../kubernetes/apps/base/audiobookshelf/README.md),
and the generic
[`docs/gitops-application-onboarding-playbook.md`](../gitops-application-onboarding-playbook.md).

---

## Context

The homelab is a single-node-class k3s cluster reconciled by Flux from
`ssh://git@github.com/GMakeziG/lab`, tracking branch `main`. Applications follow
a Kustomize **base → production overlay** pattern:

- `kubernetes/apps/base/<app>/` — reusable, environment-agnostic resources.
- `kubernetes/apps/production/<app>/` — environment specifics (namespace,
  ingress, hostnames), layered on top of base via `resources: [../../base/<app>]`.

Inbound public traffic does not use a cloud LoadBalancer. It arrives through a
single **shared Cloudflare Tunnel** (`homelab-k3s`,
`381367a6-bdca-44e3-b78e-285166692048`) running as the `cloudflared` Deployment
in the `platform` namespace, which forwards every published hostname to the
in-cluster Traefik ingress at `https://traefik.kube-system.svc.cluster.local:443`.
Existing hostnames on that tunnel already include `draw`, `linkding`, `qr`, and
`grafana`.

Secrets are normally sourced from OpenBao via External Secrets Operator (ESO).
A narrow exception exists for **bootstrap / break-glass** material that Flux
needs independent of OpenBao: SOPS + age, decrypted cluster-side by the
`sops-age` key through the `bootstrap-secrets` Flux Kustomization
(`kubernetes/bootstrap-secrets`, `prune: true`, `decryption.provider: sops`).
See [`docs/sops-age-bootstrap-recovery.md`](../sops-age-bootstrap-recovery.md).

## Problem

Onboarding ABS raised three decisions that needed to be recorded because each
carries operational and security consequences beyond ABS itself:

1. **Packaging** — deploy ABS via its community Helm chart, or via plain
   Kubernetes manifests?
2. **Ingress path** — stand up a second, ABS-dedicated Cloudflare tunnel, or
   reuse the existing shared `homelab-k3s` tunnel?
3. **Tunnel credential** — the shared tunnel's `cloudflared-tunnel-credentials`
   secret existed only as an **out-of-band, imperatively created** object
   (field manager `kubectl-create`), untracked by Git. Leave it out-of-band, or
   adopt it into GitOps?

---

## Decision 1 — Plain manifests over Helm

Deploy ABS as plain Kubernetes manifests (ConfigMap, PVCs, Deployment, Service
in base; Ingress in the production overlay). No Helm chart, no HelmRelease.

### Alternatives considered
- **Community/third-party Helm chart.** Rejected: adds an external
  dependency and templating indirection for an app whose entire surface is five
  resources; upgrades and value drift would be harder to audit than a flat diff.
- **Plain manifests (chosen).** The resource count is small and static, full
  control over `securityContext`, ports, and volumes is required, and a flat
  manifest diff is the clearest possible artifact for review and rollback.

### Rationale
ABS needs only a Deployment, ConfigMap, Service, four PVCs, and an Ingress.
Plain manifests match the repo's onboarding playbook guidance ("use plain
manifests when the app is simple / configuration is small / you need full
control"), keep the GitOps diff legible, and avoid a chart as a moving part.

## Decision 2 — Reuse the shared Cloudflare tunnel (do not create a second tunnel)

Publish `audiobookshelf.ninjatronics.io` by adding one `ingress` hostname entry
to the existing shared tunnel's config
(`kubernetes/infrastructure/base/cloudflared/configmap.yaml`), routing to
`https://traefik.kube-system.svc.cluster.local:443` with `noTLSVerify: true`.
The new entry is inserted **before** the terminal `- service: http_status:404`
catch-all, which remains last.

### Alternatives considered
- **A second, ABS-dedicated tunnel.** Rejected: a new tunnel means a new
  credential, a new `cloudflared` workload (or multi-tunnel config), and more
  moving parts, for no isolation benefit in a single-tenant homelab.
- **Reuse the shared tunnel (chosen).** One tunnel already fronts every homelab
  hostname through Traefik; ABS is just one more route.

### Rationale
Consistency with `draw`, `linkding`, `qr`, and `grafana`; minimal operational
surface; TLS is still terminated per-host by Traefik + cert-manager
(`letsencrypt-production-cloudflare`), so sharing the tunnel does not weaken
per-app TLS.

### Consequence / coupling risk
The tunnel is a **shared fate** component. A misconfiguration of the tunnel
config or its credential affects **all** hostnames on it, not just ABS. This
directly motivates Decision 3's guardrails and the M-2/M-3 gates below.

## Decision 3 — Adopt the out-of-band tunnel credential into SOPS/GitOps

Bring the previously out-of-band `cloudflared-tunnel-credentials` secret
(namespace `platform`) under Git as
`kubernetes/bootstrap-secrets/cloudflared-tunnel-credentials.enc.yaml`,
SOPS/age-encrypted to the repo recipient
(`age130mgpv4sdrfu7p7lg7sx4jh7u805w6w3lzsazlckf3pgdzfyuyssgmpjml`) and decrypted
cluster-side by the existing `sops-age` key via the `bootstrap-secrets` Flux
Kustomization.

### Alternatives considered
- **Leave it imperative / out-of-band.** Rejected: an untracked, imperatively
  created secret is invisible to review, undocumented, and a
  disaster-recovery hole — it would not be recreated by a clean Flux bootstrap.
- **Move it to OpenBao + ESO.** Rejected for now: tunnel credentials are
  exactly the "needed before/independent of OpenBao" bootstrap class the SOPS
  path exists for (per `docs/sops-age-bootstrap-recovery.md`).
- **SOPS/age adoption (chosen).** Puts the credential under version control and
  reproducible cluster-side decryption without introducing a runtime dependency
  on OpenBao for tunnel bring-up.

### Rationale
Eliminates the out-of-band drift, makes the credential auditable in a PR diff
(only `data`/`stringData` is ciphertext; metadata stays readable), and makes the
tunnel reproducible from Git on a clean bootstrap.

### Consequences
- On reconcile, Flux **owns and overwrites** the live `platform`
  `cloudflared-tunnel-credentials` secret. Because the tunnel is shared, the
  encrypted value **must** be byte-identical to the live, working
  `credentials.json`.
- The credential was **adopted, not rotated.** Rotation remains possible later
  (re-encrypt a fresh credential) but is explicitly out of scope here.

---

## Risks (residual — from PH6-SEN-001)

These are the accepted MEDIUM residual/operational risks. They are tracked in
full, with the exact validation gates, in the
[validation runbook](../runbooks/audiobookshelf-validation.md#sentinel-ph6-sen-001-residual-risks--manual-gates).

- **M-1 — Unproven write access (local-path + fsGroup:1000).** Running ABS
  non-root (UID/GID 1000) against `local-path` PVCs with `fsGroup: 1000` is
  architecturally sound but **unproven until a pod actually runs**. *Gate:* after
  Flux reconciles, confirm the pod is `Ready` and `/config` is writable
  (persistence test).
- **M-2 — Shared-tunnel credential parity.** The SOPS ciphertext could not be
  decrypted locally to prove byte-parity with the live credential. On reconcile
  Flux overwrites the live secret; a wrong re-encryption would break **every**
  tunnel hostname (`draw`, `linkding`, `qr`, `grafana`), not just ABS. *Gate:*
  confirm the ciphertext was derived from the exact live `credentials.json`
  **before merge**; after merge verify existing hostnames still resolve.
- **M-3 — Data-destructive rollback + shared-secret prune.** Rollback is
  manifest-clean via `git revert`, but the PVCs use `reclaimPolicy: Delete` and
  the overlay is `prune: true`, so a naive revert **deletes audiobook/podcast/
  config data**; reverting the bootstrap-secrets change could **prune the shared
  tunnel secret and break all tunnels**. *Mitigation:* rollback must exclude the
  PVCs and the tunnel secret, or back up data and retain the platform secret
  first.

### LOW hardening notes (accepted, non-blocking)
- No `readOnlyRootFilesystem` — ABS needs a writable `/tmp`; a future `emptyDir`
  for `/tmp` would let this be enabled.
- No `NetworkPolicy` — consistent with the current cluster baseline.
- ABS first run creates an **admin account with no prior authentication**.
  Claim the admin account immediately post-deploy, or gate the hostname behind
  temporary Traefik auth until claimed.

## Security and compliance impact

Reviewed under **PH6-SEN-001 — verdict PASS** (0 BLOCKER, 0 HIGH). The design
runs ABS non-root with a hardened `securityContext` (`runAsNonRoot`, UID/GID
1000, `fsGroup: 1000`, `seccompProfile: RuntimeDefault`,
`allowPrivilegeEscalation: false`, all capabilities dropped), keeps TLS
termination per-host at Traefik + cert-manager, and removes an out-of-band
secret from the cluster's trust surface by adopting it into SOPS/age. The three
MEDIUM findings above are **operational gates**, not code defects, and are
carried as known limitations with explicit pre-merge / post-merge checks.

## Review

Revisit this ADR if any of the following change:
- ABS grows beyond a handful of resources (reconsider Helm — Decision 1).
- A second ingress path or tenant-isolation requirement appears (reconsider the
  shared tunnel — Decision 2).
- The tunnel credential is rotated or migrated to OpenBao/ESO (Decision 3).
- The cluster gains a real StorageClass with `reclaimPolicy: Retain` or backups
  (revisit the M-3 data-loss posture).
