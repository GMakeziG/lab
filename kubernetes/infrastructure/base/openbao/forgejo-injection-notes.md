# Forgejo OpenBao Injection Notes

## Namespace
forgejo

## Deployment
forgejo

## Service Account
forgejo

## OpenBao Role
forgejo-role

## Injected File Path
/vault/secrets/db

## Injected Keys
- DB_USER
- DB_PASS
- DB_HOST
- DB_NAME

## Verify Injection

```bash
kubectl get pods -n forgejo
kubectl exec -it -n forgejo <forgejo-pod> -c forgejo -- cat /vault/secrets/db
```

Notes
Injection works ✔️
Forgejo is NOT yet using the injected secrets ❗
Current DB config is still whatever Forgejo was originally using
