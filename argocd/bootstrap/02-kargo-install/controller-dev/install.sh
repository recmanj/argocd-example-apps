#!/bin/bash
set -e

echo "=== Kargo Distributed Controller Installation (Dev Cluster) ==="
echo ""

# Check prerequisites
if ! command -v helm &> /dev/null; then
    echo "Error: Helm is not installed. Please install Helm v3.13.1 or later."
    exit 1
fi

# Check if we're in the right cluster
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"
echo ""

read -p "Is this the DEV cluster? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please switch to the dev cluster context first:"
    echo "  kubectl config use-context <dev-cluster-context>"
    exit 1
fi

# Check if control plane kubeconfig secret exists
if ! kubectl -n kargo get secret kargo-controlplane-kubeconfig &> /dev/null; then
    echo "Error: Secret 'kargo-controlplane-kubeconfig' not found in kargo namespace."
    echo ""
    echo "Please create the kubeconfig secret first:"
    echo "  cd ../kubeconfig-setup"
    echo "  ./create-kubeconfig.sh        # Run this in PROD cluster"
    echo "  ./deploy-secret.sh dev        # Run this in DEV cluster"
    exit 1
fi

echo "Installing Kargo controller (dev-shard) via Helm..."
helm install kargo-controller \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --create-namespace \
  --values values.yaml \
  --wait

echo ""
echo "Waiting for controller to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kargo-controller -n kargo --timeout=300s 2>/dev/null || true

echo ""
echo "========================================="
echo "Kargo controller (dev-shard) installation complete!"
echo "========================================="
echo ""
echo "Controller configuration:"
echo "  Shard name: dev-shard"
echo "  Control plane: via kargo-controlplane-kubeconfig secret"
echo "  ArgoCD: local (same cluster)"
echo ""
echo "To verify:"
echo "  kubectl -n kargo get pods"
echo "  kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller"
echo ""
echo "Next steps:"
echo "  1. Deploy Kargo resources (if not already done):"
echo "     kubectl apply -f ../../../../kargo/project/"
echo "  2. Verify Stages are assigned to this shard:"
echo "     kubectl -n argocd-example-apps get stages -o yaml | grep 'shard: dev-shard'"
echo ""
