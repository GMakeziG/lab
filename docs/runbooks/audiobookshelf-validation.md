# Audiobookshelf — Validation Runbook

GitOps-managed deployment of Audiobookshelf on the production k3s cluster.
All changes flow through Flux; no imperative `kubectl apply`.

## Facts (verified against the image, not assumed)

- Image: `ghcr.io/advplyr/audiobookshelf:2.36.0`
  - Digest: `sha256:180acad33d69c99ed208676465d8edcb268fa46967735579a7810859885b1a8e`
  - Verified with `docker inspect`: default `USER` is root (empty), exposed
    port `80`, env `PORT=80`, `CONFIG_PATH=/config`, `METADATA_PATH=/metadata`.
  - `node` user is UID `1000` / GID `1000`.
- Listen port is driven by the `PORT` env var. The ConfigMap sets `PORT=3005`,
  so the container binds `:3005` (verified by a local run:
  `INFO: Listening on port :3005`).
- Health endpoint: `GET /ping` -> `200 {"success":true}` (used by probes).
- Audiobookshelf does NOT use PUID/PGID. Non-root is achieved with a
  Kubernetes securityContext + `fsGroup`.

## Resources

| Kind        | Name                              | Namespace | Notes                          |
| ----------- | --------------------------------- | --------- | ------------------------------ |
| ConfigMap   | audiobookshelf-config             | apps      | PORT=3005, TZ, CONFIG/METADATA |
| Deployment  | audiobookshelf                    | apps      | 1 replica, Recreate strategy   |
| Service     | audiobookshelf (ClusterIP)        | apps      | port 3005 -> targetPort http   |
| PVC         | audiobookshelf-config    (2Gi)    | apps      | /config                        |
| PVC         | audiobookshelf-metadata  (10Gi)   | apps      | /metadata                      |
| PVC         | audiobookshelf-audiobooks (100Gi) | apps      | /audiobooks                    |
| PVC         | audiobookshelf-podcasts  (50Gi)   | apps      | /podcasts                      |
| Ingress     | audiobookshelf                    | apps      | audiobookshelf.ninjatronics.io |

StorageClass: `local-path` (default, RWO, WaitForFirstConsumer). Single replica
with `Recreate` strategy avoids two pods contending for an RWO volume.

Security context: `runAsNonRoot: true`, `runAsUser/Group: 1000`, `fsGroup: 1000`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, all caps
dropped.

## Kustomize validation (offline)

```bash
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
kubectl kustomize kubernetes/apps/base/audiobookshelf
kubectl kustomize kubernetes/apps/production
kubectl kustomize kubernetes/infrastructure/production
kubectl kustomize kubernetes/clusters/production
kubectl kustomize kubernetes/bootstrap-secrets
```

## Server-side dry-run (no apply, no persistence)

```bash
flux diff kustomization apps --path ./kubernetes/apps/production
flux diff kustomization infrastructure --path ./kubernetes/infrastructure/production
```

## Post-reconcile validation (run after Flux applies the change)

```bash
flux get kustomizations
kubectl -n apps get deployment audiobookshelf
kubectl -n apps get pods -l app.kubernetes.io/name=audiobookshelf
kubectl -n apps get svc audiobookshelf
kubectl -n apps get pvc
kubectl -n apps get ingress audiobookshelf
kubectl -n apps exec deploy/audiobookshelf -- id     # expect uid=1000(node) gid=1000(node)
```

## Port-forward smoke test

```bash
kubectl -n apps port-forward svc/audiobookshelf 3005:3005
curl -I http://127.0.0.1:3005        # expect HTTP/1.1 200 OK
curl -s http://127.0.0.1:3005/ping   # expect {"success":true}
# Browser: http://127.0.0.1:3005 -> complete initial setup, create a library,
# upload one small non-sensitive test audio file (do NOT commit the file to Git).
```

## Persistence test

```bash
kubectl -n apps get pods -l app.kubernetes.io/name=audiobookshelf   # record pod name
kubectl -n apps delete pod <pod-name>          # allowed; do not manually recreate
kubectl -n apps rollout status deploy/audiobookshelf
# Re-open the UI: confirm account, library, metadata, and test audio persist.
```

## Public URL

```bash
curl -I https://audiobookshelf.ninjatronics.io    # expect 200/302 once DNS + tunnel live
```

## Cloudflare

- Tunnel reused: `homelab-k3s` / `381367a6-bdca-44e3-b78e-285166692048`.
- ConfigMap route added (before terminal `http_status:404`).
- DNS: `audiobookshelf.ninjatronics.io` must have a CNAME to
  `381367a6-bdca-44e3-b78e-285166692048.cfargotunnel.com` (proxied). Create with:
  ```bash
  cloudflared tunnel route dns homelab-k3s audiobookshelf.ninjatronics.io
  ```
  Run from a host with the tunnel owner cert (`~/.cloudflared/cert.pem`), or add
  the CNAME in the Cloudflare dashboard.

## Secrets

`cloudflared-tunnel-credentials` (namespace `platform`) is now GitOps-managed:
`kubernetes/bootstrap-secrets/cloudflared-tunnel-credentials.enc.yaml`,
SOPS/age-encrypted with the repo recipient, decrypted cluster-side by the
existing `sops-age` key via the `bootstrap-secrets` Flux Kustomization.

## Upgrade / rollback

- Upgrade: bump the image tag + digest in
  `kubernetes/apps/base/audiobookshelf/deployment.yaml`, commit, let Flux
  reconcile. Renovate may open the bump PR automatically.
- Rollback: revert the commit; Flux restores the prior revision. PVC data is
  retained across image changes (PVC names are stable interfaces).

## Troubleshooting

```bash
kubectl -n apps describe deployment audiobookshelf
kubectl -n apps logs deploy/audiobookshelf --tail=100
kubectl -n apps describe pvc audiobookshelf-config
kubectl -n platform logs deploy/cloudflared --tail=50
```
