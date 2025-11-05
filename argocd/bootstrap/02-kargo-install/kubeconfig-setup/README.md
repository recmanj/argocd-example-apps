# Kubeconfig Setup for Distributed Kargo Controllers

## Overview
Distributed Kargo controllers need kubeconfig secrets to access the central control plane. This allows controllers in dev and staging clusters to "phone home" to read Kargo resources (Stages, Warehouses, Freight, etc.) from the control plane.

## Architecture

```
┌────────────────────────────────────────────┐
│ Control Plane (Prod Cluster)              │
│  ├── Kargo API Server                     │
│  ├── Kargo Management Controller (default)│
│  └── All Kargo CRDs & Resources           │
└────────────────────────────────────────────┘
                    ▲ ▲
                    │ │
        ┌───────────┘ └───────────┐
        │                          │
        │ kubeconfig               │ kubeconfig
        │ secret                   │ secret
        │                          │
┌───────┴────────────┐    ┌───────┴────────────┐
│ Dev Cluster        │    │ Staging Cluster    │
│  Kargo Controller  │    │  Kargo Controller  │
│  (dev-shard)       │    │  (staging-shard)   │
└────────────────────┘    └────────────────────┘
```

## Prerequisites

- Control plane installed in prod cluster
- Access to prod cluster with proper RBAC
- kubectl configured for dev and staging clusters

## Method 1: Using Service Account (Recommended)

### Step 1: Create Service Account in Control Plane

In the prod cluster where the control plane is running:

```bash
kubectl config use-context prod-cluster

# Create a service account for distributed controllers
kubectl -n kargo create serviceaccount kargo-remote-controller

# Grant the service account permissions to read Kargo resources
kubectl create clusterrolebinding kargo-remote-controller \
  --clusterrole=kargo-admin \
  --serviceaccount=kargo:kargo-remote-controller
```

### Step 2: Extract Service Account Token

```bash
# Get the service account token
SA_TOKEN=$(kubectl -n kargo get secret \
  $(kubectl -n kargo get serviceaccount kargo-remote-controller \
    -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.token}' | base64 -d)

# Get the cluster CA certificate
CA_CERT=$(kubectl -n kargo get secret \
  $(kubectl -n kargo get serviceaccount kargo-remote-controller \
    -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.ca\.crt}')

# Get the control plane API server URL
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
```

### Step 3: Create Kubeconfig File

Use the provided script:

```bash
cd argocd/bootstrap/02-kargo-install/kubeconfig-setup
./create-kubeconfig.sh
```

Or create manually:

```bash
cat > kargo-controlplane-kubeconfig.yaml <<EOF
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
```

### Step 4: Create Secrets in Remote Clusters

**In dev cluster:**
```bash
kubectl config use-context dev-cluster

kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \
  --from-file=kubeconfig=kargo-controlplane-kubeconfig.yaml

# Verify
kubectl -n kargo get secret kargo-controlplane-kubeconfig
```

**In staging cluster:**
```bash
kubectl config use-context staging-cluster

kubectl -n kargo create secret generic kargo-controlplane-kubeconfig \
  --from-file=kubeconfig=kargo-controlplane-kubeconfig.yaml

# Verify
kubectl -n kargo get secret kargo-controlplane-kubeconfig
```

## Method 2: Using Existing Kubeconfig

If you have an existing kubeconfig with access to the prod cluster:

### Step 1: Extract Prod Cluster Context

```bash
# Export just the prod cluster context from your kubeconfig
kubectl config view --minify --flatten --context=prod-cluster > kargo-controlplane-kubeconfig.yaml
```

### Step 2: Create Secrets in Remote Clusters

Same as Method 1, Step 4 above.

## Security Considerations

### Service Account Permissions

The service account needs read access to Kargo resources. Grant minimal permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-remote-controller
rules:
- apiGroups: ["kargo.akuity.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch"]
```

### Network Access

Ensure distributed controllers can reach the control plane API server:
- Firewall rules allowing traffic
- Network policies permitting egress
- DNS resolution for API server hostname

### Secret Rotation

Regularly rotate service account tokens:

```bash
# Delete the old secret
kubectl -n kargo delete secret kargo-remote-controller-token-xxxxx

# A new token will be automatically generated
# Re-run the kubeconfig creation steps
```

## Troubleshooting

### Controller Can't Connect to Control Plane

Check controller logs:
```bash
kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller
```

Common issues:
- **Secret not found**: Ensure secret exists in kargo namespace
- **Permission denied**: Verify service account has proper RBAC
- **Network timeout**: Check firewall and network policies
- **Certificate errors**: Verify CA cert in kubeconfig

### Verify Secret Content

```bash
# Extract and test the kubeconfig
kubectl -n kargo get secret kargo-controlplane-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > test-kubeconfig.yaml

# Test connectivity
kubectl --kubeconfig=test-kubeconfig.yaml -n argocd-example-apps get stages
```

### Check Controller Status

```bash
# See which shard the controller is handling
kubectl -n kargo get pods -l app.kubernetes.io/name=kargo-controller -o yaml | grep -A 5 "args:"

# Check if controller can see Stages
kubectl --kubeconfig=test-kubeconfig.yaml -n argocd-example-apps get stages
```

## Cleanup

To remove kubeconfig secrets:

```bash
# In dev cluster
kubectl -n kargo delete secret kargo-controlplane-kubeconfig

# In staging cluster
kubectl -n kargo delete secret kargo-controlplane-kubeconfig
```

To remove service account from control plane:

```bash
kubectl -n kargo delete serviceaccount kargo-remote-controller
kubectl delete clusterrolebinding kargo-remote-controller
```

## Next Steps

After creating kubeconfig secrets:
1. Install Kargo controllers in dev and staging (see `../controller-dev/` and `../controller-staging/`)
2. Verify controllers can connect to control plane
3. Deploy Kargo resources (Stages with shard assignments)
4. Test promotions across clusters
