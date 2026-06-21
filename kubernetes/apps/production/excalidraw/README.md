# Excalidraw Deployment

Self-hosted virtual whiteboard for sketching hand-drawn style diagrams on your personal domain.

## Overview

This deployment provides a production-ready Excalidraw instance accessible at `https://draw.ninjatronics.io` using GitOps best practices with FluxCD and Kustomize.

### Architecture

```
Internet
    ↓
Cloudflare Access (authentication layer)
    ↓
Traefik Ingress Controller (draw.ninjatronics.io)
    ↓
cert-manager (TLS - letsencrypt-production-cloudflare)
    ↓
Excalidraw Service (ClusterIP, port 80)
    ↓
Excalidraw Pod (single replica, port 80)
```

## Directory Structure

```
kubernetes/
├── namespaces/
│   └── excalidraw.yaml              # Namespace definition
│
└── apps/
    ├── base/
    │   └── excalidraw/
    │       ├── deployment.yaml      # Core Excalidraw deployment
    │       ├── service.yaml         # ClusterIP service
    │       └── kustomization.yaml   # Base kustomization
    │
    └── production/
        └── excalidraw/
            ├── namespace.yaml       # Namespace overlay
            ├── ingress.yaml         # HTTPS ingress with cert-manager
            └── kustomization.yaml   # Production overlay with namespace context
```

## Deployment

### Prerequisites

- K3s cluster with Traefik ingress controller
- FluxCD configured and watching the repository
- cert-manager with `letsencrypt-production-cloudflare` ClusterIssuer
- Cloudflare API token configured in cert-manager
- DNS record `draw.ninjatronics.io` pointing to your cluster

### FluxCD Integration

The deployment is fully integrated with FluxCD GitOps workflow:

1. **Namespace reconciliation**: Managed by `kubernetes/clusters/production/namespaces.yaml`
   - Path: `./kubernetes/namespaces`
   - Interval: 10 minutes

2. **Application reconciliation**: Managed by `kubernetes/clusters/production/apps.yaml`
   - Path: `./kubernetes/apps/production`
   - Interval: 10 minutes
   - Depends on: infrastructure

Changes committed to the repository are automatically applied by FluxCD.

### Manual Deployment (if needed)

```bash
kubectl kustomize kubernetes/apps/production/excalidraw | kubectl apply -f -
```

## Configuration

### Container Image

**Image**: `excalidraw/excalidraw:latest`

The image is not pinned to a specific version tag because Docker Hub does not publish semantic version tags for the client image (only `latest`). 

**To pin to a specific digest in production:**

1. Pull the image and get its digest:
   ```bash
   docker pull excalidraw/excalidraw:latest
   docker inspect excalidraw/excalidraw:latest | grep "Digest\|RepoDigests"
   ```

2. Update the image reference in `kubernetes/apps/base/excalidraw/deployment.yaml`:
   ```yaml
   image: excalidraw/excalidraw@sha256:<full-digest>
   ```

3. Commit and push the change. FluxCD will reconcile automatically.

**Version Notes:**
- Docker image last updated: June 2026 (approximately)
- Excalidraw release: v0.18.1 (March 2025)
- Image is analytics-free and contains only the client application

### Resource Allocation

Configured for homelab usage with single replica:

```yaml
resources:
  requests:
    cpu: 100m          # Minimum guaranteed CPU
    memory: 256Mi      # Minimum guaranteed memory
  limits:
    cpu: 500m          # Maximum CPU allowed
    memory: 512Mi      # Maximum memory allowed
```

Adjust these values in `kubernetes/apps/base/excalidraw/deployment.yaml` if needed.

### Health Probes

**Liveness Probe** (detects stuck/unresponsive containers):
- Endpoint: `GET /`
- Initial delay: 10 seconds
- Period: 30 seconds
- Failure threshold: 3 consecutive failures

**Readiness Probe** (determines if pod is ready to serve traffic):
- Endpoint: `GET /`
- Initial delay: 5 seconds
- Period: 10 seconds
- Failure threshold: 3 consecutive failures

### Security Context

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

Provides defense-in-depth by preventing privilege escalation and dropping unnecessary Linux capabilities.

## TLS/SSL Certificate

**ClusterIssuer**: `letsencrypt-production-cloudflare`

Certificates are automatically provisioned and renewed by cert-manager using DNS-01 challenge via Cloudflare.

To verify the certificate:

```bash
kubectl get certificate -n excalidraw
kubectl describe certificate -n excalidraw excalidraw-ninjatronics-io-tls
```

## Ingress

**Hostname**: `draw.ninjatronics.io`  
**Port**: 443 (HTTPS)  
**Controller**: Traefik

The ingress is configured with:
- TLS enabled with auto-issued Let's Encrypt certificate
- Backend service: `excalidraw` in the `excalidraw` namespace on port 80
- Path: `/` (all routes)

## Validation Steps

### 1. Verify FluxCD reconciliation

```bash
flux get kustomizations --all-namespaces | grep excalidraw
```

Expected output shows the `apps` kustomization as `True` with recent reconciliation time.

### 2. Check namespace

```bash
kubectl get namespace excalidraw
```

### 3. Check deployment

```bash
kubectl get deployment -n excalidraw
kubectl describe deployment excalidraw -n excalidraw
```

Verify pod is running and probes are healthy.

### 4. Check service

```bash
kubectl get service -n excalidraw
```

Should show `ClusterIP` on port 80.

### 5. Check ingress

```bash
kubectl get ingress -n excalidraw
kubectl describe ingress -n excalidraw excalidraw
```

Verify TLS secret is issued and ingress is ready.

### 6. Check TLS certificate

```bash
kubectl get certificate -n excalidraw
kubectl get secret -n excalidraw excalidraw-ninjatronics-io-tls
```

### 7. Verify pod is running

```bash
kubectl get pods -n excalidraw
kubectl logs -n excalidraw -l app=excalidraw --tail=50
```

### 8. Test HTTPS endpoint

```bash
curl -I https://draw.ninjatronics.io
```

Should return HTTP 200 with Traefik headers.

### 9. Access the application

Open `https://draw.ninjatronics.io` in a browser. You should see the Excalidraw interface if not behind Cloudflare Access, or Cloudflare Access login if configured.

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n excalidraw -l app=excalidraw
kubectl logs -n excalidraw -l app=excalidraw --previous
```

Check for image pull errors, resource constraints, or security policy violations.

### Certificate not issued

```bash
kubectl describe certificate -n excalidraw
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

Verify Cloudflare API token secret exists and has correct permissions.

### Ingress not routing traffic

```bash
kubectl describe ingress -n excalidraw
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

Check Traefik logs for routing issues and verify DNS is resolving to your cluster.

### Health probes failing

```bash
kubectl port-forward -n excalidraw svc/excalidraw 8080:80
curl -I http://localhost:8080/
```

Verify the pod responds to HTTP requests on port 80 at the root path.

## Rollback Procedure

### Option 1: Git revert (recommended)

```bash
# Identify the commit that introduced Excalidraw
git log --oneline | grep -i excalidraw

# Revert the commit
git revert <commit-hash>

# Push the revert commit
git push

# FluxCD will automatically reconcile and remove resources
```

### Option 2: Manual deletion

```bash
# Delete the entire namespace (this removes all resources)
kubectl delete namespace excalidraw

# Verify removal
kubectl get namespace excalidraw 2>&1 | grep "not found"
```

After manual deletion, you can restore by pushing a Git commit that adds the namespace back or by running `git revert` on the revert commit.

### Option 3: Scale down (temporary)

```bash
# Scale deployment to zero (keeps namespace/resources intact)
kubectl scale deployment -n excalidraw excalidraw --replicas=0

# Scale back up when ready
kubectl scale deployment -n excalidraw excalidraw --replicas=1
```

## Cloudflare Access (Security)

**Status**: Manual configuration required (not implemented as Kubernetes middleware)

To protect Excalidraw with Cloudflare Access:

### In Cloudflare Dashboard

1. **Navigate to**: Access → Applications
2. **Create new application**:
   - Application name: "Excalidraw"
   - Application domain: `draw.ninjatronics.io`
   - Application type: "SaaS"

3. **Configure authentication policy**:
   - Identity provider: Choose your provider (Email, Okta, Google, etc.)
   - Require: Select appropriate users/groups
   - Example policy: "Any email address under your domain"

4. **Add policy**:
   - Name: "Allow authenticated users"
   - Rules: "Emails matching" `@yourdomain.com`
   - Action: Allow
   - Approve: Any user in list

5. **Deploy**: Create the policy

### Verification

Once configured:

```bash
# Unauthenticated access will be redirected to Cloudflare Access login
curl -I https://draw.ninjatronics.io

# Should show Cloudflare Access interstitial or auth flow
```

**Notes:**
- Cloudflare Access works at the DNS/proxy level, requiring authentication before traffic reaches your cluster
- No admin interface is exposed publicly
- SSL/TLS is still handled by cert-manager for the Kubernetes ingress
- Excalidraw itself has no authentication layer (relies on Cloudflare Access)

## Maintenance

### Updating to a newer image version

1. **Find the latest digest**:
   ```bash
   docker pull excalidraw/excalidraw:latest
   docker inspect excalidraw/excalidraw:latest | grep "RepoDigests"
   ```

2. **Update the deployment**:
   Edit `kubernetes/apps/base/excalidraw/deployment.yaml` and change the image reference:
   ```yaml
   image: excalidraw/excalidraw@sha256:<new-digest>
   ```

3. **Commit and push**:
   ```bash
   git add kubernetes/apps/base/excalidraw/deployment.yaml
   git commit -m "chore: update excalidraw image to latest"
   git push
   ```

4. **Verify rollout**:
   ```bash
   kubectl rollout status deployment/excalidraw -n excalidraw
   ```

### Scaling to multiple replicas

Edit `kubernetes/apps/base/excalidraw/deployment.yaml`:

```yaml
spec:
  replicas: 3  # Change from 1 to desired number
```

Note: Excalidraw is stateless, so scaling is straightforward. Consider adding a horizontal pod autoscaler for production:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: excalidraw
  namespace: excalidraw
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: excalidraw
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

## Assumptions Made

1. ✓ Cloudflare DNS `draw.ninjatronics.io` will be configured to point to the cluster
2. ✓ cert-manager is installed with working `letsencrypt-production-cloudflare` ClusterIssuer
3. ✓ Cloudflare API token is configured in cert-manager namespace as `cloudflare-api-token-secret`
4. ✓ Traefik ingress controller is running and configured as default
5. ✓ FluxCD is watching the repository and configured to reconcile
6. ✓ Single replica is appropriate for homelab (not high-availability)
7. ✓ Excalidraw health endpoint responds to HTTP GET on `/` (root path)
8. ✓ Port 80 is the correct internal port for the Excalidraw container
9. ✓ Cloudflare Access will be manually configured via Cloudflare dashboard
10. ✓ No custom configuration or persistence is required for this initial deployment

## Notes

- **Collaboration**: Self-hosted Excalidraw instances do not support real-time collaboration/sharing features (requires Excalidraw backend server)
- **Analytics**: Container image is analytics-free
- **Data storage**: All drawings are stored locally in the browser; no backend storage
- **Exports**: Users can export drawings as PNG, SVG, or `.excalidraw` JSON format
