# Security Configuration for Kargo Distributed Controllers

This document explains the security model and RBAC configuration for Kargo distributed controllers.

## Overview

Kargo distributed controllers need access to:
1. **Kargo CRDs** (Stages, Freight, Warehouses, Promotions) - for reading/updating promotion state
2. **Git credentials** - for committing and pushing changes during promotions
3. **Docker registry credentials** (optional) - for reading image metadata
4. **ArgoCD credentials** (optional) - for triggering ArgoCD syncs

## Security Principle: Least Privilege

Remote controllers (dev, staging shards) run in separate clusters and should have **minimal permissions** to the control plane. They should NOT have cluster-admin or kargo-admin level access.

### What Changed

**BEFORE (Insecure):**
- Remote controllers used `kargo-admin` ClusterRole
- Had full administrative access to entire control plane cluster
- Could read ALL secrets cluster-wide
- Violation of least privilege principle

**AFTER (Secure):**
- Remote controllers use custom `kargo-remote-controller` ClusterRole
- Read-only access to Kargo CRDs
- Write access only to status subresources
- Secret access limited to specific project namespaces via RoleBindings

## RBAC Architecture

### 1. Cluster-Level Permissions

**ClusterRole: `kargo-remote-controller`**
- Read access to Kargo resources (Stages, Freight, Warehouses, etc.)
- Update access to status subresources
- Create/update Promotions
- Read access to ConfigMaps
- **NO cluster-wide Secret access**

```yaml
# Applied via: kubectl apply -f rbac-remote-controller.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-remote-controller
rules:
- apiGroups: ["kargo.akuity.io"]
  resources: [stages, freight, warehouses, promotions]
  verbs: [get, list, watch]
- apiGroups: ["kargo.akuity.io"]
  resources: [stages/status, freight/status, promotions/status]
  verbs: [update, patch]
# ... (see rbac-remote-controller.yaml for full details)
```

### 2. Namespace-Level Secret Access

**Per-Project RoleBindings**
- Grant secret access ONLY in specific namespaces
- Use Kargo's built-in `kargo-controller-read-secrets` ClusterRole
- Applied per-namespace for fine-grained control

```yaml
# Applied via: ./apply-per-project-rbac.sh
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kargo-remote-controller-read-secrets
  namespace: argocd-example-apps  # Project namespace
roleRef:
  kind: ClusterRole
  name: kargo-controller-read-secrets
subjects:
- kind: ServiceAccount
  name: kargo-remote-controller
  namespace: kargo
```

## Credential Management

### Git Credentials

Git credentials are required for controllers to commit and push changes during promotions.

**Where to store:**
- Project namespace: `argocd-example-apps`
- Global namespace: `kargo-cluster-secrets`

**Example Git credential secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
  namespace: kargo-cluster-secrets
  labels:
    kargo.akuity.io/cred-type: git
type: Opaque
stringData:
  repoURL: https://github.com/yourorg/yourrepo.git
  username: git
  password: ghp_your_github_token_here
```

### Docker Registry Credentials

For reading image metadata from private registries:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: docker-registry-credentials
  namespace: kargo-cluster-secrets
  labels:
    kargo.akuity.io/cred-type: image
type: Opaque
stringData:
  repoURL: https://index.docker.io
  username: your-docker-username
  password: your-docker-password
```

### Namespace Configuration

Controllers are configured to look for credentials in specific namespaces:

```yaml
# In controller-dev/values.yaml and controller-staging/values.yaml
controller:
  sharedCredentialsNamespaces:
    - argocd-example-apps    # Project-specific credentials
    - kargo-cluster-secrets  # Global credentials
```

## Security Checklist

### Initial Setup
- [ ] Apply minimal RBAC: `kubectl apply -f rbac-remote-controller.yaml`
- [ ] Apply per-project RoleBindings: `./apply-per-project-rbac.sh`
- [ ] Verify `clusterWideSecretReadingEnabled: false` in all controller values files
- [ ] Remove committed kubeconfig files (already in .gitignore)
- [ ] Store Git credentials in appropriate namespaces

### Ongoing Maintenance
- [ ] Rotate service account tokens every 90 days: `./rotate-token.sh`
- [ ] Review and audit secret access regularly
- [ ] Add new projects via per-project RoleBindings
- [ ] Monitor controller logs for permission errors

## Troubleshooting

### Controller can't access Git credentials

**Symptom:** Promotion fails with "permission denied" or "secret not found"

**Check:**
1. Verify secret exists in correct namespace:
   ```bash
   kubectl -n kargo-cluster-secrets get secrets
   ```

2. Verify RoleBinding exists:
   ```bash
   kubectl -n kargo-cluster-secrets get rolebinding kargo-remote-controller-read-secrets
   ```

3. Verify secret is properly labeled:
   ```bash
   kubectl -n kargo-cluster-secrets get secret git-credentials -o yaml
   # Should have label: kargo.akuity.io/cred-type: git
   ```

4. Check controller has access:
   ```bash
   kubectl auth can-i get secrets \
     --as=system:serviceaccount:kargo:kargo-remote-controller \
     -n kargo-cluster-secrets
   ```

### Controller has too many permissions

**Check current permissions:**
```bash
kubectl get clusterrolebinding kargo-remote-controller -o yaml
```

**Should see:**
- ClusterRole: `kargo-remote-controller` (NOT `kargo-admin`)

**If using kargo-admin:**
```bash
# Delete old binding
kubectl delete clusterrolebinding kargo-remote-controller

# Apply new minimal RBAC
kubectl apply -f rbac-remote-controller.yaml
```

## Migration from Old Setup

If you're upgrading from the previous insecure setup:

1. **Rotate credentials immediately:**
   ```bash
   ./rotate-token.sh
   ```

2. **Update RBAC:**
   ```bash
   # Delete old binding with kargo-admin
   kubectl delete clusterrolebinding kargo-remote-controller

   # Apply new minimal RBAC
   kubectl apply -f rbac-remote-controller.yaml

   # Apply per-project RoleBindings
   ./apply-per-project-rbac.sh
   ```

3. **Update controller deployments:**
   ```bash
   # Dev cluster
   kubectl config use-context dev-cluster
   helm upgrade kargo-controller oci://ghcr.io/akuity/kargo-charts/kargo \
     --namespace kargo \
     --values controller-dev/values.yaml \
     --reuse-values

   # Staging cluster
   kubectl config use-context staging-cluster
   helm upgrade kargo-controller oci://ghcr.io/akuity/kargo-charts/kargo \
     --namespace kargo \
     --values controller-staging/values.yaml \
     --reuse-values
   ```

4. **Verify controllers still function:**
   ```bash
   kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=100
   ```

## References

- [Kargo Security Documentation](https://docs.kargo.io/operator-guide/security/)
- [Managing Credentials](https://docs.kargo.io/operator-guide/security/managing-credentials/)
- [Kubernetes RBAC Best Practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)
