# k3s Lab

This repository is my DevOps lab source of truth. It contains Kubernetes manifests, Helm values, scripts, and documentation for a Rancher-managed k3s environment.

## Purpose

Build, break, troubleshoot, and automate real-world infrastructure using Kubernetes and cloud-native tooling.

## Stack

- Kubernetes (k3s)
- Rancher
- MetalLB (Layer 2 LoadBalancer)
- Traefik (Ingress)
- Observability stack (Grafana, Loki, Promtail)
- Self-hosted Git service

## Architecture (High Level)

- 1 control-plane node
- Multiple worker nodes
- Layer 2 load balancing for service exposure
- Ingress-based routing for applications

## Repository Layout

- `docs/` → design, networking, troubleshooting
- `kubernetes/` → manifests and configs
- `scripts/` → bootstrap and validation

## Security Notes

- No secrets are stored in this repository
- All sensitive values are replaced with placeholders
- Real environment configuration is maintained outside this repo
