# cert-manager Application

## Overview
cert-manager is a Kubernetes add-on that automates the management and issuance of TLS certificates. It's a critical infrastructure component used by Kargo and potentially other applications.

## Structure

```
cert-manager/
├── base/
│   └── kustomization.yaml     # Base cert-manager installation (v1.14.4)
└── envs/
    ├── dev/
    │   └── kustomization.yaml # Dev overlay (1 replica)
    ├── staging/
    │   └── kustomization.yaml # Staging overlay (default replicas)
    └── prod/
        └── kustomization.yaml # Prod overlay (2 replicas for HA)
```

## Environment Differences

### Dev
- Single replica for all components (cert-manager, webhook, cainjector)
- Minimal resource usage

### Staging
- Default configuration from base
- Used for testing cert-manager upgrades

### Prod
- 2 replicas for all components (high availability)
- Production-ready configuration

## Kargo Integration

cert-manager is managed by Kargo and follows the promotion pipeline:
1. **Warehouse** monitors cert-manager releases
2. **Dev stage** auto-promotes new versions
3. **Staging stage** requires manual promotion from dev
4. **Prod stage** requires manual promotion from staging

## Initial Bootstrap

⚠️ **Important**: cert-manager must be manually installed ONCE in each cluster before Kargo/ArgoCD can manage it:

```bash
# Install cert-manager v1.14.4 (matches this config)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

See `/argocd/bootstrap/00-cert-manager/` for installation scripts.

After bootstrap, Kargo will manage updates and configuration changes.

## Upgrading cert-manager

To upgrade cert-manager:
1. Update the version in `base/kustomization.yaml`
2. Commit and push changes
3. Kargo will detect the new version and promote through environments
4. Test thoroughly in dev before promoting to staging/prod

## Verification

After deployment, verify cert-manager is running:

```bash
# Check pods
kubectl -n cert-manager get pods

# Check CRDs are installed
kubectl get crd | grep cert-manager

# Test with a self-signed certificate
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
EOF
```

## Dependencies

- **Required by**: Kargo, and potentially other applications needing TLS certificates
- **Requires**: Kubernetes 1.22+

## Documentation

- Official docs: https://cert-manager.io/docs/
- Installation guide: https://cert-manager.io/docs/installation/
