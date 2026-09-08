# TREK — production overlay

Environment-specific resources for TREK. The reusable workload lives in
`kubernetes/apps/base/trek/`, which also carries the deployment decision,
architecture notes, storage tradeoffs, secret key documentation and runbook.

This overlay adds:

- `external-secrets/` — the `ExternalSecret` reading `secret/apps/trek` from OpenBao
- `ingress.yaml` — the Traefik HTTPS Ingress for `trek.ninjatronics.io`

## Phase 1 is internal only

TREK holds personal trip documents, and **upstream defaults public registration
to open** with no environment variable to close it (see *Registration* below).
Phase 1 therefore stays off the internet until the administrator has closed
registration by hand.

What that means concretely:

| | Status |
| --- | --- |
| Cloudflare Tunnel route | **none** — `infrastructure/base/cloudflared/config.yaml` untouched |
| Public A / CNAME for `trek.ninjatronics.io` | **none** |
| Cloudflare Access policy | **none** |
| NetworkPolicy | **none** (no precedent for app NetworkPolicies in this repo yet) |
| TLS certificate | issued, via Cloudflare **DNS-01** |

### How to reach it during Phase 1

There is **no split-horizon DNS in this lab**. AdGuard Home is deployed and
filtering, but it holds no rewrites for `ninjatronics.io` — it forwards upstream
and returns Cloudflare's public proxy addresses, identical to what a public
resolver returns. The LAN router does not forward DNS to AdGuard either. Every
other app in this cluster reaches Traefik by going out to Cloudflare and back
in through the Tunnel.

Rather than introduce a DNS architecture for one phase, Phase 1 uses a
**temporary hosts-file override on the operator's workstation**, which is the
convention documented in `docs/networking.md` §Local DNS:

```
10.99.0.242	trek.ninjatronics.io
```

`10.99.0.242` is the Traefik LoadBalancer address (MetalLB pool
`10.99.0.0/24`). Traefik routes by Host/SNI, so this is sufficient — verified
against an existing app with
`curl --resolve termix.ninjatronics.io:443:10.99.0.242`.

An AdGuard DNS rewrite was deliberately rejected. It would live on the
`adguard-conf` PVC as imperative state outside Git, would additionally require
repointing the workstation's resolver, and — most importantly — a standing
rewrite would send every LAN client straight to Traefik forever, silently
**bypassing Cloudflare Access** once Phase 2 puts it in front. A hosts line
that gets deleted does not have that failure mode.

> **The hosts-file line must be removed during Phase 2, before public
> validation.** Leaving it in place keeps that workstation bypassing Cloudflare
> Access.

### Why the certificate issues without public DNS

`letsencrypt-production-cloudflare` uses a **DNS-01** solver. cert-manager
creates a temporary `_acme-challenge.trek.ninjatronics.io` TXT record through
the Cloudflare API and removes it after validation. No A or CNAME record is
involved, so a valid public-CA certificate is obtained with zero public
exposure.

### Why not port-forward

With `NODE_ENV=production` the `trek_session` cookie carries `Secure`, so a
browser on `http://localhost:3000` silently discards it and login fails with
"Access token required". Real HTTPS is required for the bootstrap login.
Port-forward remains fine for `/api/health` and log inspection.

## Registration — the reason Phase 1 is gated

Verified against a fresh instance: `POST /api/auth/register` succeeds
anonymously with **HTTP 201**, and `GET /api/auth/app-config` reports
`allow_registration: true`.

There is **no environment variable** that closes registration. The complete
environment surface is `server/src/app-config/env.schema.ts`, and it contains no
`ALLOW_REGISTRATION` equivalent. The toggle lives only in the `app_settings`
SQLite table, written from Admin → Settings.

The two apparent escape hatches do not apply:

- `OIDC_ONLY=true` does close registration, but needs an OIDC issuer and client
  ID. **This cluster has no OIDC provider.**
- `TREK_MANAGED=true` must **not** be set — it does not set values, it locks the
  admin out of them, and `allow_registration` is on its locked list
  (`server/src/nest/common/managed.ts:126`).

Closing registration is therefore a **mandatory manual post-deployment step**,
performed by the administrator in the UI. Until it is done and verified, TREK
must not be exposed publicly.

## Bootstrap sequence

1. Add the hosts-file line above on the workstation running the browser.
2. Browse to <https://trek.ninjatronics.io> and sign in with the seeded
   administrator credentials from `secret/apps/trek`.
3. Change the bootstrap password — TREK forces this
   (`must_change_password=1`).
4. Admin → Settings: disable **password registration** and **OIDC
   registration**.
5. Enable **TOTP MFA** on the administrator account.
6. Verify:

   ```bash
   curl -sk https://trek.ninjatronics.io/api/auth/app-config | jq \
     '{allow_registration, password_registration, oidc_registration}'
   # all three must be false
   ```

7. Negative registration test — must return **403**, not 201:

   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' \
     -X POST https://trek.ninjatronics.io/api/auth/register \
     -H 'Content-Type: application/json' \
     -d '{"username":"regprobe","email":"regprobe@example.invalid","password":"Nv3r-Cr3at3d!"}'
   ```

8. Rotate `admin-password` in OpenBao — the seeded value is printed to the pod
   log at first boot and therefore reaches Loki.

Only after steps 6 and 7 pass may Phase 2 be considered.

## Follow-up changes already identified

- **Remove `ADMIN_EMAIL` / `ADMIN_PASSWORD`** from
  `external-secrets/trek-secret.yaml` once bootstrap is complete, then remove
  the two properties from OpenBao. They are read only when the database has no
  users and are ignored thereafter. `encryption-key` stays permanently.
- **Phase 2 (not authorized):** Cloudflare Access → Cloudflare Tunnel → Traefik
  → TREK login + TOTP. Requires a `cloudflared` ingress rule, a Cloudflare DNS
  Tunnel record, an Access policy, and removal of the hosts-file line.
  Note Cloudflare's free plan caps request bodies at 100 MB while TREK allows
  500 MB uploads — do backup restores over port-forward, not the public
  hostname.
- **NetworkPolicy:** worth adding for a workload holding personal documents,
  but it would be this repository's first app NetworkPolicy and belongs in its
  own change.
