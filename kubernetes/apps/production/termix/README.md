# Termix production deployment

Self-hosted SSH / SFTP / tunnel management. Deployed as plain manifests rather
than the upstream Helm chart -- see "Why not the upstream chart" below.

Publicly reachable at <https://termix.ninjatronics.io> through the
`homelab-k3s` Cloudflare Tunnel, behind Cloudflare Access.

```
browser -> Cloudflare (Access) -> cloudflared -> Traefik (websecure)
        -> Service termix:8080 -> nginx -> Termix backend (loopback 30001)
```

Cloudflare Access is an **additional** authentication layer in front of
Termix's own login, never a replacement for it. Trusted proxy authentication
(`TRUSTED_PROXY_AUTH_ENABLED`) is deliberately not enabled -- upstream's own
compose file warns against it for anything reachable by untrusted clients.
Only port 8080 is routed. The backend's 30001-30012 are not in the Service,
and the `termix-ingress` NetworkPolicy blocks direct access to them (see
Security posture).

## Layout

| Path | Contents |
|---|---|
| `kubernetes/apps/base/termix/` | ServiceAccount, ConfigMap, PVC, Deployment, Service |
| `kubernetes/apps/production/termix/external-secrets/` | ExternalSecret backed by OpenBao |
| `kubernetes/apps/production/termix/ingress.yaml` | Traefik ingress + cert-manager TLS |
| `kubernetes/apps/production/termix/networkpolicy.yaml` | Ingress allowlist: TCP 8080 from Traefik only |
| `kubernetes/namespaces/termix.yaml` | Namespace |
| `kubernetes/infrastructure/base/cloudflared/config.yaml` | Tunnel hostname rule |

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
It is intentionally excluded from `kustomization.yaml`, and `.gitignore` also
ignores `**/secret.example.yaml`, so it exists only in working trees.

## Changing configuration

`envFrom` does not roll the pod when `termix-config` changes, and an imperative
`kubectl rollout restart` is reverted by Flux on its next reconcile. Bump the
`lab/config-revision` pod annotation in `deployment.yaml` in the same commit as
any `configmap.yaml` change so the new environment rolls out declaratively.

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

Enabled for RDP/VNC/Telnet (`src/backend/starter.ts:323`). SSH, SFTP, tunnels
and host monitoring still run through Termix's own SSH backend and do not
touch guacd. Source references are to the `release-2.7.0-tag` tag.

- **Sidecar, loopback only.** `guacamole/guacd:1.6.0` runs in the termix pod.
  The image entrypoint hardcodes `-b 0.0.0.0`, so the container invokes
  `/opt/guacamole/sbin/guacd -b 127.0.0.1 -l 4822` directly. guacd is not in
  the Service and is unreachable on the pod IP; probes use `nc -z 127.0.0.1`.
- **Jump tunnels stay on loopback.** `GUACD_HOST=127.0.0.1` makes
  `jump-tunnel-endpoint.ts` bind the SSH jump-tunnel listener to `127.0.0.1`.
  Any non-loopback `GUACD_HOST` would bind it to `0.0.0.0`.
  `GUACD_TUNNEL_HOST` is unset. The env vars override the in-app `guac_url`
  setting.
- **Runtime.** guacd runs as the image's own `guacd` user, uid/gid 1000 (same
  as Termix), with a read-only root filesystem, no capabilities, and emptyDirs
  for `/home/guacd` (FreeRDP config/cert store), `/tmp` and `/drive` (RDP drive
  redirection, `routes.ts:620`; ephemeral).
- **Recordings.** RDP/Telnet sessions are recorded when session logging is on
  for the host (VNC is never recorded). Termix sends guacd
  `recording-path=/app/data/session_recordings/guacamole` (`routes.ts:588`,
  both `GUACD_RECORDING_*` vars unset) and reads the file from the same path
  afterwards. guacd mounts only that directory of `termix-data`, via
  `subPath`, never the database or keys. The `recordings-dir` init container
  creates it as uid 1000 first, because kubelet would otherwise create a
  missing subPath non-writable.
- **No extra secret.** Without `GUACAMOLE_ENCRYPTION_KEY`, the connection-token
  key is derived from `JWT_SECRET` (`token-service.ts:86`), which already comes
  from OpenBao.
- **Network.** guacd connects to RDP/VNC targets from niner, so targets must
  be reachable from that node. The Guacamole WebSocket (30008) binds all
  interfaces and is closed off by the `termix-ingress` NetworkPolicy.

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

Only port 8080 (nginx) is in the Service. nginx reaches the backend over
loopback, but the backend does **not** bind loopback-only: in 2.7.0 most of
30001-30011 listen on all interfaces (30012 and guacd's 4822 are loopback).
Before `termix-ingress` they were reachable from any pod in the cluster,
bypassing Traefik and Cloudflare Access.

`networkpolicy.yaml` (`termix-ingress`) restricts ingress to the termix pod to
TCP 8080 from the Traefik pods in `kube-system`. That is the actual TCP peer:
cloudflared targets the Traefik Service. nginx's access log shows the
cloudflared IP only because `real_ip` rewrites `$remote_addr` from
`X-Forwarded-For`. Kubelet probes come from the node and are allowed by the
k3s kube-router controller. Egress is not restricted.

### Open hardening items

- **`ALLOW_REGISTRATION`.** Closed (`ALLOW_REGISTRATION=false` in
  `termix-config`). Registration defaults to open and the first account
  registered becomes admin (`src/backend/database/routes/users.ts:107`); it was
  open only for the initial admin bootstrap. The environment variable takes
  precedence over the in-database `allow_registration` setting, so it cannot be
  re-enabled from the UI without a Git change. Verify with
  `GET /users/registration-allowed`, which must report `{"allowed":false}`.
- **Egress NetworkPolicy.** Not implemented. Ingress is restricted by
  `termix-ingress`, but Termix's purpose is outbound SSH/RDP/VNC to arbitrary
  hosts, so a default-deny egress policy needs real design.
- **Cloudflare Access.** In place for `termix.ninjatronics.io`, in addition to
  Termix's own authentication, because Termix brokers administrative access to
  the homelab. It must stay in front of this hostname.

## Ingress and TLS

The Ingress carries `cert-manager.io/cluster-issuer:
letsencrypt-production-cloudflare`, so cert-manager's ingress-shim creates the
Certificate; there is no explicit Certificate manifest, matching every other
app here. The TLS Secret follows the repository convention of the hostname with
dots replaced by dashes: `termix-ninjatronics-io-tls`.

The cloudflared hostname rule lives in
`kubernetes/infrastructure/base/cloudflared/config.yaml`, before the
`http_status:404` catch-all, and points at Traefik like every other public app.
That file is consumed by a `configMapGenerator`, so editing it changes the
generated ConfigMap name and Flux rolls cloudflared automatically.

## Internal access without Cloudflare

```sh
kubectl port-forward -n termix svc/termix 8080:8080
```

Then open <http://127.0.0.1:8080>. Useful for diagnosing whether a problem is
in Termix or in the Cloudflare/Traefik path.

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
