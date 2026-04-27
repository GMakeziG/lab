# Forgejo

## Purpose

Self-hosted Git service for lab and GitOps workflows.

## Access

- HTTP via NodePort or ingress
- SSH via NodePort

## Deployment

- Deployed using Helm
- Persistent storage required for repositories

## Future Improvements

- Move fully behind ingress
- Add TLS via cert-manager
