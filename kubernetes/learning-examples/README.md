# Zero Touch Cluster - Learning Examples

This directory contains **educational examples** for learning Kubernetes concepts and testing cluster functionality. These are **not production applications** - for that, use the [workload templates](../workloads/templates/) instead.

## Purpose: Learning vs Production

| **Learning Examples (here)** | **Workload Templates** |
|-------------------------------|------------------------|
| 🎓 Learn Kubernetes concepts | 🚀 Deploy production apps |
| 🧪 Test cluster functionality | ⚡ One-command deployment |
| 🔧 Troubleshoot issues | 🏆 Real homelab services |
| 📚 Reference for custom apps | 🛠️ Automated GitOps workflow |

## Quick Start

**For Learning:** Use these examples to understand Kubernetes
```bash
# Already deployed via ArgoCD: learning-examples application
kubectl get pods --all-namespaces | grep -E "(hello-world|storage-demo)"
```

**For Production:** Use workload templates for real applications  
```bash
make deploy-n8n            # Workflow automation
make deploy-uptime-kuma    # Service monitoring  
make deploy-homepage       # Service dashboard
```

## Learning Examples

### 🌐 Hello World Application
**Namespace:** `hello-world`

**Learning Objectives:**
- Basic Kubernetes deployment patterns
- Service → Ingress → external access flow
- ConfigMap usage for application configuration
- Pod networking and DNS resolution

**Access:**
- **Ingress:** `http://hello.homelab.local` (requires DNS setup)
- **Port Forward:** `kubectl port-forward -n hello-world svc/hello-world 8081:80`

**What it teaches:**
```yaml
# Basic pattern: Deployment → Service → Ingress
Deployment → Service → Ingress → External Access
```

### 💾 Storage Demonstrations  
**Namespace:** `storage-demo`

**Learning Objectives:**
- Understand ZTC's hybrid storage strategy
- Compare local-path vs nfs-client storage classes
- Learn PersistentVolumeClaim patterns
- See how storage affects pod scheduling

#### Local Path Storage Demo
```yaml
storageClassName: local-path
accessModes: [ReadWriteOnce]
```
- **Use Case:** Fast local storage for single-pod apps
- **Example:** Database data, logs, cache
- **Scheduling:** Pod tied to specific node

#### NFS Shared Storage Demo
```yaml  
storageClassName: nfs-client
accessModes: [ReadWriteMany]
```
- **Use Case:** Shared storage for multi-pod apps
- **Example:** File sharing, backups, shared config
- **Scheduling:** Pod can run on any node

## Learning Commands

### Basic Kubernetes Operations
```bash
# List all learning example resources
kubectl get all -n hello-world
kubectl get all -n storage-demo

# Inspect specific resources
kubectl describe deployment hello-world -n hello-world
kubectl describe pvc -n storage-demo

# View configurations
kubectl get configmap -n hello-world -o yaml
```

### Storage Analysis
```bash
# Compare storage classes
kubectl get storageclass

# See storage usage
kubectl get pvc --all-namespaces
kubectl get pv

# Check node affinity for local-path
kubectl get pods -n storage-demo -o wide
```

### Troubleshooting Practice
```bash
# View pod events  
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs -n hello-world deployment/hello-world
kubectl logs -n storage-demo -l app=local-path-demo

# Test connectivity
kubectl exec -n hello-world deployment/hello-world -- curl localhost
```

## Understanding GitOps with ArgoCD

These examples are deployed via the `learning-examples` ArgoCD Application:

```bash
# View ArgoCD application
kubectl get application learning-examples -n argocd

# Check sync status
kubectl describe application learning-examples -n argocd

# Force sync (if needed)
kubectl patch application learning-examples -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**Learning Objective:** Understand how GitOps automatically deploys and manages applications.

## From Examples to Production

Once you understand these concepts, graduate to production workloads:

### 1. For Quick Production Apps
```bash
# Use workload templates (automated GitOps)
make deploy-n8n STORAGE_SIZE=10Gi
make deploy-uptime-kuma
```

### 2. For Custom Applications
Use these examples as patterns for your own Kubernetes manifests:

```yaml
# Pattern: deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    # ... follow hello-world pattern
```

### 3. Storage Decision Guide
- **Need fast, local storage?** → Use `local-path` (like storage-demo/local-path)
- **Need shared storage?** → Use `nfs-client` (like storage-demo/nfs)  
- **Unsure?** → Start with `local-path`, migrate if needed

## Cleanup

Remove learning examples when ready for production:
```bash
kubectl delete application learning-examples -n argocd
kubectl delete namespace hello-world storage-demo
```

## Next Learning Steps

1. **Explore Workload Templates:** See production-ready applications
2. **Study Template Structure:** Learn advanced Kubernetes patterns  
3. **Customize Templates:** Override settings for your environment
4. **Create Custom Workloads:** Use examples as reference for your apps

---

**Remember:** These are learning tools, not production applications. For real homelab services, use `make deploy-<service>` commands with workload templates.