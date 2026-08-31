# Forgejo

Self-hosted Git service for lab and GitOps workflows, at
<https://git.ninjatronics.io>.

## Versions

| Component  | Pinned to      | Why                                                        |
| ---------- | -------------- | ---------------------------------------------------------- |
| Helm chart | `17.1.5`       | Latest chart; ships appVersion 15.0.7                       |
| Forgejo    | `15.0.7`       | v15.0 is the current LTS (2026-04-16 → EOL 2027-07-15)      |
| PostgreSQL | `17.11-alpine` | Matches the PostgreSQL major the chart shipped before v17   |

Forgejo v11.0 was the previous LTS and went EOL 2026-07-16. v16.0 is a regular
stable line (EOL 2026-10-29), not an LTS. `image.tag` is pinned explicitly so a
chart bump cannot silently move the deployment off the LTS line.

Chart source is the OCI registry `oci://code.forgejo.org/forgejo-helm`; there
is no classic index.yaml repository for this chart.

## Database

The Forgejo chart **no longer bundles PostgreSQL**. From the chart README
(§ "To v17"):

> PostgreSQL and PostgreSQL HA subcharts have been removed. You need to
> manually migrate to an external PostgreSQL instance.

So PostgreSQL is deployed from this directory as a plain Deployment, following
the existing `kubernetes/apps/base/firecrawl/nuq-postgres-*.yaml` pattern:
single replica, `strategy: Recreate`, standalone PVC, ClusterIP Service,
`pg_isready` probes, node affinity pin.

Connection details live in `gitea.config.database` (host, name, user); only the
password comes from a Secret, injected as `FORGEJO__DATABASE__PASSWD`.

## Persistence

Both PVCs use `local-path`, which is **node-local**. Both are pinned to
`niner` — the Forgejo pod via `nodeSelector`, PostgreSQL via `nodeAffinity` —
so the volumes land on the same node deterministically. `local-path` does not
support volume expansion, so neither PVC can be grown in place.

| PVC                     | Size | Holds                                                                                          |
| ----------------------- | ---- | ---------------------------------------------------------------------------------------------- |
| `forgejo-data`          | 20Gi | Git repositories, LFS objects, avatars, issue attachments, and the generated `gitea/conf/app.ini` |
| `forgejo-postgres-data` | 10Gi | All relational state: users, orgs, issues, PRs, comments, webhooks, access tokens, 2FA records    |

### What must be backed up

Both, and consistently with each other — a repository restored without its
matching database rows (or the reverse) leaves a broken instance.

- `forgejo-data` — repository content is only here; there is no second copy.
- `forgejo-postgres-data` — use `pg_dump`, not a raw volume copy of a running
  server.
- OpenBao `secret/apps/forgejo` — `secret-key` in particular. Forgejo uses it
  to encrypt 2FA secrets, OAuth tokens and mirror passwords **stored in the
  database**. Losing it makes that data unrecoverable even with both PVCs
  intact.

## Secrets

No secret values in Git. All come from OpenBao at `secret/apps/forgejo` via
External Secrets and the `openbao` ClusterSecretStore. See
`secret.example.yaml` for the key mapping.

The chart does not manage `SECRET_KEY`, `INTERNAL_TOKEN`, `JWT_SECRET` or
`LFS_JWT_SECRET` — Forgejo's init container generates them on first boot and
writes them into `app.ini` on the PVC. They are seeded from OpenBao via
`gitea.additionalConfigFromEnvs` so the instance is reproducible. Note that
`scripts/config_environment.sh` in the chart drops these four envs whenever an
`app.ini` already exists, so **changing them in OpenBao after first boot has no
effect** — `app.ini` stays authoritative.

## Networking

- Traefik Ingress, `letsencrypt-production-cloudflare` cluster issuer, TLS
  secret `git-ninjatronics-io-tls`.
- Reached publicly through the shared Cloudflare Tunnel; the routing rule lives
  in `kubernetes/infrastructure/base/cloudflared/configmap.yaml`.
- Both Services are ClusterIP. No NodePort, no LoadBalancer.
- TLS terminates at Traefik, so Forgejo speaks plain HTTP internally
  (`PROTOCOL: http`) while `ROOT_URL` is `https://git.ninjatronics.io/`.
- `REVERSE_PROXY_LIMIT: 1` trusts exactly one hop (Traefik). Because
  cloudflared sits in front of Traefik, logged client IPs read as the
  cloudflared pod IP. Raising the limit would make `X-Forwarded-For`
  client-spoofable, so this is deliberate.

## Git over SSH

Not exposed. `START_SSH_SERVER: false` and `DISABLE_SSH: true`, so HTTPS is the
only transport. The chart renders a `forgejo-ssh` ClusterIP Service
unconditionally; with no listener behind it, it is inert and unreachable from
outside the cluster.

To enable SSH later: drop those two settings, add a `tunnels`/TCP path or a
dedicated LoadBalancer for port 22, and set `gitea.config.server.SSH_PORT`
accordingly. Cloudflare Tunnel does not proxy raw SSH for `git` clients without
`cloudflared access` on the client side.

## Notable settings

- `DISABLE_REGISTRATION: true` — self-signup is off; the admin creates users.
- `OFFLINE_MODE: true` — no external CDN fetches for assets.
- `passwordMode: initialOnlyNoReset` — the OpenBao admin password seeds the
  account on creation and is not reapplied on every pod restart.
- Forgejo Actions is left at the upstream default. There are no runners
  registered, so it is inert; disable via `gitea.config.actions.ENABLED: false`
  if that changes.
