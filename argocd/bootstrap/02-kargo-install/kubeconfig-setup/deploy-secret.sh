#!/bin/bash
set -e

ENVIRONMENT=${1:-}
KUBECONFIG_FILE="kargo-controlplane-kubeconfig.yaml"

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging)$ ]]; then
  echo "Usage: $0 <dev|staging>"
  echo ""
  echo "This script deploys the control plane kubeconfig as a secret"
  echo "to the specified remote cluster."
  echo ""
  echo "Example:"
  echo "  $0 dev"
  exit 1
fi

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "Error: $KUBECONFIG_FILE not found."
    echo ""
    echo "Please run ./create-kubeconfig.sh first to create the kubeconfig."
    exit 1
fi

echo "=== Deploying Kubeconfig Secret to $ENVIRONMENT Cluster ==="
echo ""

CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"
echo ""

read -p "Is this the correct $ENVIRONMENT cluster context? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please switch to the $ENVIRONMENT cluster context first:"
    echo "  kubectl config use-context <$ENVIRONMENT-cluster-context>"
    exit 1
fi

echo ""
echo "Creating kargo namespace if it doesn't exist..."
kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -

echo "Creating secret kargo-controlplane-kubeconfig..."
kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \
  --from-file=kubeconfig.yaml="$KUBECONFIG_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Verifying secret..."
kubectl -n kargo get secret kargo-controlplane-kubeconfig

echo ""
echo "========================================="
echo "Secret deployed successfully!"
echo "========================================="
echo ""
echo "Next step: Install Kargo controller in this cluster"
echo "  cd ../controller-$ENVIRONMENT"
echo "  ./install.sh"
echo ""
