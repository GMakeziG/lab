# cert-manager

## Purpose

Automates TLS certificate management in Kubernetes.

## Install


helm repo add jetstack https://charts.jetstack.io

helm install cert-manager jetstack/cert-manager
--namespace cert-manager
--create-namespace
--set installCRDs=true


## Verify


kubectl get pods -n cert-manager


## Future

- Integrate with ACME (Let's Encrypt)
- Automate ingress TLS
