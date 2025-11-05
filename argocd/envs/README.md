# ApplicationSet envs

## Overview
Environment-specific envs for the ApplicationSet. Each overlay configures the ApplicationSet to discover and manage only applications for its specific environment.

## Structure

```
envs/
├── dev/
│   └── kustomization.yaml     # Filters for _apps/*/envs/dev
├── staging/
│   └── kustomization.yaml     # Filters for _apps/*/envs/staging
└── prod/
    └── kustomization.yaml     # Filters for _apps/*/envs/prod
```

## How It Works

Each overlay:
1. **Includes the base** ApplicationSet from `../base/`
2. **Patches the directory filter** to match only its environment
   - Dev: `_apps/*/envs/dev`
   - Staging: `_apps/*/envs/staging`
   - Prod: `_apps/*/envs/prod`
3. **Adds environment labels** for resource identification

## Application Naming

With this multi-cluster setup:
- **Application name**: Just the app name (e.g., `nginx`)
- **Namespace**: Just the app name (e.g., `nginx`)
- **No environment suffix** needed since each cluster only runs one environment

Example for nginx in dev cluster:
- Application name: `nginx`
- Namespace: `nginx`
- Source path: `_apps/nginx/envs/dev/`
- Kargo branch: `kargo/nginx/dev`

## Testing envs Locally

You can test what each overlay produces:

```bash
# Dev overlay
kubectl kustomize envs/dev

# Staging overlay
kubectl kustomize envs/staging

# Prod overlay
kubectl kustomize envs/prod
```

## Deployment

These envs are deployed via the bootstrap Applications in `/argocd/bootstrap/03-appset-bootstrap/`:
- `dev-appset.yaml` → deploys dev overlay to dev cluster
- `staging-appset.yaml` → deploys staging overlay to staging cluster
- `prod-appset.yaml` → deploys prod overlay to prod cluster

## Adding a New Application

To add a new application that will be discovered by the ApplicationSet:

1. Create the directory structure:
   ```
   _apps/
   └── myapp/
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

2. The ApplicationSet will automatically discover and create Applications in each cluster:
   - Dev cluster: `myapp` application pointing to `_apps/myapp/envs/dev/`
   - Staging cluster: `myapp` application pointing to `_apps/myapp/envs/staging/`
   - Prod cluster: `myapp` application pointing to `_apps/myapp/envs/prod/`

3. Set up Kargo resources (if using Kargo for promotions):
   - Create warehouse in `kargo/project/warehouses/myapp.yaml`
   - Create stages in `kargo/project/stages/myapp-{dev,staging,prod}.yaml`

## Customization

To customize behavior per environment, you can add additional patches to each overlay's `kustomization.yaml`:

```yaml
patches:
  # Example: Change destination cluster
  - patch: |-
      - op: replace
        path: /spec/template/spec/destination/server
        value: https://my-cluster.example.com
    target:
      kind: ApplicationSet
      name: argocd-example-apps
```

## Troubleshooting

### Applications not appearing
```bash
# Check ApplicationSet status
kubectl -n argocd get applicationset argocd-example-apps -o yaml

# Check if directories are being discovered
kubectl -n argocd describe applicationset argocd-example-apps
```

### Wrong directories being discovered
- Verify the path filter in the overlay's kustomization.yaml
- Ensure directory structure matches `_apps/*/envs/{env}/`
