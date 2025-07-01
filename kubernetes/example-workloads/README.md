# Zero Touch Cluster - Example Workloads

This directory contains example applications that demonstrate the capabilities of your Zero Touch Cluster deployment. These workloads are automatically deployed when you run `make infra` and serve as both functional examples and verification that your cluster is working correctly.

## Deployed Examples

### 🌐 Hello World Application
**Namespace:** `hello-world`

A simple web application that confirms your cluster is running successfully.

- **Access via Ingress:** 
  - `http://hello.homelab.local` (requires DNS setup)
  - `http://hello.k3s.local` (alternative hostname)
- **Access via Port Forward:** `kubectl port-forward -n hello-world svc/hello-world 8081:80`
- **Features:** Beautiful status page showing deployed components

### 💾 Storage Demonstrations
**Namespace:** `storage-demo`

Two applications that showcase the hybrid storage architecture:

#### Local Path Storage Demo
- **Storage Class:** `local-path` 
- **Use Cases:** Fast local storage for single-pod applications, logs, cache
- **Access Mode:** ReadWriteOnce
- **Example:** Single pod writing to local node storage

#### NFS Shared Storage Demo  
- **Storage Class:** `nfs-client`
- **Use Cases:** Multi-pod applications, shared data, backups
- **Access Mode:** ReadWriteMany
- **Example:** Multiple pods reading/writing to shared storage

## Monitoring Your Examples

### View Pod Status
```bash
# Check all example workloads
kubectl get pods -l example=true --all-namespaces

# Check specific namespace
kubectl get pods -n hello-world
kubectl get pods -n storage-demo
```

### View Storage Usage
```bash
# Check persistent volume claims
kubectl get pvc -n storage-demo

# Check storage classes
kubectl get storageclass
```

### View Logs
```bash
# Hello world application
kubectl logs -n hello-world deployment/hello-world

# Storage demos
kubectl logs -n storage-demo deployment/local-path-writer
kubectl logs -n storage-demo deployment/nfs-writer
kubectl logs -n storage-demo deployment/nfs-reader
```

## Customizing for Production

These example workloads are designed to be replaced with your actual applications once you verify the cluster is working correctly.

### Transitioning to Production GitOps

1. **Create your private Git repository** for workloads
2. **Update ArgoCD configuration:** 
   ```bash
   kubectl edit application private-workloads -n argocd
   # Update spec.source.repoURL to your repository
   ```
3. **Structure your repository** similar to this examples directory
4. **Push your applications** and let ArgoCD sync them automatically

### Repository Structure Recommendation
```
your-private-workloads/
├── applications/
│   ├── production/
│   │   ├── app1/
│   │   └── app2/
│   └── staging/
│       ├── app1/
│       └── app2/
└── README.md
```

## Storage Best Practices

### When to Use Local Path Storage
- ✅ Single-pod applications (databases, caches)
- ✅ Logs and temporary data
- ✅ Applications requiring fast I/O
- ✅ Monitoring data (Prometheus, Grafana)

### When to Use NFS Storage  
- ✅ Multi-pod applications requiring shared access
- ✅ File sharing between pods
- ✅ Backup storage
- ✅ Data that should survive pod restarts across nodes

## Cleanup

To remove all example workloads:
```bash
kubectl delete namespace hello-world storage-demo
```

## Next Steps

1. **Verify monitoring:** Access Grafana at `http://grafana.homelab.local` or via port-forward
2. **Check ArgoCD:** Access ArgoCD UI to see GitOps status  
3. **Deploy your applications:** Replace these examples with your production workloads
4. **Set up DNS:** Configure your router/DNS to resolve `*.homelab.local` to your cluster

---
**Note:** These examples are automatically deployed as part of the Zero Touch Cluster setup to provide immediate functionality and verification that all components are working correctly.