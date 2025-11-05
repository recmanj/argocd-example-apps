#!/bin/bash
set -e

# Parse command line arguments
USE_KIND=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --kind)
      USE_KIND=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--kind]"
      echo ""
      echo "Options:"
      echo "  --kind    Use Kind cluster networking (container hostname instead of localhost)"
      exit 1
      ;;
  esac
done

echo "=== Kargo Control Plane Kubeconfig Setup ==="
echo ""
echo "This script creates a kubeconfig for distributed Kargo controllers"
echo "to access the central control plane."
echo ""

if [ "$USE_KIND" = true ]; then
  echo "Mode: Kind cluster (using container hostname)"
else
  echo "Mode: Standard cluster (using external API server)"
fi
echo ""

# Check prerequisites
if ! kubectl config current-context &> /dev/null; then
    echo "Error: kubectl is not configured. Please configure kubectl for the prod cluster."
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

# Check if Kargo is installed
if ! kubectl -n kargo get deploy kargo-api &> /dev/null; then
    echo "Warning: Kargo control plane doesn't appear to be installed in this cluster."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "Creating service account for remote controllers..."

# Create kargo namespace if it doesn't exist
kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -

# Create service account
kubectl -n kargo create serviceaccount kargo-remote-controller \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply minimal RBAC for remote controllers
echo "Applying minimal RBAC for remote controllers..."
kubectl apply -f "$(dirname "$0")/rbac-remote-controller.yaml"

echo "✓ Service account created with minimal permissions"
echo ""
echo "⚠️  SECURITY NOTE:"
echo "  Remote controllers now use 'kargo-remote-controller' ClusterRole"
echo "  instead of 'kargo-admin' for better security isolation."
echo "  Per-project secret access must be configured separately."
echo ""

echo "Waiting for service account token to be created..."
sleep 3

# Get the service account token secret name
SA_SECRET=$(kubectl -n kargo get serviceaccount kargo-remote-controller \
  -o jsonpath='{.secrets[0].name}' 2>/dev/null || true)

# If no secret (Kubernetes 1.24+), create one manually
if [ -z "$SA_SECRET" ]; then
    echo "Creating service account token secret (Kubernetes 1.24+)..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kargo-remote-controller-token
  namespace: kargo
  annotations:
    kubernetes.io/service-account.name: kargo-remote-controller
type: kubernetes.io/service-account-token
EOF
    sleep 3
    SA_SECRET="kargo-remote-controller-token"
fi

# Extract token and CA cert
echo "Extracting credentials..."
SA_TOKEN=$(kubectl -n kargo get secret "$SA_SECRET" \
  -o jsonpath='{.data.token}' | base64 -d)
CA_CERT=$(kubectl -n kargo get secret "$SA_SECRET" \
  -o jsonpath='{.data.ca\.crt}')

# Get API server URL
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# If using Kind, replace localhost with container hostname
if [ "$USE_KIND" = true ]; then
  # Extract the context name to determine the cluster name
  CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}')

  # For kind clusters, the container name is typically the cluster name + "-control-plane"
  # and they communicate internally on port 6443
  if [[ "$CLUSTER_NAME" == kind-* ]]; then
    # Extract the cluster suffix (e.g., "prod" from "kind-prod")
    CLUSTER_SUFFIX="${CLUSTER_NAME#kind-}"
    CONTAINER_NAME="${CLUSTER_SUFFIX}-control-plane"
    API_SERVER="https://${CONTAINER_NAME}:6443"
    echo "Kind cluster detected: Using container hostname $CONTAINER_NAME"
  else
    echo "Warning: --kind flag used but cluster name doesn't match 'kind-*' pattern"
    echo "Using original API server URL"
  fi
fi

echo "API Server: $API_SERVER"
echo ""

# Create kubeconfig file
KUBECONFIG_FILE="kargo-controlplane-kubeconfig.yaml"

cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: kargo-controlplane
  cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${API_SERVER}
contexts:
- name: kargo-controlplane
  context:
    cluster: kargo-controlplane
    user: kargo-remote-controller
current-context: kargo-controlplane
users:
- name: kargo-remote-controller
  user:
    token: ${SA_TOKEN}
EOF

echo "Kubeconfig created: $KUBECONFIG_FILE"
echo ""

# Test the kubeconfig
echo "Testing kubeconfig..."
if kubectl --kubeconfig="$KUBECONFIG_FILE" cluster-info &> /dev/null; then
    echo "✓ Kubeconfig is valid and can connect to the cluster"
else
    echo "✗ Warning: Kubeconfig validation failed"
    echo "  This might be okay if the control plane API is not accessible from here"
fi

echo ""
echo "========================================="
echo "Kubeconfig created successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Create secret in DEV cluster:"
echo "   kubectl config use-context dev-cluster"
echo "   kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \\"
echo "     --from-file=kubeconfig.yaml=$KUBECONFIG_FILE"
echo ""
echo "2. Create secret in STAGING cluster:"
echo "   kubectl config use-context staging-cluster"
echo "   kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \\"
echo "     --from-file=kubeconfig.yaml=$KUBECONFIG_FILE"
echo ""
echo "3. Install Kargo controllers:"
echo "   - Dev: ./controller-dev/install.sh"
echo "   - Staging: ./controller-staging/install.sh"
echo ""
echo "IMPORTANT: Store this kubeconfig securely and delete when done:"
echo "  rm $KUBECONFIG_FILE"
echo ""
