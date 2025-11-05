#!/bin/bash
set -e

echo "=== Kargo Remote Controller Token Rotation ==="
echo ""
echo "This script rotates the service account token for remote controllers"
echo "and updates the kubeconfig secret in dev and staging clusters."
echo ""
echo "⚠️  WARNING: This will invalidate the current token!"
echo ""

# Check prerequisites
if ! kubectl config current-context &> /dev/null; then
    echo "Error: kubectl is not configured."
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"
echo ""

read -p "Is this the PROD cluster (control plane)? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please switch to the prod cluster context first:"
    echo "  kubectl config use-context <prod-cluster-context>"
    exit 1
fi

echo ""
echo "Step 1: Deleting old service account token..."

# Delete the old token secret
OLD_SECRET=$(kubectl -n kargo get secret kargo-remote-controller-token 2>/dev/null || echo "")

if [ -z "$OLD_SECRET" ]; then
    echo "No existing token secret found. Creating new one..."
else
    kubectl -n kargo delete secret kargo-remote-controller-token
    echo "✓ Old token deleted"
fi

echo ""
echo "Step 2: Creating new service account token..."

# Create new token secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kargo-remote-controller-token
  namespace: kargo
  annotations:
    kubernetes.io/service-account.name: kargo-remote-controller
    rotated-at: "$(date -Iseconds)"
type: kubernetes.io/service-account-token
EOF

echo "Waiting for token to be generated..."
sleep 5

# Verify token exists
if ! kubectl -n kargo get secret kargo-remote-controller-token -o jsonpath='{.data.token}' &> /dev/null; then
    echo "✗ Error: Token was not generated"
    exit 1
fi

echo "✓ New token created"

echo ""
echo "Step 3: Recreating kubeconfig file..."

# Run the kubeconfig creation script
cd "$(dirname "$0")"
./create-kubeconfig.sh

KUBECONFIG_FILE="kargo-controlplane-kubeconfig.yaml"

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "✗ Error: Kubeconfig file was not created"
    exit 1
fi

echo "✓ Kubeconfig recreated"

echo ""
echo "========================================="
echo "Token Rotation Complete!"
echo "========================================="
echo ""
echo "⚠️  NEXT STEPS - Update Remote Clusters:"
echo ""
echo "1. Update secret in DEV cluster:"
echo "   kubectl config use-context dev-cluster"
echo "   kubectl -n kargo delete secret kargo-controlplane-kubeconfig"
echo "   kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \\"
echo "     --from-file=kubeconfig=$KUBECONFIG_FILE"
echo "   kubectl -n kargo rollout restart deployment kargo-controller"
echo ""
echo "2. Update secret in STAGING cluster:"
echo "   kubectl config use-context staging-cluster"
echo "   kubectl -n kargo delete secret kargo-controlplane-kubeconfig"
echo "   kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \\"
echo "     --from-file=kubeconfig=$KUBECONFIG_FILE"
echo "   kubectl -n kargo rollout restart deployment kargo-controller"
echo ""
echo "3. Verify controllers are running:"
echo "   kubectl -n kargo get pods"
echo "   kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=50"
echo ""
echo "4. Delete the kubeconfig file when done:"
echo "   rm $KUBECONFIG_FILE"
echo ""
echo "📅 Schedule next rotation: $(date -d '+90 days' '+%Y-%m-%d')"
echo ""
