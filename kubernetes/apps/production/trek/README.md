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
performed by the administrator after first boot — partly in the UI and partly
through the admin API, for the reason in the next section. Until it is done and
verified, TREK must not be exposed publicly.

### OIDC registration defaults to ENABLED and is hidden in the UI

Closing password registration is **not sufficient**. `oidc_registration` is a
separate toggle that defaults to enabled, and the admin panel does not show it
on an instance with no OIDC provider configured.

`server/src/nest/auth/auth.service.ts:170` treats an **absent** `app_settings`
row as enabled:

```js
oidc_registration: get('oidc_registration') !== 'false',   // row absent -> true
```

and the public `allow_registration` flag is derived from both
(`auth.service.ts:292`):

```js
allow_registration: isDemo ? false : (toggles.password_registration || toggles.oidc_registration)
```

so `allow_registration` stays `true` while `oidc_registration` is unset, even
with password registration switched off.

**The control is not rendered when OIDC is unconfigured.** In
`client/src/pages/admin/AdminSettingsTab.tsx:86` and `:106`, both the *SSO
Login* and *SSO Registration* switches are wrapped in `{oidcConfigured && (…)}`.
With no `OIDC_ISSUER` / `OIDC_CLIENT_ID` this instance reports
`oidc_configured: false`, so neither switch appears in Admin → Settings and the
setting cannot be changed from the UI at all. It is still writable through the
API — `oidc_registration` and `oidc_login` are both in `ADMIN_SETTINGS_KEYS`
(`server/src/nest/auth/auth.helpers.ts:37`) — via `PUT /api/auth/app-settings`
as an authenticated administrator.

Both rows have been written explicitly on this instance:

| `app_settings` key | Value | Why |
| --- | --- | --- |
| `password_registration` | `"false"` | closes self-service password signup |
| `oidc_registration` | `"false"` | **required** — the absent-row default is `true` |
| `oidc_login` | `"false"` | intentionally off until an OIDC provider is deliberately configured |

`password_login` remains enabled and `passkey_login` remains off, both at their
upstream defaults (rows absent).

> **`oidc_registration` must be `false` before any public exposure**, and it
> **must be re-checked before configuring an OIDC provider in future.** While no
> IdP exists the flag is inert — the entry point refuses — so a stale `true`
> causes no visible symptom and is easy to miss. The day an issuer and client ID
> are configured, a `true` value means anyone who can authenticate to that IdP
> can self-register into TREK, silently. Treat verifying it as a precondition of
> both Phase 2 and any future SSO work.

Verify the whole posture in one call:

```bash
curl -sk https://trek.ninjatronics.io/api/auth/app-config | jq \
  '{allow_registration, password_registration, oidc_registration, oidc_login, oidc_configured}'
# all five must be false
```

## Bootstrap sequence

1. Add the hosts-file line above on the workstation running the browser.
2. Browse to <https://trek.ninjatronics.io> and sign in with the seeded
   administrator credentials from `secret/apps/trek`.
3. Change the bootstrap password — TREK forces this
   (`must_change_password=1`).
4. Admin → Settings: disable **password registration**.
5. Disable **OIDC registration** (and **OIDC login**). These have no UI control
   on an instance without an OIDC provider — see *OIDC registration defaults to
   ENABLED* above — so they must be set through the authenticated admin API.
   From the browser devtools console on a logged-in TREK tab (the session
   cookie is `httpOnly`, so the request has to originate from the page):

   ```js
   await fetch('/api/auth/app-settings', {
     method: 'PUT',
     credentials: 'include',
     headers: { 'Content-Type': 'application/json' },
     body: JSON.stringify({ oidc_registration: false, oidc_login: false })
   }).then(r => r.json())    // -> {success: true}
   ```

6. Enable **TOTP MFA** on the administrator account.
7. Verify:

   ```bash
   curl -sk https://trek.ninjatronics.io/api/auth/app-config | jq \
     '{allow_registration, password_registration, oidc_registration, oidc_login, oidc_configured}'
   # all five must be false
   ```

8. Negative registration test — must return **403**, not 201, and must not
   create a user:

   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' \
     -X POST https://trek.ninjatronics.io/api/auth/register \
     -H 'Content-Type: application/json' \
     -d '{"username":"regprobe","email":"regprobe@example.invalid","password":"Nv3r-Cr3at3d!"}'
   ```

9. Remove the bootstrap-only `ADMIN_EMAIL` / `ADMIN_PASSWORD` mappings from
   `external-secrets/trek-secret.yaml` and bump `lab/config-revision` in the
   base Deployment so the pod rolls — `envFrom` does not restart a pod when the
   referenced Secret changes, so without the bump the variables would remain in
   the running container. Then remove the `admin-email` / `admin-password`
   properties from OpenBao. **Done** — see *Bootstrap secrets* below.

Only after steps 7 and 8 pass may Phase 2 be considered.

## Bootstrap secrets — removed

`ADMIN_EMAIL` and `ADMIN_PASSWORD` seeded the first administrator and are read
only while the database has no users (`server/src/db/seeds.ts:24-33`). Bootstrap
is complete — the administrator exists, the bootstrap password was changed,
TOTP is enrolled, and registration is closed and verified — so both mappings
have been removed from the `ExternalSecret` and the pod rolled.

`ENCRYPTION_KEY` is untouched and remains the only secret TREK consumes at
runtime. It is permanent and recovery-critical; see the base README.

The generated `trek-secret` therefore now contains exactly one key:
`ENCRYPTION_KEY`.

Nothing in Git references `admin-email` or `admin-password` any more, so those
two properties can be deleted from `secret/apps/trek` in OpenBao. Deleting them
is safe on an initialised instance and is done by the operator, not by Flux.

## Follow-up changes already identified
- **Phase 2 (not authorized):** Cloudflare Access → Cloudflare Tunnel → Traefik
  → TREK login + TOTP. Requires a `cloudflared` ingress rule, a Cloudflare DNS
  Tunnel record, an Access policy, and removal of the hosts-file line.
  **Precondition:** re-run the five-flag check above — `allow_registration`,
  `password_registration`, `oidc_registration`, `oidc_login` and
  `oidc_configured` must all still be `false`. These live in SQLite on the data
  PVC, not in Git, so Flux will not restore them if they drift or if the volume
  is ever restored from an early backup.
  Note Cloudflare's free plan caps request bodies at 100 MB while TREK allows
  500 MB uploads — do backup restores over port-forward, not the public
  hostname.
- **Future OIDC/SSO work:** before configuring an issuer and client ID, confirm
  `oidc_registration` is `false`. Configuring an IdP while it is `true` opens
  self-registration to anyone who can authenticate there, with no visible
  symptom beforehand.
- **NetworkPolicy:** worth adding for a workload holding personal documents,
  but it would be this repository's first app NetworkPolicy and belongs in its
  own change.
