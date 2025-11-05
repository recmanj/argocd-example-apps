# cert-manager Bootstrap Installation

## Overview
cert-manager must be installed first as it's a dependency for Kargo and potentially other applications.

## Installation

### Option 1: Using kubectl (Recommended for bootstrap)
```bash
# Install cert-manager v1.14.4
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Verify installation
kubectl -n cert-manager get pods
```

### Option 2: Using Helm
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true
```

### Option 3: Using the local manifest
```bash
# If you've downloaded the manifest locally
kubectl apply -f install.yaml
```

## Verification
Wait for all pods to be running:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

## Notes
- This is a **one-time manual installation** per cluster
- After bootstrap, cert-manager will be managed by Kargo through the ApplicationSet
- Install in all 3 clusters: dev, staging, prod (or just prod if Kargo is centralized there)
- Version v1.14.4 is used for stability; update via Kargo after bootstrap
