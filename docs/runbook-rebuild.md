
````markdown
# Cluster Rebuild Runbook

## Purpose

Rebuild the entire cluster from scratch using Git as the source of truth.

---

## Prerequisites

- Fresh k3s cluster
- kubectl configured
- GitHub repo access
- SSH access to node

---

## Step 0: Node OS prep (RHEL / Rocky nodes only)

RHEL-family nodes run `firewalld`, which blocks the flannel VXLAN overlay and
breaks cross-node pod networking. Configure this BEFORE installing k3s (see
`docs/networking.md` for details):

```bash
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
printf 'net.ipv4.conf.all.rp_filter=0\nnet.ipv4.conf.default.rp_filter=0\n' \
  | sudo tee /etc/sysctl.d/90-k3s-rp-filter.conf
sudo sysctl --system
```

Debian/Ubuntu nodes ship with no host firewall and need no action here.

---

## Step 1: Install k3s

```bash
curl -sfL https://get.k3s.io | sh -
````

Verify:

```bash
kubectl get nodes
```

---

## Step 2: Install Flux CLI

```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

Verify:

```bash
flux --version
```

---

## Step 3: Bootstrap Flux

```bash
flux bootstrap github \
  --owner=GMakeziG \
  --repo=lab \
  --branch=main \
  --path=./kubernetes/clusters/home \
  --personal
```

---

## Step 4: Verify Flux

```bash
flux get sources git
flux get kustomizations
```

---

## Step 5: Watch Reconciliation

```bash
kubectl get pods -A -w
```

Expected order:

1. flux-system
    
2. namespaces
    
3. platform
    
4. apps
    
5. observability
    

---

## Step 6: Verify Core Components

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

Check:

- MetalLB IP assigned
    
- Traefik running
    
- PostgreSQL running
    
- OpenBao running
    
- External Secrets running
    

---

## Step 7: Verify Secrets

```bash
kubectl get externalsecret -A
kubectl get secret -n apps recipes-secret
```

---

## Step 8: Verify Apps

```bash
kubectl get pods -n apps
kubectl rollout status deployment recipes -n apps
```

---

## Step 9: Access Services

- Rancher
    
- Recipes
    
- OpenBao UI
    

Example:

```
http://recipes.ninjatronics.home.arpa
```

---

## Step 10: Post-Rebuild Tasks

- Rotate secrets in OpenBao
    
- Verify TLS (if configured)
    
- Validate backups
    
- Confirm ingress access
    

---

## Troubleshooting

### Flux stuck

```bash
flux logs --kind=Kustomization --name=apps -n flux-system
```

---

### Pods stuck in Init

```bash
kubectl logs <pod> -c init-recipes
```

---

### Secrets not syncing

```bash
kubectl describe externalsecret -A
```

---

### Database issues

```bash
kubectl run psql-test ...
```

---

## Recovery Principle

```
If it’s not in Git, it doesn’t exist.
```

Never fix permanently with kubectl — fix in Git.

````

---

# ✅ Final step

```bash
cd ~/src/lab
git add docs/
git commit -m "Add GitOps architecture and full cluster rebuild runbook"
git push github main
````

