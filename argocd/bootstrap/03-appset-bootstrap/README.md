# ApplicationSet Bootstrap (App-of-Apps)

## Overview
These Application manifests bootstrap the ApplicationSet in each cluster. Once applied, ArgoCD will manage the ApplicationSet from Git, which in turn manages all applications.

## Prerequisites
- cert-manager installed (see `../00-cert-manager/`)
- ArgoCD installed (see `../01-argocd-install/`)
- Kargo installed in prod cluster (see `../02-kargo-install/`)
- ApplicationSet base and envs created (in `/argocd/base/` and `/argocd/envs/`)

## Installation

### Deploy to Dev Cluster
```bash
kubectl apply -f dev-appset.yaml
```

### Deploy to Staging Cluster
```bash
kubectl apply -f staging-appset.yaml
```

### Deploy to Prod Cluster
```bash
kubectl apply -f prod-appset.yaml
```

### Or use the install script
```bash
./install.sh dev      # For dev cluster
./install.sh staging  # For staging cluster
./install.sh prod     # For prod cluster
```

## What This Does

Each Application:
1. Points to the appropriate overlay in Git (`argocd/envs/{env}/`)
2. Deploys the ApplicationSet to the `argocd` namespace
3. Enables automated sync (self-heal + prune)
4. The ApplicationSet then discovers and manages all apps in `_apps/*/envs/{env}/`

## Verification

Check that the bootstrap Application is synced:
```bash
kubectl -n argocd get application argocd-example-apps-appset
```

Check that the ApplicationSet was created:
```bash
kubectl -n argocd get applicationset
```

Check that individual applications were created by the ApplicationSet:
```bash
kubectl -n argocd get applications
```

You should see applications like:
- `nginx` (in dev cluster)
- `kustomize-guestbook` (in dev cluster)
- `cert-manager` (once added)

## Architecture

```
Bootstrap App (manual, one-time)
  └── ApplicationSet (managed by ArgoCD from Git)
        ├── nginx Application (auto-discovered)
        ├── kustomize-guestbook Application (auto-discovered)
        └── cert-manager Application (auto-discovered)
```

## Customization

To customize the bootstrap Application:
- Update `repoURL` if using a different Git repository
- Change `targetRevision` if using a different branch
- Modify `syncPolicy` for different sync behavior
- Update `project` if using ArgoCD Projects

## Troubleshooting

### Application not syncing
```bash
# Check Application status
kubectl -n argocd get application argocd-example-apps-appset -o yaml

# Check ArgoCD logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller
```

### ApplicationSet not creating apps
```bash
# Check ApplicationSet status
kubectl -n argocd get applicationset argocd-example-apps -o yaml

# Verify the Git generator is finding directories
kubectl -n argocd describe applicationset argocd-example-apps
```

## Next Steps
After the ApplicationSet is bootstrapped:
1. Applications will automatically deploy to their namespaces
2. Kargo can be used to promote changes between environments
3. All configuration is now managed via Git
