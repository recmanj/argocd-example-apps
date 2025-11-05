#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo "Usage: $0 <dev|staging|prod>"
  echo "Example: $0 dev"
  exit 1
fi

echo "Deploying ApplicationSet bootstrap for ${ENVIRONMENT} environment..."
kubectl apply -f "${ENVIRONMENT}-appset.yaml"

echo ""
echo "Waiting for Application to be created..."
sleep 3

echo ""
echo "Application status:"
kubectl -n argocd get applicationset argocd-example-apps-appset

echo ""
echo "========================================="
echo "ApplicationSet bootstrap deployed!"
echo "========================================="
echo ""
echo "The ApplicationSet will now discover and manage applications in _apps/*/envs/${ENVIRONMENT}/"
echo ""
echo "To check status:"
echo "  kubectl -n argocd get applicationset argocd-example-apps-appset"
echo "  kubectl -n argocd get applications"
echo ""
echo "To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  https://localhost:8080"
echo ""
