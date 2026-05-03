Linkding staging flow:
OpenBao secret → eso-linkding-policy → eso-apps role → ClusterSecretStore openbao → ExternalSecret → linkding-secret → HelmRelease env → Linkding pod
