# Calibre runbook

Calibre is an internal-only, single-replica content server. It runs on `niner`
with two `local-path` RWO volumes and is available through Traefik at
`https://calibre.internal`. There is no public DNS record, Cloudflare Tunnel
route, or Cloudflare Access application for this service.

## Prerequisites

- `calibre.internal` resolves to an internal Traefik address (for example via
  internal DNS or `/etc/hosts`).
- The `lab-selfsigned` ClusterIssuer is ready and its CA is trusted by clients.
- OpenBao contains `secret/apps/calibre` with `username` and `password` keys.
- `ghcr.io/ninjatronics/calibre-server:9.14.0` is published, or that exact
  locally built tag has been imported into k3s containerd on `niner`.

Create the credentials with an authenticated OpenBao session; replace the
placeholders rather than committing values to Git:

```sh
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$BAO_TOKEN" \
  bao kv put secret/apps/calibre \
  username='<calibre-username>' \
  password='<strong-random-password>'
```

Verify metadata without reading secret values:

```sh
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$BAO_TOKEN" \
  bao kv metadata get secret/apps/calibre
```

## Build and deploy

Build the image from `containers/calibre`:

```sh
make -C containers/calibre build
```

If GHCR is unavailable, import the image on the selected node:

```sh
docker save ghcr.io/ninjatronics/calibre-server:9.14.0 | \
  ssh niner sudo k3s ctr images import -
```

Commit changes to `main`; do not use `kubectl apply`. Flux reconciles the
namespace and production application aggregations automatically. Observe it:

```sh
flux reconcile source git flux-system
flux reconcile kustomization namespaces --with-source
flux reconcile kustomization apps --with-source
kubectl get externalsecret,secret -n calibre
kubectl get deployment,pod,pvc,service,ingress -n calibre -o wide
kubectl rollout status deployment/calibre -n calibre --timeout=5m
```

The ExternalSecret must report Ready before the Deployment can start. The two
PVCs bind only when the pod is scheduled because `local-path` uses
`WaitForFirstConsumer`.

## Access and health

Browse to `https://calibre.internal` and sign in with the OpenBao-managed
credentials. For an in-cluster service check:

```sh
kubectl run calibre-check -n calibre --rm -i --restart=Never \
  --image=curlimages/curl -- \
  curl --fail --silent --show-error http://calibre:8080/
```

Inspect failures without exposing secret values:

```sh
kubectl describe pod -n calibre -l app.kubernetes.io/name=calibre
kubectl logs -n calibre deployment/calibre
kubectl describe externalsecret calibre-secret -n calibre
```

## Backup and restore

Back up both PVCs together while Calibre is stopped so the library database,
user database, and configuration are consistent. Scale-down and scale-up must
be performed through a temporary Git commit and Flux reconciliation, never by
deleting the PVCs. Archive `/config` and `/library` from a maintenance pod
pinned to `niner`, then copy the archive to storage outside the cluster.

For restore, keep the Deployment scaled to zero through Git, restore both
archives to their existing claims with ownership `10001:10001`, and then
restore the replica count through Git. Never recreate or delete the claims as
a rollback mechanism: the `local-path` reclaim policy is `Delete`.

## Upgrade

1. Check the current stable release on the official Calibre site.
2. Update `CALIBRE_VERSION` and the independently calculated archive SHA-256
   in `containers/calibre/Dockerfile`.
3. Build and smoke-test the image, publish it or import it on `niner`, and
   update the Deployment image tag.
4. Render the base, production overlay, namespace aggregation, and production
   aggregation with `kubectl kustomize`.
5. Commit to `main`, reconcile through Flux, and confirm the rollout and logs.

## Rollback

Revert the Git commit that changed the image or manifests and let Flux
reconcile. Because the Deployment uses `Recreate`, expect a short outage. If
the prior image was node-local, confirm that exact tag is still present on
`niner` before reverting. A schema-incompatible Calibre downgrade may require
restoring the coordinated `/config` and `/library` backup; do not delete or
recreate either PVC.
