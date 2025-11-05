#!/bin/bash
set -e

echo "=== Kargo Control Plane Installation ===="
echo ""

# Check prerequisites
if ! command -v helm &> /dev/null; then
    echo "Error: Helm is not installed. Please install Helm v3.13.1 or later."
    exit 1
fi

if ! command -v htpasswd &> /dev/null; then
    echo "Error: htpasswd is not installed. Please install apache2-utils (Debian/Ubuntu) or httpd-tools (RHEL/CentOS)."
    exit 1
fi

# Check if we're in the right cluster
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"
echo ""

read -p "Is this the PROD cluster (for control plane)? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please switch to the prod cluster context first:"
    echo "  kubectl config use-context <prod-cluster-context>"
    exit 1
fi

# Check if cert-manager is installed
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo "Warning: cert-manager namespace not found. Kargo requires cert-manager to be installed first."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Generating secure credentials..."
pass=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)
hashed_pass=$(htpasswd -bnBC 10 "" "$pass" | tr -d ':\n')
signing_key=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)

echo ""
echo "Installing Kargo Control Plane via Helm..."
helm install kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --create-namespace \
  --set api.adminAccount.passwordHash="$hashed_pass" \
  --set api.adminAccount.tokenSigningKey="$signing_key" \
  --values values-controlplane.yaml \
  --wait

echo ""
echo "Waiting for Kargo to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=kargo -n kargo --timeout=300s 2>/dev/null || true

echo ""
echo "========================================="
echo "Kargo Control Plane installation complete!"
echo "========================================="
echo ""
echo "Admin Credentials (SAVE THESE!):"
echo "  Username: admin"
echo "  Password: $pass"
echo ""
echo "To access Kargo UI:"
echo "  kubectl port-forward svc/kargo-api -n kargo 8081:80"
echo "  Then access at: http://localhost:8081"
echo ""
echo "========================================="
echo "IMPORTANT: Next Steps for Multi-Cluster"
echo "========================================="
echo ""
echo "1. Create kubeconfig for distributed controllers:"
echo "   cd kubeconfig-setup"
echo "   ./create-kubeconfig.sh"
echo ""
echo "2. Deploy kubeconfig secret to dev cluster:"
echo "   kubectl config use-context dev-cluster"
echo "   cd kubeconfig-setup"
echo "   ./deploy-secret.sh dev"
echo ""
echo "3. Deploy kubeconfig secret to staging cluster:"
echo "   kubectl config use-context staging-cluster"
echo "   cd kubeconfig-setup"
echo "   ./deploy-secret.sh staging"
echo ""
echo "4. Install controllers in dev and staging:"
echo "   cd controller-dev && ./install.sh    # Run in dev cluster"
echo "   cd controller-staging && ./install.sh # Run in staging cluster"
echo ""
echo "5. Deploy Kargo resources:"
echo "   kubectl apply -f ../../kargo/project/"
echo ""
