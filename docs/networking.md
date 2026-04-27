# Networking

## Load Balancing

MetalLB is used in Layer 2 mode to provide external IPs for services.

Example range (placeholder):
192.168.X.240 - 192.168.X.250


## Ingress

- Managed by Traefik
- Routes traffic based on hostname

Example:


app.lab.local


## Local DNS

Use `/etc/hosts` or internal DNS:


<LOADBALANCER_IP> app.lab.local


## Kernel Requirements

MetalLB requires:


net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0


## Notes

- ICMP (ping) may not work for LoadBalancer IPs
- HTTP/HTTPS traffic is the correct validation method
