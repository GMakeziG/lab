# Architecture

## Node Roles

- Control Plane Node
- Worker Nodes (compute)
- Future: Storage Node

## Platform Components

- Kubernetes (k3s)
- Rancher for cluster management
- Traefik for ingress routing
- MetalLB for LoadBalancer IP assignment

## Traffic Flow

Client → LoadBalancer IP → Ingress Controller → Service → Pod

## Design Goals

- Lightweight cluster
- Reproducible deployments
- Clear separation of platform vs application workloads
