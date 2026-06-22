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


## Node Firewall (RHEL / Rocky nodes)

Debian/Ubuntu nodes ship with no host firewall, but RHEL-family nodes
(e.g. Rocky) run `firewalld` by default. firewalld's nft rules sit in front
of the k3s/flannel iptables rules and will silently drop the flannel VXLAN
overlay, isolating that node's pods cross-node (symptoms: Traefik 504 when the
backend pod is on that node; a LoadBalancer VIP becomes unreachable when that
node is the elected MetalLB L2 leader).

Required firewalld config on every RHEL/Rocky node:

```bash
# flannel VXLAN underlay (node-to-node, UDP 8472)
sudo firewall-cmd --permanent --add-port=8472/udp
# kubelet API (metrics, logs, exec)
sudo firewall-cmd --permanent --add-port=10250/tcp
# trust the pod and service CIDRs
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
```

Also persist `rp_filter=0` (see Kernel Requirements) in
`/etc/sysctl.d/90-k3s-rp-filter.conf` and run `sudo sysctl --system`. Note that
`net.ipv4.conf.default.rp_filter` only affects interfaces created afterwards, so
set it before k3s creates `flannel.1`/`cni0` (or reset existing interfaces).

## Notes

- ICMP (ping) may not work for LoadBalancer IPs
- HTTP/HTTPS traffic is the correct validation method
