# TREK — base

Self-hosted trip planner: agenda, itinerary, lodging, flights, reservations,
notes, activities and trip documents.

Upstream: <https://github.com/liketrek/TREK>

## Deployment decision: plain manifests

An official Helm chart exists (`charts/trek/`, published to
`https://chart.liketrek.com`) and is competent, but it cannot express this
lab's required security posture. `charts/trek/templates/deployment.yaml` has no
container `securityContext`, no `seccompProfile`, no `serviceAccountName` or
`automountServiceAccountToken`, no `nodeSelector`, and — critically — no
`command`/`args` override, which is the exact knob needed to run the image
unprivileged (see *Security context* below).

Using a HelmRelease would mean either accepting a root container or patching
rendered Helm output with Kustomize. Plain manifests are fewer moving parts and
match the `termix` pattern already established in this repository, and the
decision table in `docs/gitops-application-onboarding-playbook.md` §2.

## Architecture

One container. There is nothing to split out.

| Layer | Implementation |
| --- | --- |
| Backend | NestJS 11 / Express 4 on Node 24 |
| Frontend | React SPA built into the image, served from `/app/server/public` |
| Database | **SQLite only** (`better-sqlite3`), `/app/data/travel.db`, WAL |
| Realtime | `ws` gateway on `/ws`, same HTTP server and port |
| Scheduled jobs | in-process `@nestjs/schedule` cron |
| Migrations | in-process at boot, 205 steps, before the server listens |
| Document parsing | `kitinerary-extractor` 6.3.3, bundled in the image |

No PostgreSQL, Redis, sidecar, worker, or migration Job. The cluster's existing
PostgreSQL is deliberately **not** used — TREK ships no PostgreSQL driver, so
this is not a preference.

## Image

```
docker.io/mauriceboe/trek:4.2.1@sha256:777f4d647e973fe7d87fecd957e854b86d57e8d977fd041763e0ca19b3c2e2c0
```

Published to **Docker Hub**, not GHCR (`.github/workflows/docker.yml`).
Multi-arch `linux/amd64` + `linux/arm64`; all cluster nodes are amd64.

Upstream cuts releases frequently and `latest`/`4`/`4.2.1` currently resolve to
the same index. **Pin the digest** — do not track a floating tag.

## Security context

The image's default `CMD` **cannot run unprivileged**. It ends in
`exec gosu node node …`, and `gosu` calls `setgroups()` unconditionally
(`tianon/gosu` → `setup-user.go:33`), which requires `CAP_SETGID`. Upstream's
own `docker-compose.yml` re-adds `CHOWN`, `SETUID` and `SETGID` for this
reason. Under `runAsNonRoot: true` with `capabilities.drop: [ALL]` the stock
command fails with:

```
error: failed switching to 'node': operation not permitted
```

The fix is to bypass `gosu` entirely — Kubernetes already does its job via
`runAsUser` and `fsGroup`, and `/app`, `/app/data`, `/app/uploads` are
`node`-owned (uid/gid 1000) in the image:

```yaml
workingDir: /app/server        # tsconfig-paths/register reads tsconfig.json from cwd
command: ["dumb-init", "--"]
args: ["node", "--require", "tsconfig-paths/register", "dist/index.js"]
```

With that override the following are all satisfied:

| Control | Status |
| --- | --- |
| `runAsNonRoot` / uid+gid 1000 | yes |
| `allowPrivilegeEscalation: false` | yes |
| `capabilities: drop [ALL]` | yes |
| `seccompProfile: RuntimeDefault` | yes |
| `readOnlyRootFilesystem: true` | yes — requires the `/tmp` emptyDir |
| `automountServiceAccountToken: false` | yes — TREK never calls the k8s API |

`readOnlyRootFilesystem` works because TREK writes only to `/app/data`,
`/app/uploads` and `/tmp`. The `/tmp` emptyDir is mandatory: the image sets
`XDG_CACHE_HOME=/tmp/kf6-cache` for kitinerary's Qt/KF6 stack.

No hostPath, privileged mode, Docker socket, hostNetwork, hostPID or hostIPC.

The third-party plugin runtime is disabled (`TREK_PLUGINS_ENABLED=false`). It
is **on** upstream by default and forks child Node processes from
`/app/data/plugins`.

## Storage

| PVC | Mount | Size | Contents |
| --- | --- | --- | --- |
| `trek-data` | `/app/data` | 20Gi | `travel.db` + WAL, `.encryption_key`, `.jwt_secret`, `logs/`, `backups/`, `tmp/` |
| `trek-uploads` | `/app/uploads` | 50Gi | `files/ covers/ avatars/ photos/ journey/ places/` |

The image symlinks `/app/server/data → /app/data` and
`/app/server/uploads → /app/uploads`; mount at the `/app/*` paths, never at
`/app` itself (a volume there hides the application code and the image's
preflight check aborts with a message saying so).

> **`local-path` in this cluster cannot expand volumes**
> (`ALLOWVOLUMEEXPANSION=false`). These sizes are effectively permanent —
> growing one means provisioning a new PVC and copying the data. The reclaim
> policy is `Delete`, so removing a PVC destroys its contents. Do not delete or
> recreate these PVCs while troubleshooting.

`trek-data` is oversized on purpose: TREK's own backups write to
`/app/data/backups`, and each archive bundles the database **plus the entire
uploads tree**.

## Scheduling — samson

`nodeSelector: kubernetes.io/hostname: samson`.

`local-path` binds a volume to whichever node first schedules the pod, so
pinning is a correctness requirement, not a convenience — without it a
reschedule leaves the pod `Pending` on a volume it cannot reach. The choice of
node is a capacity/failure-domain tradeoff:

| | niner | samson |
| --- | --- | --- |
| Allocatable ephemeral storage | ~71 GB | ~933 GB |
| Existing PVC requests | ~180 Gi | 162 Gi |

niner is heavily oversubscribed on disk (`local-path` does not enforce quotas),
and a disk-full event there would take down Prometheus, Forgejo, n8n, Termix
and Calibre together. TREK is upload-heavy and holds personal documents, so it
goes on samson.

**Consequence: samson is now TREK's storage and failure domain.** A samson
outage is a TREK outage, with no automatic failover. This is already true of
every `local-path` workload here; pinning only makes it explicit.

## Secrets

Runtime secrets come from OpenBao via External Secrets. The environment-overlay
`ExternalSecret` lives at
`kubernetes/apps/production/trek/external-secrets/trek-secret.yaml`.

`secret.example.yaml` is excluded by this repository's `.gitignore`, so the
expected keys are documented here instead.

**OpenBao path:** `secret/apps/trek` (KV v2). The `openbao`
`ClusterSecretStore` already mounts the `secret` engine, so `remoteRef.key` is
`apps/trek`.

| OpenBao property | Env var | Format | Lifecycle |
| --- | --- | --- | --- |
| `encryption-key` | `ENCRYPTION_KEY` | 64-char hex (32 bytes) | **Permanent, recovery-critical** |

`encryption-key` is the only secret this deployment consumes at runtime.

`ENCRYPTION_KEY` derives the AES-256-GCM keys for everything TREK stores
encrypted: TOTP/MFA secrets, SMTP password, OIDC client secret, S3 credentials,
per-user API keys and share-link passphrases. **Losing it makes all of those
permanently unreadable.** Trips, places and users are unaffected. Changing it
requires the interactive migration described in *Runbook* below — never edit it
in place.

Supplying it from the environment (rather than letting TREK auto-generate one
onto the PVC) has a second benefit: backup archives then **omit**
`.encryption_key`, because TREK only bundles the file when it is the source of
truth (`server/src/nest/backup/backup.impl.ts:257`). The archive is therefore
not self-decrypting — which also means **a restore is incomplete without
OpenBao**.

### Bootstrap-only secrets, since removed

`ADMIN_EMAIL` / `ADMIN_PASSWORD` seeded the first administrator. They are read
**only when the database has no users** (`server/src/db/seeds.ts:24-33`) and are
silently ignored on every later boot — the seeder logs a warning and skips.

They have been **removed from the `ExternalSecret`** now that bootstrap is
complete: the administrator exists, the bootstrap password has been changed,
TOTP is enrolled, and registration is closed and verified. Re-adding them would
have no effect on an initialised instance.

The pod was rolled at the same time (`lab/config-revision: "2"`), because
`envFrom` does not restart a pod when the referenced Secret changes — without
the roll the two variables would have stayed in the running container's
environment even after leaving the Secret.

The matching `admin-email` / `admin-password` properties in OpenBao are removed
separately by the operator; nothing in Git references them any more.

> Re-seeding a **fresh** instance (empty data PVC) would need them again. Add
> both back to the `ExternalSecret`, bump `lab/config-revision`, and remove them
> once the new admin exists.

> `JWT_SECRET` is **not** managed here and must never be set. TREK generates it
> into `/app/data/.jwt_secret` and rotates it from the admin panel; an env var
> would override a rotation on the next restart
> (`server/src/config.ts:100-118`).

> The initial admin password is printed to stdout in a startup banner
> (`server/src/db/seeds.ts:75-81`) whether supplied or generated, so it reaches
> the pod log and Loki. The account is created with `must_change_password=1`.
> Change it at first login and rotate the OpenBao value.

## Runbook

```bash
# Health (works over port-forward; login does not — see the note below)
kubectl -n trek port-forward svc/trek 3000:3000
curl -s http://127.0.0.1:3000/api/health          # {"status":"ok"}

# Registration / auth posture
curl -sk https://trek.ninjatronics.io/api/auth/app-config | jq \
  '{allow_registration, password_registration, oidc_registration}'

# Locked out of the admin account
kubectl -n trek exec deploy/trek -- node /app/server/reset-admin.js

# Rotate ENCRYPTION_KEY (interactive; takes its own DB backup first)
kubectl -n trek exec -it deploy/trek -- \
  sh -c 'cd /app/server && node --import tsx scripts/migrate-encryption.ts'

# Roll the pod after a ConfigMap change: bump lab/config-revision in
# deployment.yaml and commit. Do NOT use `kubectl rollout restart` — Flux
# reverts it on the next reconcile.
```

> **Port-forward cannot be used to log in.** With `NODE_ENV=production` the
> `trek_session` cookie carries `Secure`, so a browser on `http://localhost`
> silently discards it and login fails with "Access token required"
> (`server/src/nest/common/cookie.ts:60-69`). Use the HTTPS Ingress. Port-forward
> remains fine for `/api/health` and log inspection.

## Backups

TREK has a built-in backup (Admin → Backups; manual or scheduled with
retention) producing a ZIP of the checkpointed database plus the uploads tree,
written to `/app/data/backups`.

Two caveats:

1. **It backs up to the same PVC it protects.** A samson disk failure loses the
   data and the backups together. Copy archives off-cluster, or back up both
   PVCs at the volume level.
2. **The archive does not contain the encryption key** (see *Secrets*). A
   restore onto a fresh install must supply the same `ENCRYPTION_KEY` from
   OpenBao, or every stored secret and MFA enrolment is lost.

A raw copy of `travel.db` taken mid-write without its `-wal` file can be
inconsistent. Use TREK's backup (it checkpoints WAL first) or stop the pod.

## Upstream references

Paths below are relative to the upstream repository, inspected via OpenSrc at
`github:liketrek/TREK`. It is deliberately not vendored into this repository.

- `Dockerfile` — image layout, `gosu` entrypoint, `/app/{data,uploads}` symlinks
- `docker-compose.yml` — upstream's own hardening (`read_only`, `cap_drop: ALL`)
- `charts/trek/` — official chart; reference for probes and update strategy
- `server/src/app-config/env.schema.ts` — the complete environment surface
- `server/src/db/seeds.ts` — admin bootstrap
- `server/src/nest/auth/auth.service.ts` — registration toggles
- `server/src/config.ts` — `ENCRYPTION_KEY` / `JWT_SECRET` resolution
- `wiki/Security-Hardening.md` — upstream hardening checklist
