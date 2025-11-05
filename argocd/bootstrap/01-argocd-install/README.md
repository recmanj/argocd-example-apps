# ArgoCD Bootstrap Installation

## Overview
ArgoCD installation with environment-specific envs for dev, staging, and prod clusters.

## Installation

### Prerequisites
- cert-manager must be installed first (see `../00-cert-manager/`)
- kubectl configured for target cluster
- kustomize (or kubectl with kustomize support)

### Install to Dev Cluster
```bash
kubectl apply -k envs/dev
```

### Install to Staging Cluster
```bash
kubectl apply -k envs/staging
```

### Install to Prod Cluster
```bash
kubectl apply -k envs/prod
```

## Verification
Wait for all ArgoCD components to be ready:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=argocd -n argocd --timeout=300s
```

## Access ArgoCD UI

### Get admin password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Port forward to access UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then access at: https://localhost:8080
- Username: `admin`
- Password: (from command above)

## Configuration

### Environment-Specific Settings
Each overlay includes:
- Environment labels for resource identification
- Cluster-specific ConfigMap settings
- Environment-specific ArgoCD configurations

### Customization
To customize for your environment, edit the overlay's `kustomization.yaml`:
- Update cluster names in `configMapGenerator`
- Add RBAC policies
- Configure ingress (if needed)
- Add custom patches

## Next Steps
After ArgoCD is installed:
1. Install Kargo (see `../02-kargo-install/`)
2. Deploy the ApplicationSet bootstrap (see `../03-appset-bootstrap/`)
3. ArgoCD will then manage all applications via ApplicationSets
