#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo "Usage: $0 <dev|staging|prod>"
  echo "Example: $0 dev"
  exit 1
fi

echo "Installing ArgoCD for ${ENVIRONMENT} environment..."
kubectl apply -k "envs/${ENVIRONMENT}"

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/managed-by=kustomize -n argocd --timeout=300s

echo ""
echo "ArgoCD installation complete!"
echo ""
echo "To access ArgoCD UI:"
echo "1. Get admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo "2. Port forward:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "3. Access at: https://localhost:8080"
echo "   Username: admin"
echo "   Password: (from step 1)"
