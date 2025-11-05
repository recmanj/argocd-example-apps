#!/bin/bash
set -e

echo "=== Apply Per-Project RBAC for Remote Controllers ==="
echo ""
echo "This script grants remote controllers read-only access to Secrets"
echo "in specific project namespaces."
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
echo "The following namespaces will receive secret access:"
echo "  - argocd-example-apps (project namespace)"
echo "  - kargo-cluster-secrets (global credentials)"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Creating namespaces if they don't exist..."

# Create namespaces
kubectl create namespace argocd-example-apps --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kargo-cluster-secrets --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Applying RoleBindings..."

# Apply the per-project RBAC
kubectl apply -f "$(dirname "$0")/rbac-per-project.yaml"

echo ""
echo "========================================="
echo "Per-Project RBAC Applied Successfully!"
echo "========================================="
echo ""
echo "Remote controllers can now read Secrets in:"
echo "  ✓ argocd-example-apps"
echo "  ✓ kargo-cluster-secrets"
echo ""
echo "To add more projects, edit rbac-per-project.yaml and add"
echo "additional RoleBinding resources for each namespace."
echo ""
