# Infisical Ingress Notes

## Local hostname

Preferred lab hostname:

    infisical.lab.arpa

Avoid `.local` because it is reserved for mDNS.

## DNS

Add this hostname to AdGuard Home or your lab DNS:

    infisical.lab.arpa -> <INGRESS_LOADBALANCER_IP>

Find the ingress IP:

    kubectl get svc -A | grep -i ingress
    kubectl get ingress -n infisical

## First phase

Start with HTTP:

    http://infisical.lab.arpa

## Later phase

After cert-manager is ready, switch to HTTPS:

    https://infisical.lab.arpa

## Troubleshooting

    kubectl get ingress -n infisical
    kubectl describe ingress -n infisical
    kubectl get pods -n infisical
    kubectl logs -n infisical deploy/infisical
