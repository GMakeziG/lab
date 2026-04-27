# Troubleshooting

## LoadBalancer IP not reachable

Check:


kubectl get svc -A
kubectl get pods -n metallb-system -o wide


Verify:

- speaker pods running on nodes
- IP assigned correctly

---

## Cannot access application

Check ingress:


kubectl get ingress -A


Validate:

- hostname matches local DNS or hosts file
- ingress controller is running

---

## Node issues


kubectl get nodes -o wide
kubectl describe node <node>


---

## Network issues

Check:

- rp_filter settings
- routing
- kube-proxy / iptables rules

---

## Quick test


curl -k https://<loadbalancer-ip>
