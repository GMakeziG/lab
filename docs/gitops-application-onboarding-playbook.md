This should be your reusable guide for converting any Docker-based GitHub project into GitOps:

1. Find the official repository and container image.
2. Review supported tags and avoid latest.
3. Identify the container port.
4. Identify environment variables.
5. Identify required volume paths.
6. Determine the runtime user and UID/GID.
7. Create the ConfigMap.
8. Create the Deployment.
9. Create the ClusterIP Service.
10. Test through port-forwarding.
11. Add persistent storage.
12. Test pod replacement and data persistence.
13. Configure non-root execution.
14. Add Ingress, TLS, Cloudflare Tunnel routing, and DNS.
15. Validate Kustomize.
16. Commit, push, reconcile, and verify.


# GitOps Application Onboarding Playbook sections

## 1. Purpose and scope

The why?!

```markdown
# GitOps Application Onboarding Playbook

This guide explains how to convert a Docker-based application into a GitOps-managed Kubernetes deployment using Flux and Kustomize.

Use this guide for:
- Docker images from GitHub or container registries
- Applications deployed with plain Kubernetes manifests
- Applications that need persistence, ingress, TLS, secrets, and monitoring

Do not use this guide blindly for:
- Databases
- Stateful clusters
- Operators
- Applications with an official Helm chart that is clearly better suited
```

## 2. Decision: plain manifests or Helm

Decision table.

| Use plain manifests when             | Use Helm when                              |
| ------------------------------------ | ------------------------------------------ |
| The app is simple                    | The app has many resources                 |
| You want to learn Kubernetes objects | The official chart is well maintained      |
| Configuration is small               | The chart includes upgrades and migrations |
| You need full control                | The chart has useful defaults              |

Document the decision for each app.

```markdown
Decision: plain manifests

Reason:
Audiobookshelf requires a Deployment, ConfigMap, Service, PVCs, and Ingress. Plain manifests make the learning objectives clearer.
```

## 3. Application research worksheet

Fill-in template.

```markdown
## Application research

Application:
Official repository:
Official documentation:
Official image:
Selected image tag:
Image digest:
License:
Release date:
Maintainer:
Supported architectures:

Container port:
Configurable port variable:
Health-check endpoint:
Timezone variable:
Required environment variables:
Optional environment variables:

Required volumes:
Recommended volumes:
Read-only volumes:
Writable volumes:

Default user:
Default UID:
Default GID:
Supports non-root:
Requires filesystem ownership changes:

Backup requirements:
Upgrade notes:
Known breaking changes:
```

For Audiobookshelf, filled in:

```markdown
Application: Audiobookshelf
Official repository: https://github.com/advplyr/audiobookshelf
Official image: ghcr.io/advplyr/audiobookshelf
Selected image tag: v2.35.1
Application port: 3005
Timezone: America/Los_Angeles
```

## 4. Verify the container before writing YAML

Commands to use.

```bash
docker pull ghcr.io/advplyr/audiobookshelf:v2.35.1

docker image inspect \
  ghcr.io/advplyr/audiobookshelf:v2.35.1

docker inspect \
  ghcr.io/advplyr/audiobookshelf:v2.35.1 \
  --format '{{json .Config.ExposedPorts}}'

docker inspect \
  ghcr.io/advplyr/audiobookshelf:v2.35.1 \
  --format '{{json .Config.Env}}'

docker inspect \
  ghcr.io/advplyr/audiobookshelf:v2.35.1 \
  --format '{{json .Config.Volumes}}'

docker inspect \
  ghcr.io/advplyr/audiobookshelf:v2.35.1 \
  --format '{{.Config.User}}'
```

Warning:

```markdown
Do not guess the UID, GID, volume paths, or application port. Verify them from the image or official documentation.
```

## 5. Repository placement rules

Where files belong.

```text
kubernetes/apps/base/<app>/
├── configmap.yaml
├── deployment.yaml
├── service.yaml
├── pvc.yaml
├── kustomization.yaml
└── README.md

kubernetes/apps/production/<app>/
├── ingress.yaml
├── kustomization.yaml
└── patches.yaml
```

Ownership:

```markdown
Base contains reusable application resources.

Production contains environment-specific ingress, hostnames, storage sizes, replicas, and patches.

Namespaces remain owned by kubernetes/namespaces/.
```

## 6. Naming conventions

Clear standards:

```markdown
Resource names use lowercase kebab-case.

Examples:
- Deployment: audiobookshelf
- Service: audiobookshelf
- ConfigMap: audiobookshelf-config
- PVC: audiobookshelf-config
- Ingress: audiobookshelf
- TLS Secret: audiobooks-ninjatronics-io-tls
```

## 7. ConfigMap template

Generic template:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: APP-config
data:
  PORT: "3005"
  TZ: America/Los_Angeles
```

A ConfigMap only works if the application actually supports those variables.

## 8. Deployment template

Complete reusable example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: APP
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: APP
  template:
    metadata:
      labels:
        app.kubernetes.io/name: APP
    spec:
      containers:
        - name: APP
          image: REGISTRY/IMAGE:VERSION
          envFrom:
            - configMapRef:
                name: APP-config
          ports:
            - name: http
              containerPort: 3005
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

Image pinning and probes.

## 9. Service template

```yaml
apiVersion: v1
kind: Service
metadata:
  name: APP
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: APP
  ports:
    - name: http
      port: 3005
      targetPort: http
```

Why named ports reduce mismatch errors.

## 10. Health checks

Document how to identify a suitable endpoint.

```markdown
Prefer:
- /health
- /healthz
- /ready
- /api/health

Avoid using a heavy dashboard page when a dedicated health endpoint exists.
```

Template:

```yaml
readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 20
```

## 11. Persistent storage planning

Sample worksheet:

| Mount path    | Purpose               | PVC name                    | Initial size | Backup required |
| ------------- | --------------------- | --------------------------- | -----------: | --------------- |
| `/config`     | Database and settings | `audiobookshelf-config`     |          2Gi | Yes             |
| `/metadata`   | Covers and metadata   | `audiobookshelf-metadata`   |          5Gi | Yes             |
| `/audiobooks` | Media library         | `audiobookshelf-audiobooks` |         20Gi | Yes             |
| `/podcasts`   | Podcast library       | `audiobookshelf-podcasts`   |         10Gi | Yes             |

Add a reminder:

```markdown
Changing a PVC name creates a new volume. Treat PVC names as persistent interfaces.
```

## 12. Security context checklist

Important for Stage 3.

```markdown
Before setting securityContext:

- Verify the image user.
- Verify numeric UID/GID.
- Verify writable paths.
- Verify the storage driver supports fsGroup.
- Test with an empty PVC first.
```

Template:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containers:
  - name: APP
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
```

Only add these after verification:

```yaml
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
```

## 13. Secrets decision tree

Document when to use each tool.

```markdown
Use OpenBao + External Secrets for:
- application passwords
- API tokens
- OAuth secrets
- SMTP credentials
- database passwords

Use SOPS + age for:
- bootstrap secrets
- Flux decryption material
- credentials required before OpenBao is available
- Cloudflare tunnel credentials
```

Also include:

```markdown
Never place plaintext secrets in:
- ConfigMaps
- Helm values
- example manifests
- README files
- Git history
```

## 14. Port-forward testing

Document headless server and desktop server.

On headless:

```bash
kubectl -n apps port-forward svc/audiobookshelf 3005:3005
```

On desktop server:

```bash
ssh -L 3005:localhost:3005 gerso@headless
```

Browser on desktop server:

```text
http://localhost:3005
```

## 15. Ingress template

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: APP
  namespace: apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production-cloudflare
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - APP.ninjatronics.io
      secretName: APP-ninjatronics-io-tls
  rules:
    - host: APP.ninjatronics.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: APP
                port:
                  number: 3005
```

## 16. Cloudflare Tunnel checklist

Include this every time:

```markdown
- Add hostname to cloudflared ConfigMap.
- Keep the final http_status:404 rule last.
- Create the CNAME/Tunnel DNS record.
- Restart cloudflared only if it does not reload the ConfigMap.
```

Example:

```yaml
- hostname: audiobooks.ninjatronics.io
  service: https://traefik.kube-system.svc.cluster.local:443
  originRequest:
    noTLSVerify: true
```

## 17. Validation commands

Make this copy-paste friendly.

```bash
kubectl kustomize kubernetes/apps/base
kubectl kustomize kubernetes/apps/production
kubectl kustomize kubernetes/clusters/production

git diff --check
git status --short
```

After deployment:

```bash
flux get kustomizations
kubectl get deploy,po,svc,pvc,ingress -n apps
kubectl describe deployment audiobookshelf -n apps
kubectl logs -n apps deploy/audiobookshelf --tail=100
```

## 18. Persistence test

Create an explicit test:

```markdown
1. Create the initial account.
2. Add an audiobook library.
3. Add one test audio file.
4. Record the file and library name.
5. Restart the Deployment.
6. Wait for the new pod.
7. Log in again.
8. Confirm the user account remains.
9. Confirm the library remains.
10. Confirm the audio file remains playable.
```

Command:

```bash
kubectl rollout restart deployment audiobookshelf -n apps
kubectl rollout status deployment audiobookshelf -n apps
```

## 19. Non-root verification

```bash
kubectl exec -n apps deploy/audiobookshelf -- id

kubectl exec -n apps deploy/audiobookshelf -- \
  sh -c 'ps -o pid,user,group,args'
```

Expected result:

```text
uid=<non-zero UID>
```

## 20. Git workflow

Document the exact process:

```bash
git status --short
git diff
git add <specific-files>
git commit -m "feat(apps): deploy Audiobookshelf base service"
git push origin main
```

Then:

```bash
flux reconcile source git flux-system
flux reconcile kustomization apps --with-source
```

## 21. Rollback procedure

Include both Git and Kubernetes checks.

```bash
git revert <commit-sha>
git push origin main

flux reconcile kustomization apps --with-source
```

Do not delete PVCs during rollback unless data removal is intentional.

## 22. Upgrade procedure

```markdown
1. Review release notes.
2. Update image tag.
3. Render and validate.
4. Commit the version change separately.
5. Reconcile Flux.
6. Watch the rollout.
7. Confirm data and login.
8. Revert if needed.
```

## 23. Troubleshooting matrix

| Symptom                 | Likely cause                                | First command                  |
| ----------------------- | ------------------------------------------- | ------------------------------ |
| Pod pending             | PVC or scheduling issue                     | `kubectl describe pod`         |
| CrashLoopBackOff        | bad config or permissions                   | `kubectl logs`                 |
| 404 through tunnel      | hostname missing from cloudflared ConfigMap | inspect ConfigMap              |
| 502 through tunnel      | service or endpoint failure                 | `kubectl get endpoints`        |
| Certificate pending     | DNS-01 or issuer issue                      | `kubectl describe certificate` |
| Permission denied       | incorrect UID/GID or volume ownership       | `kubectl exec ... id`          |
| Data lost after restart | missing or incorrect PVC mount              | inspect Deployment             |

## 24. Completion checklist

End the document with a reusable checklist:

```markdown
- [ ] Official repository verified
- [ ] Official image verified
- [ ] Version pinned
- [ ] Port verified
- [ ] Environment variables verified
- [ ] Volume paths verified
- [ ] Runtime user verified
- [ ] ConfigMap created
- [ ] Deployment created
- [ ] ClusterIP Service created
- [ ] Port-forward tested
- [ ] PVCs created
- [ ] Persistence tested
- [ ] Non-root execution verified
- [ ] Ingress created
- [ ] TLS ready
- [ ] Cloudflare tunnel rule added
- [ ] DNS record created
- [ ] Kustomize validated
- [ ] Flux reconciled
- [ ] Rollback documented
- [ ] Application README completed
- [ ] Validation runbook completed
```
