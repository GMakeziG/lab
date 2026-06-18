# Cloudflare 521/522 Troubleshooting

## Symptoms

- Cloudflare 521: web server is down
- Cloudflare 522: connection timed out
- Kubernetes workloads appear healthy
- Internal tests to the ingress controller succeed

## Working Configuration

- Public TCP 80 -> Kubernetes ingress NodePort
- Public TCP 443 -> Kubernetes ingress NodePort
- Avoid forwarding directly to MetalLB VIPs when using certain consumer routers

## Verification Commands

```sh
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl get pod -n kube-system -o wide | grep traefik
kubectl get svc -n kube-system traefik
kubectl logs -n kube-system deploy/traefik --tail=200
```

Test through the expected public hostname after updating router and DNS settings.

## Root Cause

The router failed to reliably forward WAN traffic to the MetalLB virtual IP.

## Resolution

Forward traffic to the ingress controller NodePorts instead of the MetalLB VIP.

## Recovery Steps

1. Confirm public DNS points to the current WAN IP.
2. Confirm the ingress controller service NodePorts.
3. Update router port forwards:
   - Public TCP 80 -> Kubernetes ingress NodePort
   - Public TCP 443 -> Kubernetes ingress NodePort
4. Test from an external network.
5. Confirm Cloudflare no longer shows 521 or 522.
