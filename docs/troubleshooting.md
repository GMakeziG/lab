# Troubleshooting

## LoadBalancer IP not reachable

Check:


kubectl get svc -A
kubectl get pods -n metallb-system -o wide


Verify:

- speaker pods running on nodes
- IP assigned correctly

---

## Cannot access application

Check ingress:


kubectl get ingress -A


Validate:

- hostname matches local DNS or hosts file
- ingress controller is running

---

## Node issues


kubectl get nodes -o wide
kubectl describe node <node>


---

## Network issues

Check:

- rp_filter settings
- routing
- kube-proxy / iptables rules

---

## Cross-node 504 / VIP unreachable (firewalld on RHEL nodes)

Symptoms:

- Traefik returns `504` only when the backend pod runs on a specific node
- A LoadBalancer VIP is unreachable from the LAN (but `curl` works when routed
  through a different node)
- The underlay works (you can `ping` the node IP) but pod-to-pod across that
  node fails

Cause: `firewalld` (default-on for RHEL/Rocky) drops the flannel VXLAN overlay
(UDP 8472) before k3s's iptables rules apply, isolating that node's pods.

Diagnose (underlay OK, overlay broken = firewall):

```bash
# from another node, pod-to-pod across the suspect node fails but node IP pings
kubectl get pods -A -o wide        # find a pod on the suspect node
ping <suspect-pod-ip>              # FAIL
ping <suspect-node-ip>             # OK
# on the suspect node:
sudo firewall-cmd --query-port=8472/udp   # -> no
```

Fix: apply the firewalld config in `docs/networking.md` (open 8472/udp, trust
pod/service CIDRs, kubelet 10250/tcp) and `firewall-cmd --reload`.

---

## Quick test


curl -k https://<loadbalancer-ip>

## Troubleshooting: Secrets / Recipes App

### Flux stuck on reconciliation

Check:

```bash
flux get kustomizations
flux logs --kind=Kustomization --name=apps -n flux-system
```

Common cause:

Deployment not healthy (init container stuck)
---

### Recipes pod stuck at Init
```bash
kubectl get pods -n apps
kubectl logs -n apps <pod> -c init-recipes
```
If you see:
```bash
Starting gunicorn
```
Fix:

- Ensure init container has proper`command`and`args`
- Must exit cleanly`(exit 0)`
---
### Secrets not syncing
```bash
kubectl get externalsecret -n apps
kubectl describe externalsecret recipes-secret -n apps
```
Check:

- `Ready=True`
- `SecretSynced`
---
### App cannot connect to database

Test manually:
```bash
kubectl run psql-test -n apps -it --rm \
  --image=postgres:15 \
  --env="PGPASSWORD=<password>" \
  --restart=Never \
  --command -- \
  psql -h postgresql.platform.svc.cluster.local -U recipes -d recipes
```
---
### Verify secrets without exposing values
```bash
kubectl get secret recipes-secret -n apps -o jsonpath='{.data}' | jq 'keys'
```
---
### Force External Secret refresh
```bash
kubectl annotate externalsecret recipes-secret -n apps \
  force-sync="$(date +%s)" --overwrite
```
---
### Restart app after secret change
```bash
kubectl rollout restart deployment recipes -n apps
kubectl rollout status deployment recipes -n apps
```
---
### Check for legacy secret usage
```bash
grep -R "secretKeyRef\|postgresql-password\|secret-key" kubernetes/apps/recipes
```
Should return nothing.
