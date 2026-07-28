# Audiobookshelf

Self-hosted audiobook and podcast server, GitOps-managed via Flux.

## Documentation

- [GitOps Application Onboarding Playbook](../../../../docs/gitops-application-onboarding-playbook.md)
- [Audiobookshelf Validation Runbook](../../../../docs/runbooks/audiobookshelf-validation.md)

## App-specific details

- Official repository: https://github.com/advplyr/audiobookshelf
- Official docs: https://audiobookshelf.org/docs
- Image: `ghcr.io/advplyr/audiobookshelf:2.36.0`
  - Digest: `sha256:180acad33d69c99ed208676465d8edcb268fa46967735579a7810859885b1a8e`
- Port: `3005` (set via ConfigMap `PORT`; image default is `80`)
- ConfigMap `audiobookshelf-config`: `PORT=3005`, `TZ=America/Los_Angeles`,
  `CONFIG_PATH=/config`, `METADATA_PATH=/metadata`
- Volume mount paths / PVCs:
  - `/config`     -> `audiobookshelf-config`     (2Gi)
  - `/metadata`   -> `audiobookshelf-metadata`   (10Gi)
  - `/audiobooks` -> `audiobookshelf-audiobooks` (100Gi)
  - `/podcasts`   -> `audiobookshelf-podcasts`   (50Gi)
- StorageClass: `local-path` (RWO)
- Runtime user: `node`, UID `1000` / GID `1000` (non-root; `fsGroup: 1000`)
- Health endpoint: `GET /ping` -> `200 {"success":true}`
- Public URL: https://audiobookshelf.ninjatronics.io (via shared Cloudflare tunnel)

## Port-forward

```bash
kubectl -n apps port-forward svc/audiobookshelf 3005:3005
curl -I http://127.0.0.1:3005
```

## Persistence test, ingress/TLS, upgrade, rollback, troubleshooting

See the [validation runbook](../../../../docs/runbooks/audiobookshelf-validation.md).
