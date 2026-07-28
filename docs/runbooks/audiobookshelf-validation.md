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

## Deployment procedure (how it reconciles)

The live Flux `GitRepository` (`flux-system`) tracks branch **`main`**
(`kubernetes/clusters/production/flux-system/gotk-sync.yaml`). Nothing on
`feat/audiobookshelf` reconciles until that branch is the source. Once the
branch is merged to `main` (or an approved temporary source repoint is applied —
see [Remaining manual gates](#remaining-manual-gates)):

1. `flux-system` GitRepository pulls the new `main` revision.
2. The `bootstrap-secrets` Kustomization (dependsOn `namespaces`,
   `decryption.provider: sops`, `prune: true`) decrypts and applies
   `cloudflared-tunnel-credentials` into `platform`.
3. The `apps` Kustomization (dependsOn `infrastructure`, `path
   ./kubernetes/apps/production`, `prune: true`, `wait: true`) applies the ABS
   base + production overlay into the `apps` namespace.
4. cert-manager issues `audiobookshelf-ninjatronics-io-tls`; the pod becomes
   `Ready` once `/ping` returns 200.

Force a reconcile (after merge) instead of waiting for the 10m interval:

```bash
flux reconcile source git flux-system
flux reconcile kustomization apps --with-source
```

## Upgrade / rollback

- **Upgrade:** bump the image tag + digest in
  `kubernetes/apps/base/audiobookshelf/deployment.yaml`, commit, let Flux
  reconcile. Renovate may open the bump PR automatically. PVC data is retained
  across image changes (PVC names are stable interfaces).

- **Rollback (image only):** revert the image bump commit; Flux restores the
  prior revision. PVCs are untouched — safe.

- **Rollback (whole app / onboarding) — DESTRUCTIVE, read first.** Reverting the
  ABS onboarding commits is manifest-clean via `git revert`, **but it is
  data-destructive and can break the shared tunnel** (Sentinel M-3):
  - The four PVCs use `storageClassName: local-path` whose PVs are
    `reclaimPolicy: Delete`, and the `apps` Kustomization is `prune: true`.
    Reverting the PVC/base manifests makes Flux **prune the PVCs, which deletes
    the underlying audiobook / podcast / metadata / config data.**
  - Reverting the `bootstrap-secrets` change can **prune the shared
    `cloudflared-tunnel-credentials` secret**, which breaks **every** tunnel
    hostname (`draw`, `linkding`, `qr`, `grafana`), not just ABS.
  - **Safe rollback procedure:** exclude the PVCs and the tunnel secret from the
    revert (revert only the Deployment/Service/ConfigMap/Ingress/cloudflared-route
    manifests), **or** back up the PVC data and retain the `platform`
    `cloudflared-tunnel-credentials` secret *before* reverting. Never blindly
    `git revert` the whole feature branch against a live cluster.

## Sentinel (PH6-SEN-001) residual risks & manual gates

Security review **PH6-SEN-001 — verdict PASS** (0 BLOCKER, 0 HIGH). Three MEDIUM
residual/operational risks remain and are **manual gates**, not code defects.
See the ADR:
[`docs/decisions/0001-audiobookshelf-plain-manifests-shared-tunnel-sops-adoption.md`](../decisions/0001-audiobookshelf-plain-manifests-shared-tunnel-sops-adoption.md).

- **M-1 — write access unproven until a pod runs.** local-path + `fsGroup: 1000`
  granting non-root (UID/GID 1000) write to `/config` is sound but unverified
  offline. **Gate (post-reconcile):** pod is `Ready` and `/config` is writable:
  ```bash
  kubectl -n apps get pods -l app.kubernetes.io/name=audiobookshelf
  kubectl -n apps exec deploy/audiobookshelf -- id      # uid=1000 gid=1000
  kubectl -n apps exec deploy/audiobookshelf -- sh -c 'touch /config/.wtest && rm /config/.wtest && echo WRITABLE'
  ```
  Then run the [Persistence test](#persistence-test).

- **M-2 — shared-tunnel credential parity (PRE-MERGE gate).** The SOPS ciphertext
  in `cloudflared-tunnel-credentials.enc.yaml` could not be decrypted locally to
  prove byte-parity with the live credential. On reconcile Flux **overwrites**
  the live `platform` secret; a wrong re-encryption breaks **all** tunnel
  hostnames. **Gate (before merge):** confirm the ciphertext was derived from the
  exact live `credentials.json`. **Gate (after merge):** verify existing
  hostnames still resolve/serve:
  ```bash
  # before merge (host holding the plaintext / age key):
  #   sops -d kubernetes/bootstrap-secrets/cloudflared-tunnel-credentials.enc.yaml \
  #     | yq '.data."credentials.json"' | base64 -d | diff - /path/to/live/credentials.json
  # after merge:
  for h in draw linkding qr grafana audiobookshelf; do curl -sI https://$h.ninjatronics.io -o /dev/null -w "$h %{http_code}\n"; done
  kubectl -n platform logs deploy/cloudflared --tail=50   # no credential/tunnel errors
  ```

- **M-3 — rollback is data-destructive + can prune the shared secret.** Covered
  in [Upgrade / rollback](#upgrade--rollback) above. Do not `git revert` the PVCs
  or the tunnel secret against a live cluster without backing up first.

## Remaining manual gates (not yet done — environment-blocked)

1. **Flux source is `main`.** The `flux-system` GitRepository tracks branch
   `main`; `feat/audiobookshelf` will not reconcile until it is **merged to
   `main`** or an **approved temporary source repoint** is applied (Gerso's
   decision). Live reconcile is blocked until then.
2. **Cloudflare DNS does not resolve yet.** `audiobookshelf.ninjatronics.io` must
   be created as a proxied CNAME to
   `381367a6-bdca-44e3-b78e-285166692048.cfargotunnel.com`:
   ```bash
   cloudflared tunnel route dns homelab-k3s audiobookshelf.ninjatronics.io
   ```
   Run from a host holding the tunnel owner cert (`~/.cloudflared/cert.pem`) or
   add the CNAME in the Cloudflare dashboard. No CF token was available in the
   implementation environment.
3. **Draft PR not opened.** `gh` was not authenticated in the implementation
   environment; the PR for `feat/audiobookshelf` still needs to be created.

## Known limitations (LOW hardening — accepted, non-blocking)

- **No `readOnlyRootFilesystem`.** ABS needs a writable `/tmp`; a future
  `emptyDir` mount for `/tmp` would let this be enabled.
- **No `NetworkPolicy`.** Consistent with the current cluster baseline.
- **First-run admin is unauthenticated.** ABS creates the initial admin account
  with no prior auth. **Claim the admin account immediately after first
  deploy**, or gate `audiobookshelf.ninjatronics.io` behind temporary Traefik
  auth until it is claimed.

## Troubleshooting

```bash
kubectl -n apps describe deployment audiobookshelf
kubectl -n apps logs deploy/audiobookshelf --tail=100
kubectl -n apps describe pvc audiobookshelf-config
kubectl -n platform logs deploy/cloudflared --tail=50
```
