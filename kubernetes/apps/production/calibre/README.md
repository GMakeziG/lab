# Calibre production deployment

The ingress is internal-only at `https://calibre.internal` and uses the
cluster's `lab-selfsigned` issuer. No Cloudflare DNS or tunnel route is used.

## OpenBao credentials

The local workstation does not have the `bao` CLI or an authenticated OpenBao
token, so an OpenBao administrator must create the KV v2 secret before this
overlay is reconciled. Run the following and replace both placeholder values:

```sh
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$BAO_TOKEN" \
  bao kv put secret/apps/calibre \
  username='<calibre-username>' \
  password='<strong-random-password>'
```

Then verify only the key names (the command does not print their values):

```sh
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$BAO_TOKEN" \
  bao kv metadata get secret/apps/calibre
```

ESO maps `username` and `password` to `CALIBRE_USERNAME` and
`CALIBRE_PASSWORD` in the generated Kubernetes Secret.
