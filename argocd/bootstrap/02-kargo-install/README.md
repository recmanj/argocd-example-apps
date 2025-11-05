# Kargo Multi-Cluster Installation

## Overview

Kargo uses a **distributed controller architecture** to manage promotions across multiple clusters:

- **Control Plane** (1 cluster - typically prod): API server, webhooks, management controller, all CRDs
- **Distributed Controllers** (1 per cluster): Controller-only installations that "phone home" to the control plane

### Architecture Diagram

```
┌────────────────────────────────────────────┐
│ Control Plane (Prod Cluster)              │
│  ├── Kargo API Server                     │
│  ├── Kargo Management Controller (default)│
│  ├── Webhooks Server                      │
│  └── All Kargo CRDs & Resources           │
└────────────────────────────────────────────┘
                    ▲ ▲
                    │ │
        ┌───────────┘ └───────────┐
        │ kubeconfig               │ kubeconfig
        │ secret                   │ secret
        │                          │
┌───────┴────────────┐    ┌───────┴────────────┐
│ Dev Cluster        │    │ Staging Cluster    │
│  Kargo Controller  │    │  Kargo Controller  │
│  (dev-shard)       │    │  (staging-shard)   │
│  + Local ArgoCD    │    │  + Local ArgoCD    │
└────────────────────┘    └────────────────────┘
```

## Prerequisites

- cert-manager installed in all clusters (see `../00-cert-manager/`)
- ArgoCD installed in all clusters (see `../01-argocd-install/`)
- Helm v3.13.1 or later
- htpasswd utility (for control plane)
- kubectl configured with contexts for all clusters

## Installation Order

Kargo must be installed in a specific order due to dependencies:

### 1. Install Control Plane (Prod Cluster)

The control plane provides the API, webhooks, and manages all Kargo resources.

```bash
# Switch to prod cluster
kubectl config use-context prod-cluster

# Run interactive installer
./install.sh
# Select option 1: Control Plane

# Or run directly
./install-controlplane.sh
```

This will:
- Generate secure admin credentials
- Install full Kargo (API + controller + webhooks)
- Configure as default controller (no shard assignment)

**Save the admin credentials displayed!**

### 2. Create Kubeconfig for Control Plane Access

Distributed controllers need kubeconfig to access the control plane.

```bash
# Ensure you're in prod cluster
kubectl config use-context prod-cluster

cd kubeconfig-setup
./create-kubeconfig.sh
```

This creates:
- Service account in prod cluster
- Kubeconfig file: `kargo-controlplane-kubeconfig.yaml`

**Keep this file secure!**

### 3. Deploy Kubeconfig Secret to Dev Cluster

```bash
# Switch to dev cluster
kubectl config use-context dev-cluster

cd kubeconfig-setup
./deploy-secret.sh dev
```

### 4. Deploy Kubeconfig Secret to Staging Cluster

```bash
# Switch to staging cluster
kubectl config use-context staging-cluster

cd kubeconfig-setup
./deploy-secret.sh staging
```

### 5. Install Dev Controller

```bash
# Ensure you're in dev cluster
kubectl config use-context dev-cluster

./install.sh
# Select option 2: Dev Controller

# Or run directly
cd controller-dev
./install.sh
```

This installs:
- Controller only (no API/webhooks)
- Shard name: `dev-shard`
- Connects to control plane via kubeconfig secret

### 6. Install Staging Controller

```bash
# Ensure you're in staging cluster
kubectl config use-context staging-cluster

./install.sh
# Select option 3: Staging Controller

# Or run directly
cd controller-staging
./install.sh
```

This installs:
- Controller only (no API/webhooks)
- Shard name: `staging-shard`
- Connects to control plane via kubeconfig secret

### 7. Deploy Kargo Resources

Deploy Projects, Warehouses, and Stages to the control plane:

```bash
# Switch to prod cluster (where control plane is)
kubectl config use-context prod-cluster

# Deploy all Kargo resources
kubectl apply -f ../../kargo/project/
```

**Important**: Stages must have shard assignments:
- Dev Stages: `spec.shard: dev-shard`
- Staging Stages: `spec.shard: staging-shard`
- Prod Stages: No shard (handled by default controller)

## Verification

### Check Control Plane (Prod Cluster)

```bash
kubectl config use-context prod-cluster

# Check pods
kubectl -n kargo get pods

# Should see:
# - kargo-api-*
# - kargo-controller-*
# - kargo-webhooks-server-*

# Check Kargo resources
kubectl -n argocd-example-apps get warehouses
kubectl -n argocd-example-apps get stages
kubectl -n argocd-example-apps get freight
```

### Check Dev Controller

```bash
kubectl config use-context dev-cluster

# Check pods
kubectl -n kargo get pods

# Should see only:
# - kargo-controller-*

# Check controller logs
kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=50

# Look for "shard=dev-shard" in logs
```

### Check Staging Controller

```bash
kubectl config use-context staging-cluster

# Check pods
kubectl -n kargo get pods

# Should see only:
# - kargo-controller-*

# Check controller logs
kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=50

# Look for "shard=staging-shard" in logs
```

### Verify Sharding

Check that Stages are assigned to correct shards:

```bash
kubectl config use-context prod-cluster

# List Stages with shard assignments
kubectl -n argocd-example-apps get stages -o yaml | grep -A 1 "name:"| grep -A 1 "shard:"

# Expected output:
# cert-manager-dev:    shard: dev-shard
# nginx-dev:           shard: dev-shard
# ...
# cert-manager-staging: shard: staging-shard
# nginx-staging:       shard: staging-shard
# ...
# cert-manager-prod:   <no shard> (default)
# nginx-prod:          <no shard> (default)
```

## Access Kargo UI

The Kargo UI is only available via the control plane:

```bash
kubectl config use-context prod-cluster
kubectl port-forward svc/kargo-api -n kargo 8081:80
```

Access at: http://localhost:8081
- Username: `admin`
- Password: (from installation step 1)

## Directory Structure

```
02-kargo-install/
├── README.md (this file)
├── install.sh                      # Interactive installer
├── install-controlplane.sh         # Control plane installation
├── values-controlplane.yaml        # Control plane Helm values
├── values-prod.yaml                # Legacy (replaced by values-controlplane.yaml)
├── controller-dev/
│   ├── values.yaml                 # Dev controller Helm values
│   └── install.sh                  # Dev controller installation
├── controller-staging/
│   ├── values.yaml                 # Staging controller Helm values
│   └── install.sh                  # Staging controller installation
└── kubeconfig-setup/
    ├── README.md                   # Detailed kubeconfig setup guide
    ├── create-kubeconfig.sh        # Create control plane kubeconfig
    └── deploy-secret.sh            # Deploy secret to remote clusters
```

## Customization

### Control Plane

Edit `values-controlplane.yaml` to customize:
- API server replicas
- Resource limits
- Ingress configuration
- OIDC authentication
- Admin account settings

### Distributed Controllers

Edit `controller-{env}/values.yaml` to customize:
- Shard name
- Resource limits
- Log levels
- Git client configuration

## How Sharding Works

### Shard Assignment

Stages are assigned to controllers via the `spec.shard` field:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: nginx-dev
spec:
  shard: dev-shard  # This Stage is handled by dev controller
  # ... rest of spec
```

### Controller Behavior

- **Dev controller** (`shardName: dev-shard`): Reconciles only Stages with `shard: dev-shard`
- **Staging controller** (`shardName: staging-shard`): Reconciles only Stages with `shard: staging-shard`
- **Default controller** (control plane, no `shardName`): Reconciles Stages without explicit shard assignment

### Promotions

Promotions work across shards:
1. Warehouse detects new version
2. Dev controller promotes to dev Stage
3. Staging controller waits for freight from dev
4. Staging controller promotes to staging Stage
5. Default controller waits for freight from staging
6. Default controller promotes to prod Stage

## Troubleshooting

### Controller Can't Connect to Control Plane

**Symptoms:**
- Controller logs show connection errors
- Stages not reconciling

**Check:**
```bash
# Verify secret exists
kubectl -n kargo get secret kargo-controlplane-kubeconfig

# Test kubeconfig
kubectl -n kargo get secret kargo-controlplane-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/test-kubeconfig.yaml
kubectl --kubeconfig=/tmp/test-kubeconfig.yaml -n argocd-example-apps get stages

# Check network connectivity
kubectl -n kargo exec -it <controller-pod> -- curl -k <control-plane-api-url>
```

**Solutions:**
- Recreate kubeconfig secret
- Check firewall rules
- Verify service account permissions

### Stages Not Being Reconciled

**Symptoms:**
- Promotions not happening
- Stages stuck in pending

**Check:**
```bash
# Verify shard assignments match
kubectl -n argocd-example-apps get stage <stage-name> -o yaml | grep shard

# Check controller is running in correct cluster
kubectl -n kargo get pods -o yaml | grep -A 5 "SHARD_NAME"

# Check controller logs
kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=100
```

**Solutions:**
- Add shard field to Stages
- Verify controller installed with correct shard name
- Check kubeconfig secret

### API/Webhooks in Wrong Cluster

**Symptoms:**
- API pods in dev/staging clusters
- Webhook configurations in non-prod clusters

**Solution:**
Controllers should have API and webhooks disabled:
```yaml
api:
  enabled: false
webhooks:
  register: false
```

Reinstall controller with correct values.

## Security Considerations

⚠️ **IMPORTANT**: This setup has been configured with security best practices.
See [kubeconfig-setup/SECURITY.md](./kubeconfig-setup/SECURITY.md) for complete details.

### Service Account Permissions

The control plane service account (`kargo-remote-controller`) uses minimal RBAC:
- **Cluster-level**: Read Kargo CRDs, update status (via `kargo-remote-controller` ClusterRole)
- **Namespace-level**: Read secrets in specific project namespaces only (via RoleBindings)
- **NO cluster-wide secret access** (follows Kargo security best practices)

### Network Security

- Ensure mTLS between controllers and control plane
- Restrict API server access with network policies
- Use separate service accounts per cluster

### Secret Management

- Rotate service account tokens regularly
- Store kubeconfig files securely
- Delete kubeconfig files after deployment

## Upgrading

### Upgrade Control Plane

```bash
helm upgrade kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --values values-controlplane.yaml \
  --reuse-values
```

### Upgrade Controllers

```bash
# Dev controller
helm upgrade kargo-controller \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --values controller-dev/values.yaml \
  --reuse-values

# Staging controller
helm upgrade kargo-controller \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --values controller-staging/values.yaml \
  --reuse-values
```

## References

- Kargo documentation: https://docs.kargo.io/
- GitHub discussion on multi-cluster: https://github.com/akuity/kargo/discussions/2090
- Helm chart values: `helm show values oci://ghcr.io/akuity/kargo-charts/kargo`
