# Termix production deployment

Self-hosted SSH / SFTP / tunnel management. Deployed as plain manifests rather
than the upstream Helm chart -- see "Why not the upstream chart" below.

Phase 1 is **internal only**: ClusterIP on port 8080, no Ingress, no Traefik
route, no cloudflared route, no Cloudflare DNS, no Cloudflare Access. Public
exposure is Phase 2 and is not authorised yet.

## Layout

| Path | Contents |
|---|---|
| `kubernetes/apps/base/termix/` | ServiceAccount, ConfigMap, PVC, Deployment, Service |
| `kubernetes/apps/production/termix/external-secrets/` | ExternalSecret backed by OpenBao |
| `kubernetes/namespaces/termix.yaml` | Namespace |

## Image

```
ghcr.io/lukegus/termix:release-2.7.0@sha256:be6080b9d4b282984bd9ffc280d1d9fd30b22539adb33853c44d783343c83d33
```

Note the registry: the published image is `ghcr.io/lukegus/termix`, not the
`ghcr.io/termix-ssh/termix` that the upstream chart defaults to (that path does
not exist). Upstream also tags releases `release-<version>`; there is no bare
`2.7.0` tag.

## Secrets

OpenBao KV v2 path `secret/apps/termix`. The ClusterSecretStore `openbao`
mounts the `secret` path, so `remoteRef.key` is `apps/termix`.

| OpenBao property | Env var | Required format |
|---|---|---|
| `jwt-secret` | `JWT_SECRET` | >= 64 characters |
| `database-key` | `DATABASE_KEY` | exactly 64 hex characters |
| `encryption-key` | `ENCRYPTION_KEY` | exactly 64 hex characters |
| `internal-auth-token` | `INTERNAL_AUTH_TOKEN` | >= 32 characters |

**These must exist before the first pod starts.** All four are validated in
`src/backend/utils/system-crypto.ts`. A missing or malformed value does not
raise an error -- Termix generates its own replacement and writes it to
`/app/data/.env`. That would move the encryption keys out of OpenBao onto the
PVC, and re-introducing the OpenBao values afterwards would leave the database
and stored SSH credentials undecryptable.

The `eso-apps` OpenBao policy needs read on `secret/data/apps/termix` and
`secret/metadata/apps/termix`.

Verify key names only, never values:

```sh
kubectl get externalsecret termix-secret -n termix
kubectl get secret termix-secret -n termix -o jsonpath='{.data}' | jq 'keys'
```

`kubernetes/apps/base/termix/secret.example.yaml` documents the expected keys.
It is intentionally excluded from `kustomization.yaml`.

## Storage and encryption at rest

One PVC, `termix-data`, 20Gi, `local-path`, ReadWriteOnce, mounted at
`/app/data`. The workload is pinned to `niner` with a `kubernetes.io/hostname`
nodeSelector; `local-path` is `WaitForFirstConsumer`, so the pin makes the
binding deterministic instead of "wherever it first scheduled".

`local-path` on this cluster has `ALLOWVOLUMEEXPANSION: false`. The PVC cannot
be grown in place, so do not delete or recreate it during troubleshooting.

Termix runs SQLite **in memory** (`src/backend/database/db/index.ts:38`) and
persists it as an AES-256-GCM blob at `/app/data/db.sqlite.encrypted`, keyed by
`DATABASE_KEY`. Stored SSH credentials are additionally wrapped with per-user
data-encryption keys under `ENCRYPTION_KEY`.

Two consequences:

- The snapshot is flushed on a **5-minute dirty timer** and on SIGTERM. A
  `--force` pod delete can lose up to five minutes of changes. Delete pods
  normally and let the grace period run.
- A PVC backup alone is not restorable. You need the OpenBao values too.

## Guacamole

Not deployed. `guacd` serves RDP/VNC/Telnet only
(`src/backend/starter.ts:320`); SSH, SFTP, tunnels and host monitoring all run
through Termix's own SSH backend. `ENABLE_GUACAMOLE=false` stops the backend
loading the Guacamole server, and `GUACD_HOST`/`GUACD_PORT` are left unset,
which `src/backend/utils/guacd-config.ts:57` treats as "no guacd".

Re-enabling is additive: a `guacamole/guacd` sidecar, `GUACD_HOST=127.0.0.1`,
the `GUACD_*` recording paths, and a `GUACAMOLE_ENCRYPTION_KEY` secret.

## Security posture

Non-root (uid/gid 1000), `runAsNonRoot`, `fsGroup: 1000`,
`allowPrivilegeEscalation: false`, all capabilities dropped,
`seccompProfile: RuntimeDefault`, dedicated ServiceAccount with
`automountServiceAccountToken: false`. No hostPath, hostNetwork, hostPID,
hostIPC, Docker socket or privileged container. Termix manages Docker/Podman
over SSH, not through a mounted socket.

The image declares no `USER`; `docker/entrypoint.sh` normally starts as root
and `gosu`-drops to uid 1000. Starting as 1000 makes it skip the root branch
and reach the same end state, since the image directories are already owned by
`node:node` and `fsGroup` covers the volume.

`readOnlyRootFilesystem` is **false**, deliberately. `docker/entrypoint.sh`
renders the nginx config into `/tmp/nginx` and unconditionally rewrites
`/app/html/**/sw.js` with `sed -i` on every start. Both live in the image root
filesystem, not on the data volume, so an emptyDir cannot substitute.

Only port 8080 (nginx) is exposed. The backend listens on 30001-30012 but
nginx reaches it over loopback, so those stay off the Service.

### Open hardening items

- **`ALLOW_REGISTRATION`.** Registration defaults to open and the first user
  registered becomes admin (`src/backend/database/routes/users.ts:107`). It is
  open only for the initial admin bootstrap and must be set to `false` before
  any exposure.
- **NetworkPolicy.** Not implemented. Termix's purpose is outbound SSH to
  arbitrary hosts, so a default-deny egress policy needs real design. Treat
  "default-deny ingress except Traefik" as a Phase 2 prerequisite.
- **Cloudflare Access.** Mandatory for Phase 2, in addition to Termix's own
  authentication, because Termix brokers administrative access to the homelab.

## Temporary internal access

```sh
kubectl port-forward -n termix svc/termix 8080:8080
```

Then open <http://127.0.0.1:8080>.

## Why not the upstream chart

`charts/termix` exists upstream but is not consumable:

- It is never published. `.github/workflows/helm.yml` pushes only on a manual
  `workflow_dispatch`, and `oci://ghcr.io/termix-ssh/charts/termix` does not
  exist.
- Its default image repository (`ghcr.io/termix-ssh/termix`) does not exist,
  and its default tag (`appVersion` `2.7.0`) is not a real tag.
- It only models `JWT_SECRET`, `DATABASE_URL` and `GUACAMOLE_ENCRYPTION_KEY`.
  It has no way to inject `DATABASE_KEY`, `ENCRYPTION_KEY` or
  `INTERNAL_AUTH_TOKEN`, so those would silently self-generate onto the PVC.

Consuming it would mean a Flux `GitRepository` clone of the whole upstream
application repo, then overriding the image, tag, secrets, securityContext,
guacd and node placement -- nearly everything the chart provides.

## Common operations

```sh
kubectl get pods -n termix -o wide
kubectl get pvc -n termix
kubectl logs -n termix deploy/termix
kubectl describe externalsecret termix-secret -n termix

flux reconcile kustomization apps --with-source
```
