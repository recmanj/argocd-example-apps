# ArgoCD Multi-Cluster Configuration

This directory contains the ArgoCD ApplicationSet configuration for managing applications across multiple clusters (dev, staging, prod).

## Directory Structure

```
argocd/
├── base/
│   ├── appset.yaml              # Base ApplicationSet definition
│   └── kustomization.yaml       # Base kustomization
├── envs/
│   ├── dev/
│   │   └── kustomization.yaml   # Dev overlay (filters _apps/*/envs/dev)
│   ├── staging/
│   │   └── kustomization.yaml   # Staging overlay (filters _apps/*/envs/staging)
│   └── prod/
│       └── kustomization.yaml   # Prod overlay (filters _apps/*/envs/prod)
├── bootstrap/
│   ├── 00-cert-manager/         # cert-manager installation (prerequisite)
│   ├── 01-argocd-install/       # ArgoCD installation with envs
│   ├── 02-kargo-install/        # Kargo installation (centralized)
│   └── 03-appset-bootstrap/     # App-of-apps for ApplicationSet
└── argocd-example-apps-appset.yaml  # LEGACY - replaced by base + envs

```

## Architecture

### Base + envs Pattern

The ApplicationSet uses Kustomize base + envs to support multiple clusters:

**Base** (`base/appset.yaml`):
- Generic ApplicationSet template
- Discovers apps in `_apps/*/envs/*`
- Creates Applications with simplified names (no env suffix)

**envs** (`envs/{env}/`):
- Environment-specific patches
- Filters directories for specific environment only
- Dev: `_apps/*/envs/dev`
- Staging: `_apps/*/envs/staging`
- Prod: `_apps/*/envs/prod`

### Multi-Cluster Setup

Each cluster runs:
1. **cert-manager** (manually bootstrapped)
2. **ArgoCD** (environment-specific overlay)
3. **ApplicationSet** (environment-specific overlay)
   - Discovers applications for its environment only
   - Creates Applications in simplified namespaces

Example for nginx in dev cluster:
- Application name: `nginx` (not `nginx-dev`)
- Namespace: `nginx` (not `nginx-dev`)
- Source: `_apps/nginx/envs/dev/`
- Kargo branch: `kargo/nginx/dev`

### Kargo Integration

Kargo is deployed centrally (typically in prod cluster) and manages promotions across all environments.

**Promotion pipeline:**
```
Warehouse (new version) → dev (auto) → staging (manual) → prod (manual)
```

**Kargo branches:**
- `kargo/{app}/dev` - Rendered manifests for dev
- `kargo/{app}/staging` - Rendered manifests for staging
- `kargo/{app}/prod` - Rendered manifests for prod

## Quick Start

### Bootstrap a New Cluster

1. **Install cert-manager:**
```bash
cd bootstrap/00-cert-manager
./install.sh
```

2. **Install ArgoCD:**
```bash
cd bootstrap/01-argocd-install
./install.sh <dev|staging|prod>
```

3. **Install Kargo** (prod cluster only):
```bash
cd bootstrap/02-kargo-install
./install.sh
```

4. **Deploy ApplicationSet:**
```bash
cd bootstrap/03-appset-bootstrap
./install.sh <dev|staging|prod>
```

### Test envs

To see what each overlay produces:

```bash
# Dev overlay
kubectl kustomize envs/dev

# Staging overlay
kubectl kustomize envs/staging

# Prod overlay
kubectl kustomize envs/prod
```

## Application Discovery

The ApplicationSet automatically discovers applications following this pattern:

```
_apps/
└── {app-name}/
    ├── base/
    │   └── kustomization.yaml
    └── envs/
        ├── dev/
        │   └── kustomization.yaml
        ├── staging/
        │   └── kustomization.yaml
        └── prod/
            └── kustomization.yaml
```

For each matching directory, an Application is created:
- **Name**: `{app-name}`
- **Namespace**: `{app-name}`
- **Source path**: Points to root (kustomized manifest in Kargo branch)
- **Target revision**: `kargo/{app-name}/{env}`

## Key Changes from Single-Cluster

### Old Configuration (single cluster)
```yaml
# Application name included environment
name: '{{index .path.segments 1}}-{{.path.basename}}'  # nginx-dev

# Namespace included environment
namespace: '{{index .path.segments 1}}-{{.path.basename}}'  # nginx-dev

# Discovered all environments
path: _apps/*/envs/*
```

### New Configuration (multi-cluster)
```yaml
# Application name is just the app
name: '{{index .path.segments 1}}'  # nginx

# Namespace is just the app
namespace: '{{index .path.segments 1}}'  # nginx

# Each cluster filters its environment
# Dev: _apps/*/envs/dev
# Staging: _apps/*/envs/staging
# Prod: _apps/*/envs/prod
```

## Adding a New Application

1. Create directory structure:
```bash
mkdir -p _apps/myapp/{base,envs/{dev,staging,prod}}
```

2. Add Kustomize configs to base and environments

3. Create Kargo resources (optional, if using Kargo):
   - Warehouse: `kargo/project/warehouses/myapp.yaml`
   - Stages: `kargo/project/stages/myapp-{dev,staging,prod}.yaml`

4. Commit and push - ApplicationSet auto-discovers the new app

5. Verify in ArgoCD UI

## Upgrading

### Update ApplicationSet Version
Changes to the ApplicationSet are managed via Git:

1. Update files in `base/` or `envs/`
2. Commit and push
3. The bootstrap Application syncs changes automatically
4. ApplicationSet updates and regenerates Applications

### Rollback
```bash
# Revert Git commit
git revert <commit-hash>
git push

# Force sync in ArgoCD
kubectl -n argocd patch application argocd-example-apps-appset \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

## Troubleshooting

### No Applications Generated

Check ApplicationSet status:
```bash
kubectl -n argocd get applicationset argocd-example-apps -o yaml
kubectl -n argocd describe applicationset argocd-example-apps
```

Common issues:
- Git repository access problems
- Directory pattern doesn't match
- ApplicationSet controller not running

### Wrong Environment's Apps Showing Up

Verify the overlay patch in `envs/{env}/kustomization.yaml`:
```yaml
patches:
  - patch: |-
      - op: replace
        path: /spec/generators/0/git/directories/0/path
        value: _apps/*/envs/dev  # Should match environment
```

### Applications Not Syncing

Check ArgoCD Application status:
```bash
kubectl -n argocd get application <app-name> -o yaml
```

Common issues:
- Kargo branch doesn't exist yet (wait for first promotion)
- Git credentials not configured
- Target namespace doesn't exist (should auto-create)

## Documentation

- **Bootstrap Guide**: [bootstrap/README.md](./bootstrap/README.md) - Complete multi-cluster setup guide
- **Overlay Details**: [envs/README.md](./envs/README.md) - Overlay configuration details
- **cert-manager**: [bootstrap/00-cert-manager/README.md](./bootstrap/00-cert-manager/README.md)
- **ArgoCD**: [bootstrap/01-argocd-install/README.md](./bootstrap/01-argocd-install/README.md)
- **Kargo**: [bootstrap/02-kargo-install/README.md](./bootstrap/02-kargo-install/README.md)
- **ApplicationSet Bootstrap**: [bootstrap/03-appset-bootstrap/README.md](./bootstrap/03-appset-bootstrap/README.md)

## References

- ArgoCD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/
- Kustomize: https://kustomize.io/
- Kargo: https://docs.kargo.io/
