# ArgoCD Applications

This directory contains ArgoCD Application manifests that define what workloads should be deployed to your Zero Touch Cluster via GitOps.

## Default Configuration

### Example Workloads (Active by Default)
**File:** `example-workloads.yaml`

By default, your cluster deploys example workloads from the local repository to demonstrate functionality:

- **Hello World App:** Simple web application with cluster status
- **Storage Demos:** Examples showing local-path and NFS storage
- **Monitoring Integration:** Ready for Grafana dashboards

**Source:** `kubernetes/example-workloads/` (local directory in this repository)

## Transitioning to Production GitOps

### Step 1: Create Your Private Repository
Create a private Git repository with your actual workloads:

```
your-private-workloads/
├── applications/
│   ├── production/
│   │   ├── app1/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── ingress.yaml
│   │   └── app2/
│   └── staging/
└── README.md
```

### Step 2: Update ArgoCD Configuration

Option A: **Edit existing application**
```bash
kubectl edit application example-workloads -n argocd
```
Update the `spec.source.repoURL` to point to your private repository.

Option B: **Create new application file**
```bash
cp example-workloads.yaml my-production-workloads.yaml
# Edit the file to point to your repository
kubectl apply -f my-production-workloads.yaml
```

### Step 3: Configure Repository Access

If using a private repository, ensure ArgoCD can access it:

1. **SSH Key Method:**
   ```bash
   kubectl create secret generic private-repo-ssh \
     --from-file=sshPrivateKey=/path/to/ssh/key \
     -n argocd
   ```

2. **Token Method (already configured by setup wizard):**
   The `setup-wizard.sh` automatically creates repository credentials if you provided a Git token.

### Step 4: Verify Deployment
```bash
# Check application status
kubectl get applications -n argocd

# Check application health
argocd app list  # if ArgoCD CLI is installed
```

## Application Structure Best Practices

### Repository Layout
```
applications/
├── base/                    # Common resources
│   ├── namespaces.yaml
│   └── rbac.yaml
├── production/
│   ├── app1/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── app2/
└── staging/
    └── app1/
        ├── kustomization.yaml
        └── patches/
```

### Storage Class Usage
Your cluster provides two storage classes:

- **`local-path`** (default): Fast local storage
  - Single-pod applications
  - Logs, cache, temporary data
  - Monitoring data (Prometheus, Grafana)

- **`nfs-client`**: Shared network storage  
  - Multi-pod applications
  - Shared data between pods
  - Backups and persistent data

Example PVC:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  storageClassName: local-path  # or nfs-client
  accessModes:
    - ReadWriteOnce  # or ReadWriteMany for NFS
  resources:
    requests:
      storage: 10Gi
```

## Multiple Environments

### Production + Staging Setup
```yaml
# production-workloads.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: production-workloads
spec:
  source:
    repoURL: https://github.com/yourname/workloads
    targetRevision: main
    path: applications/production

---
# staging-workloads.yaml  
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: staging-workloads
spec:
  source:
    repoURL: https://github.com/yourname/workloads
    targetRevision: staging
    path: applications/staging
```

## Troubleshooting

### Check Application Status
```bash
kubectl get applications -n argocd
kubectl describe application example-workloads -n argocd
```

### Force Sync
```bash
kubectl patch application example-workloads -n argocd \
  --type='merge' \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Repository Access Issues
```bash
# Check repository credentials
kubectl get secrets -n argocd | grep repo
kubectl describe secret <repo-secret> -n argocd
```

---

**Next Steps:**
1. Verify example workloads are running: `kubectl get pods --all-namespaces`
2. Access hello-world app: `kubectl port-forward -n hello-world svc/hello-world 8081:80`
3. Create your private repository and update ArgoCD when ready