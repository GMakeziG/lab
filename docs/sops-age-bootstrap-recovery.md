# SOPS + age: Bootstrap & Emergency Recovery Secrets

## Scope

This mechanism exists for **one purpose only**: encrypting the small set of
secrets Flux needs before, or independent of, OpenBao + External Secrets
Operator (ESO) being reachable. Examples: bootstrap credentials needed on a
fresh cluster before OpenBao is unsealed and ESO is running, or a break-glass
secret used during disaster recovery.

**This is not a replacement for OpenBao.** OpenBao + ESO remain the preferred
and default secret store for all application/runtime secrets — see
`docs/architecture.md` and the "Secrets Architecture" section of
`CLAUDE.md`. Do not migrate existing OpenBao-backed secrets to SOPS.

| | OpenBao + ESO | SOPS + age |
|---|---|---|
| Use for | App/runtime secrets | Bootstrap / emergency recovery only |
| Where secret lives | OpenBao KV v2 | Encrypted in Git |
| When it must work | Cluster steady-state | Before OpenBao/ESO exist, or when they're unreachable |

## How it works

```
Plaintext Secret manifest
  ↓  sops --encrypt (age recipient)
Encrypted Secret manifest (committed to Git)
  ↓  Flux Kustomization (spec.decryption.provider: sops)
  ↓  reads age private key from Secret "sops-age" in flux-system
Decrypted Kubernetes Secret (applied to cluster, never written back to Git)
```

Only the `data` and `stringData` fields of a Kubernetes `Secret` are
encrypted (see `encrypted_regex` in `.sops.yaml`). `metadata`, `kind`, `type`,
etc. stay in plaintext so the file is still readable/reviewable in a PR diff.

## Repo layout

- `.sops.yaml` — SOPS config. Scopes encryption to
  `kubernetes/bootstrap-secrets/**` and pins the age public key (recipient).
- `kubernetes/bootstrap-secrets/` — the only directory where SOPS-encrypted
  manifests should live. Contains its own `kustomization.yaml`.
- `kubernetes/clusters/production/bootstrap-secrets.yaml` — the Flux
  `Kustomization` that reconciles that directory. It sets:

  ```yaml
  spec:
    decryption:
      provider: sops
      secretRef:
        name: sops-age
  ```

  It runs immediately after the `namespaces` Kustomization and before
  `controllers`/`infrastructure`, since bootstrap secrets may need to exist
  before the rest of the platform comes up.

- `kubernetes/bootstrap-secrets/example-bootstrap-secret.enc.yaml` — an
  **example only**, with a placeholder value (`REPLACE_ME_NOT_A_REAL_SECRET`).
  It shows the shape of an encrypted manifest; it is not consumed by any
  workload.

## Where the age private key lives

This repository uses a single, permanent age key
(public key `age130mgpv4sdrfu7p7lg7sx4jh7u805w6w3lzsazlckf3pgdzfyuyssgmpjml`,
pinned in `.sops.yaml`). The private key is **never committed to Git**. It
exists in exactly two places:

1. **Locally**, at the standard SOPS age key location:
   `~/.config/sops/age/keys.txt`. `sops` reads this path automatically, so no
   `SOPS_AGE_KEY_FILE` export is needed on this machine.

2. **In-cluster**, as a Kubernetes Secret so Flux can decrypt:

   ```bash
   kubectl create secret generic sops-age \
     --namespace flux-system \
     --from-file=age.agekey=~/.config/sops/age/keys.txt
   ```

   Flux's `kustomize-controller` reads this secret (referenced by
   `secretRef.name: sops-age`) to decrypt any Kustomization that declares
   `decryption.provider: sops`.

3. **Offline backup, outside Git** — e.g. a password manager entry, an
   encrypted USB drive, or a printed paper backup stored securely. This is
   the recovery path if both the local copy and the in-cluster copy are
   lost. Without this backup, any secret encrypted with this age key becomes
   permanently unrecoverable if the machine and cluster are both rebuilt
   from scratch.

The corresponding **public key** (the age "recipient") is not sensitive and
is committed in `.sops.yaml`.

Do not generate a new keypair for this repository — `~/.config/sops/age/keys.txt`
holds the one permanent key. Only rotate it deliberately (see below).

## Day-to-day usage

Create/edit an encrypted secret (no key export needed — `sops` finds
`~/.config/sops/age/keys.txt` by default):

```bash
# create a new plaintext Secret manifest under kubernetes/bootstrap-secrets/,
# then encrypt in place:
sops --encrypt --in-place kubernetes/bootstrap-secrets/my-secret.enc.yaml

# to edit an already-encrypted file:
sops kubernetes/bootstrap-secrets/my-secret.enc.yaml
```

Add the new file to `kubernetes/bootstrap-secrets/kustomization.yaml`
`resources:` list. Commit — only the encrypted file is committed.

### Rotating the key

If the permanent key ever needs to be rotated (suspected compromise, etc.):

```bash
age-keygen -o /path/outside/repo/new-key.agekey   # keep OUT of the repo
```

Update the `age:` recipient in `.sops.yaml` to the new public key, then
re-encrypt every file under `kubernetes/bootstrap-secrets/` with
`sops updatekeys <file>` (run once per file, with both old and new keys
available locally), replace `~/.config/sops/age/keys.txt` with the new key,
and recreate the `sops-age` secret in `flux-system`.

## Recovery procedure (cluster rebuild)

1. Restore the age private key from the offline backup.
2. Re-bootstrap Flux against this Git repo.
3. Recreate the `sops-age` secret in `flux-system` (see command above) before
   or as soon as possible after `flux-system` exists — the
   `bootstrap-secrets` Kustomization will fail to decrypt until this secret
   is present, but will retry automatically once it is.
4. Flux reconciles `bootstrap-secrets`, decrypting the committed manifests.
5. Continue with normal recovery (OpenBao unseal, ESO sync, etc.).

## Future / not yet implemented

Storing OpenBao **unseal keys** via this same SOPS+age mechanism (as a
belt-and-suspenders emergency-recovery path for OpenBao itself) has been
discussed but is **explicitly deferred**. Do not place OpenBao unseal keys
in Git — encrypted or otherwise — until this is revisited and explicitly
decided.
