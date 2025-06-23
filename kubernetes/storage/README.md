# Storage Configuration

This directory contains Kubernetes storage configurations for the homelab.

## 📦 Storage Options

### **Local-Path (Default)**
- **Always available**: Built into k3s, no additional setup required
- **Storage class**: `local-path` (default)
- **Use cases**: Single-node workloads, fast I/O, stateful apps that don't need sharing
- **Location**: Local storage on each worker node

### **NFS (Optional)**
- **Requires setup**: Enable with `nfs_enabled: true` in Ansible configuration
- **Storage class**: `nfs-client`
- **Use cases**: Shared storage, multi-pod applications, ReadWriteMany volumes
- **Location**: Centralized NFS server on storage node (192.168.50.20:/export/k8s)

## 🚀 Quick Start

### **1. Check Available Storage Classes**
```bash
kubectl get storageclass
```

### **2. Deploy NFS Provisioner (if NFS enabled)**
```bash
# Only run this if you've enabled NFS in Ansible
kubectl apply -f kubernetes/storage/nfs-provisioner.yaml
```

### **3. Test Storage with Example PVCs**
```bash
# Local-path example
kubectl apply -f kubernetes/storage/examples/local-path-pvc.yaml

# NFS example (if available)
kubectl apply -f kubernetes/storage/examples/nfs-pvc.yaml
```

## 📋 Storage Class Comparison

| Feature | Local-Path | NFS |
|---------|------------|-----|
| **Performance** | ⚡ Fastest (local disk) | 🌐 Network dependent |
| **Sharing** | ❌ Single node only | ✅ Multi-node sharing |
| **Access Modes** | RWO only | RWO, ROX, RWX |
| **Setup Complexity** | ✅ Built-in | 🔧 Requires NFS server |
| **Data Persistence** | 🏠 Node-local | 🌍 Centralized |
| **Backup Strategy** | Per-node backup | Single-point backup |

## 🎯 When to Use Each

### **Use Local-Path for:**
- Single-replica databases (PostgreSQL, MySQL)
- Node-local caching (Redis, Memcached)
- Build artifacts and temporary storage
- High-performance I/O workloads

### **Use NFS for:**
- Shared configuration files
- Multi-pod applications needing shared data
- Media/asset storage accessed by multiple pods
- Applications requiring ReadWriteMany volumes

## 🔧 Configuration

### **Enable NFS Storage**
1. **Update Ansible configuration**:
   ```yaml
   # In ansible/inventory/group_vars/all.yml
   nfs_enabled: true
   ```

2. **Re-run storage setup**:
   ```bash
   ansible-playbook ansible/playbooks/01-k8s-storage-setup.yml
   ```

3. **Deploy NFS provisioner**:
   ```bash
   kubectl apply -f kubernetes/storage/nfs-provisioner.yaml
   ```

### **Verify NFS Setup**
```bash
# Check NFS server is running
ssh ubuntu@192.168.50.20 "sudo systemctl status nfs-server"

# Test NFS mount from any worker node
ssh ubuntu@192.168.50.11 "sudo mount -t nfs 192.168.50.20:/export/k8s /mnt"
```

## 📁 Files

- `nfs-provisioner.yaml` - NFS Subdir External Provisioner deployment
- `examples/` - Example PVC manifests for testing
- `README.md` - This documentation

## 🐛 Troubleshooting

### **NFS Issues**
```bash
# Check NFS server status
ssh ubuntu@192.168.50.20 "sudo systemctl status nfs-server"

# Check exports
ssh ubuntu@192.168.50.20 "sudo exportfs -v"

# Test connectivity from worker
ssh ubuntu@192.168.50.11 "showmount -e 192.168.50.20"
```

### **Storage Class Issues**
```bash
# List storage classes
kubectl get storageclass

# Check provisioner pods
kubectl get pods -n nfs-provisioner

# Check provisioner logs
kubectl logs -n nfs-provisioner deployment/nfs-client-provisioner
```

### **PVC Issues**
```bash
# Check PVC status
kubectl get pvc

# Check PV details
kubectl get pv

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```