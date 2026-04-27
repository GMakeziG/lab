# Infisical

Infisical is the lab secrets-management platform.

## Location

```text
src/lab/kubernetes/platform/infisical
Purpose

This service will store secrets for lab applications such as:

Forgejo
Grafana
Recipes app
Future Kubernetes workloads

The goal is to stop storing sensitive values directly in Kubernetes YAML files.

Files
namespace.yaml
helm-values.yaml
ingress-notes.md
README.md
Create namespace
kubectl apply -f namespace.yaml
Add Helm repo
helm repo add infisical https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/
helm repo update
Generate replacement secrets

Do not keep the default CHANGE_ME values.

openssl rand -base64 32
openssl rand -base64 32
openssl rand -hex 32

Use generated values for:

PostgreSQL password
Redis password
JWT secret
Encryption key
Deploy
helm install infisical infisical/infisical \
  -n infisical \
  -f helm-values.yaml
Upgrade after changes
helm upgrade infisical infisical/infisical \
  -n infisical \
  -f helm-values.yaml
Check status
kubectl get pods -n infisical
kubectl get svc -n infisical
kubectl get ingress -n infisical
Access
http://infisical.lab.arpa
Next step

After Infisical is working, add one of the Kubernetes integrations:

Infisical Kubernetes Operator
Infisical CSI Provider
External Secrets Operator

For this lab, the clean path is probably:

Infisical -> Kubernetes integration -> Kubernetes Secret -> App

