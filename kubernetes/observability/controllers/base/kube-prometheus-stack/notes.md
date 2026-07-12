# kube-prometheus-stack

## Namespace

observability (reused, owned by `kubernetes/namespaces/observability.yaml` — do not declare it here)

## OpenBao secret

Path: `secret/observability/grafana` (KV v2)

Properties:
- admin-user
- admin-password

## OpenBao policy

Grant the `eso-apps` role read access to this path:

```hcl
path "secret/data/observability/grafana" {
  capabilities = ["read"]
}

path "secret/metadata/observability/grafana" {
  capabilities = ["read"]
}
```

## Storage & retention

- Grafana: 5Gi PVC
- Prometheus: 20Gi PVC, 15d retention
- Alertmanager: 2Gi PVC

All use the cluster default StorageClass (no `storageClassName` set, consistent with other PVCs in this repo). Adjust sizes if the lab's disk pressure changes.

## Flow

OpenBao secret (`secret/observability/grafana`) → ClusterSecretStore `openbao` → ExternalSecret `kube-prometheus-stack-grafana-admin` → Secret `kube-prometheus-stack-grafana-admin` → HelmRelease `grafana.admin.existingSecret` → Grafana pod
