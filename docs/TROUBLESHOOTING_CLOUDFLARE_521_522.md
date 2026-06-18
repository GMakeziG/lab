# Cloudflare 521/522 Troubleshooting

## Symptoms

- Cloudflare 522: connection timed out
- Cloudflare 521: web server is down
- Kubernetes resources look healthy
- Internal tests directly to Traefik work

## Working Configuration

- Public TCP 80 -> `10.99.0.5:31094`
- Public TCP 443 -> `10.99.0.5:30533`
- Do not forward directly to MetalLB VIP `10.99.0.242`

## Current Known Values

- `zion`: `10.99.0.5`
- Traefik LoadBalancer VIP: `10.99.0.242`
- Traefik NodePorts:
  - HTTP: `31094`
  - HTTPS: `30533`
- Apps:
  - `qr.ninjatronics.io`
  - `linkding.ninjatronics.io`

## Verification Commands

```sh
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl get pod -n kube-system -o wide | grep traefik
kubectl get svc -n kube-system traefik
kubectl logs -n kube-system deploy/traefik --tail=200

curl -vk --resolve qr.ninjatronics.io:443:10.99.0.242 https://qr.ninjatronics.io
curl -vk --resolve linkding.ninjatronics.io:443:10.99.0.242 https://linkding.ninjatronics.io
```

## Root Cause

Synology SRM may not reliably forward WAN traffic to the MetalLB floating VIP
`10.99.0.242`. Forwarding WAN traffic to Traefik's NodePorts on `zion` fixed
the issue.

## Recovery Steps

1. Confirm Cloudflare DNS points to the current WAN IP.
2. Confirm the Traefik service NodePorts.
3. Update Synology SRM port forwards:
   - Public TCP 80 -> `10.99.0.5:31094`
   - Public TCP 443 -> `10.99.0.5:30533`
4. Test from a cellular network.
5. Confirm Cloudflare no longer shows 521 or 522.
