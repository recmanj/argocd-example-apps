# Multi-Cluster Bootstrap Guide

This guide walks through bootstrapping the multi-cluster GitOps setup with ArgoCD, Kargo, and your applications across dev, staging, and prod environments.

## Architecture Overview

### Multi-Cluster Setup
- **3 separate Kubernetes clusters**: dev, staging, prod
- **3 separate ArgoCD instances**: one per cluster
- **Distributed Kargo architecture**:
  - **Control Plane** (prod cluster): API + webhooks + default controller
  - **Distributed Controllers** (dev/staging clusters): Controller-only, "phone home" to control plane
- **Environment-specific ApplicationSets**: each cluster only manages its own environment's applications

### Component Flow
```
┌────────────────────────────────────────────────────────────────┐
│ Dev Cluster                                                     │
│  ├── cert-manager (manual bootstrap)                           │
│  ├── ArgoCD (overlay: dev)                                     │
│  ├── Kargo Controller (dev-shard) ────┐                        │
│  │   └── Manages dev Stages           │ kubeconfig            │
│  └── ApplicationSet (overlay: dev)     │ secret                │
│       ├── nginx (namespace: nginx)     │                       │
│       ├── kustomize-guestbook          │                       │
│       └── cert-manager                 │                       │
└────────────────────────────────────────┼───────────────────────┘
                                         │
┌────────────────────────────────────────┼───────────────────────┐
│ Staging Cluster                        │                       │
│  ├── cert-manager (manual bootstrap)  │                       │
│  ├── ArgoCD (overlay: staging)         │                       │
│  ├── Kargo Controller (staging-shard)─┤                       │
│  │   └── Manages staging Stages       │ kubeconfig            │
│  └── ApplicationSet (overlay: staging) │ secret                │
│       ├── nginx (namespace: nginx)     │                       │
│       ├── kustomize-guestbook          │                       │
│       └── cert-manager                 │                       │
└────────────────────────────────────────┼───────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Prod Cluster - Kargo Control Plane                              │
│  ├── cert-manager (manual bootstrap)                            │
│  ├── ArgoCD (overlay: prod)                                     │
│  ├── Kargo Control Plane                                        │
│  │   ├── API Server (UI, CLI access)                           │
│  │   ├── Webhooks Server                                        │
│  │   ├── Default Controller (manages prod Stages)              │
│  │   ├── All Kargo CRDs & Resources:                           │
│  │   │   ├── Warehouses (cert-manager, nginx, guestbook)       │
│  │   │   ├── Stages (9 total - 3 apps × 3 envs)               │
│  │   │   └── Freight (versions/artifacts)                      │
│  └── ApplicationSet (overlay: prod)                             │
│       ├── nginx (namespace: nginx)                              │
│       ├── kustomize-guestbook                                   │
│       └── cert-manager                                          │
└─────────────────────────────────────────────────────────────────┘

Git Repository
  ├── kargo/{app}/dev (rendered manifests)
  ├── kargo/{app}/staging (rendered manifests)
  └── kargo/{app}/prod (rendered manifests)

Promotion Flow:
  Warehouse → dev-shard → staging-shard → default controller
```

## Prerequisites

Before starting:
- Access to 3 Kubernetes clusters (dev, staging, prod)
- kubectl configured with contexts for each cluster
- Helm v3.13.1 or later
- htpasswd utility (for Kargo)
- Git repository access (https://github.com/recmanj/argocd-example-apps.git)

## Bootstrap Order

**Critical**: Components must be installed in this order due to dependencies.

### Phase 1: cert-manager (All Clusters)

cert-manager is required by Kargo and potentially other applications.

**For each cluster (dev, staging, prod):**

```bash
# Switch to cluster context
kubectl config use-context <cluster-context>

# Install cert-manager
cd argocd/bootstrap/00-cert-manager
./install.sh

# Verify
kubectl -n cert-manager get pods
```

**Documentation**: See [00-cert-manager/README.md](./00-cert-manager/README.md)

### Phase 2: ArgoCD (All Clusters)

Install ArgoCD with environment-specific configurations.

**Dev cluster:**
```bash
kubectl config use-context dev-cluster
cd argocd/bootstrap/01-argocd-install
./install.sh dev
```

**Staging cluster:**
```bash
kubectl config use-context staging-cluster
cd argocd/bootstrap/01-argocd-install
./install.sh staging
```

**Prod cluster:**
```bash
kubectl config use-context prod-cluster
cd argocd/bootstrap/01-argocd-install
./install.sh prod
```

**Get ArgoCD credentials:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Documentation**: See [01-argocd-install/README.md](./01-argocd-install/README.md)

### Phase 3: Kargo Distributed Architecture

Kargo uses a distributed controller architecture. Install in this order:

#### 3.1: Install Kargo Control Plane (Prod Cluster)

```bash
kubectl config use-context prod-cluster
cd argocd/bootstrap/02-kargo-install
./install-controlplane.sh
```

This installs:
- API server
- Webhooks server
- Default controller (manages prod Stages)
- All Kargo CRDs

**IMPORTANT**: Save the admin credentials displayed!

#### 3.2: Create Kubeconfig for Control Plane Access

```bash
# Ensure you're in prod cluster
kubectl config use-context prod-cluster
cd kubeconfig-setup
./create-kubeconfig.sh
```

This creates a service account and kubeconfig file that distributed controllers use to access the control plane.

#### 3.3: Deploy Kubeconfig Secret to Dev Cluster

```bash
kubectl config use-context dev-cluster
cd kubeconfig-setup
./deploy-secret.sh dev
```

#### 3.4: Deploy Kubeconfig Secret to Staging Cluster

```bash
kubectl config use-context staging-cluster
cd kubeconfig-setup
./deploy-secret.sh staging
```

#### 3.5: Install Dev Controller

```bash
kubectl config use-context dev-cluster
cd argocd/bootstrap/02-kargo-install/controller-dev
./install.sh
```

This installs controller-only (no API/webhooks) with shard name `dev-shard`.

#### 3.6: Install Staging Controller

```bash
kubectl config use-context staging-cluster
cd argocd/bootstrap/02-kargo-install/controller-staging
./install.sh
```

This installs controller-only (no API/webhooks) with shard name `staging-shard`.

**Documentation**: See [02-kargo-install/README.md](./02-kargo-install/README.md) for detailed architecture and troubleshooting

### Phase 4: Deploy Kargo Resources

Deploy Kargo projects, warehouses, and stages.

```bash
kubectl config use-context prod-cluster

# Deploy Kargo project and resources
kubectl apply -f kargo/project/project.yaml
kubectl apply -f kargo/project/promotiontasks.yaml
kubectl apply -f kargo/project/warehouses/
kubectl apply -f kargo/project/stages/
```

**Verify:**
```bash
kubectl -n argocd-example-apps get warehouses
kubectl -n argocd-example-apps get stages
```

### Phase 5: ApplicationSet Bootstrap (All Clusters)

Deploy the ApplicationSet bootstrap Application in each cluster. This creates an ArgoCD Application that manages the ApplicationSet from Git.

**Dev cluster:**
```bash
kubectl config use-context dev-cluster
cd argocd/bootstrap/03-appset-bootstrap
./install.sh dev
```

**Staging cluster:**
```bash
kubectl config use-context staging-cluster
cd argocd/bootstrap/03-appset-bootstrap
./install.sh staging
```

**Prod cluster:**
```bash
kubectl config use-context prod-cluster
cd argocd/bootstrap/03-appset-bootstrap
./install.sh prod
```

**Verify ApplicationSet is working:**
```bash
# Check ApplicationSet was created
kubectl -n argocd get applicationset

# Check Applications were generated
kubectl -n argocd get applications
```

You should see applications like:
- `nginx`
- `kustomize-guestbook`
- `cert-manager`

**Documentation**: See [03-appset-bootstrap/README.md](./03-appset-bootstrap/README.md)

## Verification

### Check ArgoCD (Each Cluster)

```bash
# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
# Username: admin
# Password: (from step 2)
```

You should see:
- The bootstrap Application (`argocd-example-apps-appset`)
- Individual applications (`nginx`, `kustomize-guestbook`, `cert-manager`)

### Check Kargo (Prod Cluster)

```bash
# Port forward Kargo UI
kubectl port-forward svc/kargo-api -n kargo 8081:80

# Access at http://localhost:8081
# Username: admin
# Password: (from step 3)
```

You should see:
- Project: `argocd-example-apps`
- Warehouses: `cert-manager`, `nginx`, `kustomize-guestbook`
- Stages: 9 stages (3 environments × 3 apps)

### Check Applications Are Running (Each Cluster)

```bash
# List application namespaces
kubectl get namespaces | grep -E "nginx|kustomize-guestbook|cert-manager"

# Check pods in each namespace
kubectl -n nginx get pods
kubectl -n kustomize-guestbook get pods
kubectl -n cert-manager get pods
```

## Using Kargo for Promotions

### Promotion Flow

1. **New version detected**: Warehouse detects new image version or Git change
2. **Auto-promotion to dev**: Dev stages automatically promote new freight
3. **Manual promotion to staging**: Review and promote from dev to staging via Kargo UI
4. **Manual promotion to prod**: Review and promote from staging to prod via Kargo UI

### Promoting an Application

Via Kargo UI:
1. Access Kargo UI (http://localhost:8081)
2. Navigate to the project `argocd-example-apps`
3. Select a stage (e.g., `nginx-staging`)
4. Click "Promote" on available freight
5. Confirm promotion

Via CLI:
```bash
# Promote to staging
kubectl -n argocd-example-apps create promotion nginx-staging-promotion \
  --from-freight=<freight-id>
```

### Checking Promotion Status

```bash
# View freight status
kubectl -n argocd-example-apps get freight

# View promotion history
kubectl -n argocd-example-apps get promotions

# Check specific stage
kubectl -n argocd-example-apps get stage nginx-dev -o yaml
```

## Architecture Decisions

### Why Simplified Namespaces?

In the multi-cluster setup:
- **Old pattern**: `{app}-{env}` (e.g., `nginx-dev`, `nginx-staging`, `nginx-prod`)
- **New pattern**: `{app}` (e.g., `nginx`)

**Rationale**: Each cluster only runs one environment, so the environment suffix is redundant. This simplifies:
- Namespace management
- Resource naming
- Application references

### Why Centralized Kargo?

Kargo is deployed centrally (prod cluster) because:
1. **Single source of truth** for promotion pipelines
2. **Simplified management** of stages and warehouses
3. **Cross-cluster promotion** orchestration from one place
4. **Resource efficiency** - only one Kargo installation

### Why Bootstrap cert-manager?

cert-manager must be manually installed first because:
1. **Kargo depends on it** (requires cert-manager CRDs)
2. **Chicken-and-egg problem**: Can't use Kargo to manage cert-manager until cert-manager exists
3. **After bootstrap**: Kargo manages cert-manager updates and promotions

## Troubleshooting

### ApplicationSet not creating Applications

```bash
# Check ApplicationSet status
kubectl -n argocd describe applicationset argocd-example-apps

# Check ArgoCD logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

### Kargo promotions not working

```bash
# Check Kargo controller logs
kubectl -n kargo logs -l app.kubernetes.io/name=kargo-controller --tail=100

# Verify stage configuration
kubectl -n argocd-example-apps get stage <stage-name> -o yaml

# Check if freight exists
kubectl -n argocd-example-apps get freight
```

### Applications stuck syncing

```bash
# Check application status
kubectl -n argocd get application <app-name> -o yaml

# Force refresh
kubectl -n argocd patch application <app-name> -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

### Multi-cluster access issues

```bash
# Verify Kargo can reach other clusters
kubectl -n kargo get secrets

# Check cluster credentials
kubectl -n kargo describe secret <cluster-secret>
```

## Adding a New Application

To add a new application to the GitOps pipeline:

1. **Create app structure**:
```bash
mkdir -p _apps/myapp/{base,envs/{dev,staging,prod}}
```

2. **Add Kustomize configuration** to base and environments

3. **Create Kargo warehouse** in `kargo/project/warehouses/myapp.yaml`

4. **Create Kargo stages** in `kargo/project/stages/`:
   - `myapp-dev.yaml`
   - `myapp-staging.yaml`
   - `myapp-prod.yaml`

5. **Commit and push** - ApplicationSets will auto-discover the new app

6. **Verify** in ArgoCD UI that new Applications were created

## Maintenance

### Upgrading ArgoCD

1. Update version in `argocd/bootstrap/01-argocd-install/base/kustomization.yaml`
2. Apply to each cluster:
```bash
kubectl apply -k argocd/bootstrap/01-argocd-install/envs/<env>
```

### Upgrading Kargo

```bash
helm upgrade kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --reuse-values
```

### Upgrading cert-manager

cert-manager upgrades are managed by Kargo after bootstrap:
1. Update version in `_apps/cert-manager/base/kustomization.yaml`
2. Commit and push
3. Kargo promotes through dev → staging → prod

## Security Considerations

For production use:
- **Change default passwords** for ArgoCD and Kargo
- **Enable RBAC** and configure proper user access
- **Set up ingress** with TLS for ArgoCD and Kargo
- **Configure OIDC/SSO** authentication
- **Use proper Git credentials** (SSH keys, deploy tokens)
- **Secure cluster access** for Kargo's multi-cluster setup
- **Review and harden** default configurations

Refer to official documentation:
- ArgoCD: https://argo-cd.readthedocs.io/en/stable/operator-manual/security/
- Kargo: https://docs.kargo.io/operator-guide/secure-configuration

## Next Steps

After successful bootstrap:
1. Configure ingress for ArgoCD and Kargo
2. Set up authentication (OIDC, LDAP, etc.)
3. Add more applications following the pattern
4. Configure notification webhooks for promotions
5. Set up monitoring and alerting

## Support

- ArgoCD documentation: https://argo-cd.readthedocs.io/
- Kargo documentation: https://docs.kargo.io/
- Project repository: https://github.com/recmanj/argocd-example-apps
