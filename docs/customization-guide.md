# Customization Guide

This guide helps you adapt this homelab configuration for your specific environment. Since this is a reference implementation, you'll need to modify several files to match your network and preferences.

## 🔧 Essential Customizations

### 1. Network Configuration

**Reference Setup**: 192.168.50.0/24 subnet with managed router
**Your Setup**: Update for your network range

#### Files to Modify:
```bash
# Primary inventory file
ansible/inventory/hosts.ini
# Change all 192.168.50.x addresses to your subnet
# Example: 192.168.50.10 → 192.168.1.10

# Global configuration
ansible/inventory/group_vars/all.yml
# Update network settings, NFS configuration, and other global vars

# Cloud-init configuration template
provisioning/cloud-init/user-data.template
# Update network configuration section if using static IPs

# System components configuration  
kubernetes/system/*/values.yaml
# Update any hardcoded domain names or resource limits
```

### 2. SSH Key Configuration

**Reference Setup**: Ed25519 key at `~/.ssh/id_ed25519`
**Your Setup**: Point to your actual SSH key

```bash
# In ansible/inventory/secrets.yml (create from template):
ansible_user: ubuntu  # Keep this for Ubuntu compatibility
ansible_ssh_private_key_file: ~/.ssh/your_key_name
```

### 3. Hostname Preferences

**Reference Setup**: k3s-master, k3s-worker-01/02/03, k8s-storage
**Your Setup**: Choose names that make sense for you

```bash
# In ansible/inventory/hosts.ini:
# Change hostnames in both the inventory names and ansible_host values
# Example:
# k3s-master → my-k8s-master
# k3s-worker-01 → my-worker-1
```

## 🏠 Hardware Adaptations

### Mini PC Specifications
**Reference Hardware**: 16GB RAM, 4 cores, 256GB storage per node
**Minimum Requirements**: 8GB RAM, 2 cores, 128GB storage

#### Performance Considerations:
- **8GB RAM**: Reduce resource requests in Kubernetes manifests
- **2 cores**: Limit concurrent workloads, may need longer deployment times
- **128GB storage**: Monitor disk usage, consider external storage for persistent volumes

### Network Hardware
**Reference Setup**: Managed router with DHCP controller and managed switches
**Alternatives**: 
- Any router with DHCP (just update IP ranges accordingly)
- Static IP assignment vs. DHCP reservations
- Different subnet ranges as needed

## 🌐 Network-Specific Changes

### Router/DHCP Configuration
```bash
# Common subnet alternatives to the reference (192.168.50.0/24):
192.168.1.0/24   → Change .50. to .1. in all configs
192.168.0.0/24   → Change .50. to .0. in all configs  
10.0.0.0/24      → Change 192.168.50. to 10.0.0. in all configs
```

### DNS Considerations
- **Reference Setup**: Managed router provides local DNS
- **Your Setup**: Ensure your router/DNS can resolve the hostnames you choose
- **Alternative**: Use IP addresses directly instead of hostnames

## 🔐 Secrets Management

### Initial Setup
```bash
# Use the setup command to create secret templates
make setup

# This creates:
# ansible/inventory/secrets.yml              # From secrets.yml.template
# kubernetes/system/*/values-secret.yaml       # From values-secret.yaml.template
```

### Required Secret Files
```bash
# Edit the created secrets file:
ansible/inventory/secrets.yml
# Set your SSH key path and other sensitive data
```

### Ansible Vault Setup
```bash
# Create vault password file (optional, for convenience):
echo "your_vault_password" > ~/.ansible_vault_pass
chmod 600 ~/.ansible_vault_pass

# Add to ~/.bashrc:
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible_vault_pass
```

## 🎯 Application Customization

### Domain Names and TLS
**Reference Setup**: Local domain names with self-signed certs
**Your Setup**: Update domain names in ingress configurations

```bash
# In kubernetes/system/*/values.yaml:
# Change any hardcoded domains to your preferences
# Example: grafana.homelab.local → grafana.yourname.local
```

### Storage Configuration
**Reference Setup**: Hybrid storage with both local-path and NFS enabled by default
**Your Setup**: Both storage classes available out-of-the-box, adjust sizes as needed

```bash
# Storage configuration in ansible/inventory/group_vars/all.yml:
nfs_enabled: true     # Already enabled by default
nfs_export_path: "/export/k8s"
storage_type: "hybrid"  # Both local-path and NFS available

# In kubernetes/system/*/values.yaml:
# Modify storage requests if needed:
# persistence.size: 100Gi → 50Gi (for smaller setups)
```

## 🔄 GitOps Architecture

Zero Touch Cluster uses a **Hybrid GitOps approach** that separates system infrastructure from application workloads:

### **System Components (Helm Charts)**
Core infrastructure deployed directly via Helm:
- **ztc-monitoring**: Prometheus, Grafana, AlertManager
- **ztc-storage**: Hybrid storage with local-path + NFS
- **ArgoCD**: GitOps platform itself

```bash
# Deploy system components
make system-components    # All system components
make monitoring-stack     # Just monitoring
make storage-stack        # Just storage
make argocd              # Just ArgoCD
```

### **Application Workloads (ArgoCD)**
Applications deployed via GitOps from private repositories:
- **Private workloads**: Business applications, databases
- **Shared workloads**: Open source tools, utilities
- **Environment-specific**: staging, production configs

```bash
# Configure private repository access
cp kubernetes/system/argocd/config/repository-credentials.yaml.template \
   kubernetes/system/argocd/config/repository-credentials.yaml
# Edit with your GitHub/GitLab credentials

# Deploy ArgoCD applications
make argocd-apps
```

### **When to Use Each Approach**

**Use Helm for:**
- ✅ System infrastructure (monitoring, storage, ingress)
- ✅ Foundational components needed for cluster operation
- ✅ Components that don't change frequently
- ✅ Vendor charts with complex dependencies

**Use ArgoCD for:**
- ✅ Application workloads and business logic
- ✅ Environment-specific deployments
- ✅ Applications that change frequently
- ✅ Multi-environment (dev/staging/prod) workflows

### **ArgoCD Configuration**

#### **Repository Credentials Setup**
```bash
# 1. Copy template
cp kubernetes/system/argocd/config/repository-credentials.yaml.template \
   kubernetes/system/argocd/config/repository-credentials.yaml

# 2. Edit with your credentials
# For GitHub (recommended):
#   url: "https://github.com/yourusername/private-workloads"
#   username: "yourusername"  
#   password: "ghp_your_personal_access_token"

# 3. Apply credentials
kubectl apply -f kubernetes/system/argocd/config/repository-credentials.yaml
```

#### **Private Repository Structure**
Create a separate repository for your workloads:
```
private-workloads/
├── applications/           # ArgoCD will monitor this path
│   ├── database/
│   │   ├── postgres.yaml
│   │   └── values.yaml
│   ├── web-app/
│   └── monitoring-extras/
└── environments/          # Optional: environment-specific configs
    ├── staging/
    └── production/
```

#### **Storage Classes for Workloads**
Your ArgoCD-deployed applications can use both storage classes:

```yaml
# In your private workloads - use local-path for single-pod apps
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  storageClassName: "local-path"  # Fast local storage
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 10Gi

---
# Use nfs-client for shared/multi-pod apps  
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
spec:
  storageClassName: "nfs-client"  # Shared NFS storage
  accessModes: ["ReadWriteMany"]
  resources:
    requests:
      storage: 50Gi
```

## 🚀 Deployment Customization

### **Quick Start Commands**
```bash
# 1. Initial setup (creates secret templates)
make setup

# 2. Deploy infrastructure + system components + ArgoCD
make infra

# 3. Configure private repository credentials (see ArgoCD section above)
# 4. Deploy your applications via ArgoCD
make argocd-apps

# 5. Verify deployment
make status
make gitops-status   # Check ArgoCD application status
```

### **System Components Deployment**
Deploy infrastructure components individually:

```bash
# Infrastructure (Ansible-managed)
make storage         # NFS storage server setup
make cluster         # k3s cluster deployment

# System components (Helm-managed)
make system-components    # Deploy all system Helm charts
make monitoring-stack     # ztc-monitoring only
make storage-stack        # ztc-storage only
make argocd              # ArgoCD platform only
```

### **GitOps Workflow**
Once system components are deployed:

```bash
# Check GitOps status
make gitops-status       # View ArgoCD applications
make gitops-sync         # Force sync all applications

# ArgoCD management
kubectl get applications -n argocd
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Access UI: http://localhost:8080
```

### Resource Limits
For lower-spec hardware, reduce resource requests:

```bash
# In Helm values files:
resources:
  requests:
    memory: "256Mi"    # Reduce from higher values
    cpu: "100m"        # Reduce from higher values
  limits:
    memory: "512Mi"    # Adjust accordingly
    cpu: "500m"
```

## 🔍 Validation Checklist

### **Infrastructure Preparation**
- [ ] All IP addresses updated in inventory
- [ ] SSH key path correct in secrets.yml
- [ ] Hostnames updated consistently across files
- [ ] Network subnet matches your router configuration
- [ ] Storage sizing appropriate for your hardware
- [ ] DNS/domain names updated if using custom domains
- [ ] Resource limits adjusted for your hardware specs

### **GitOps Configuration**
- [ ] Private repository created for workloads
- [ ] Repository credentials configured in ArgoCD
- [ ] `private-workloads.yaml` updated with correct repo URL
- [ ] Storage class strategy defined for applications
- [ ] Application manifests follow ArgoCD patterns

### **Validation Commands**
```bash
# Pre-deployment validation
make lint         # Validate YAML syntax and Ansible playbooks
make validate     # Validate Kubernetes manifests
make ping         # Test connectivity to nodes

# Post-deployment verification
make status       # Check cluster status
make gitops-status # Check ArgoCD applications
kubectl get storageclass  # Verify storage classes
```

## 🆘 Common Customization Issues

### "Connection refused" errors
- Verify IP addresses match your actual network
- Check SSH key path and permissions
- Ensure nodes are powered on and accessible
- Test connectivity: `make ping`
- Debug with: `ansible all -m ping -vvv`

### "Insufficient resources" errors
- Reduce memory/CPU requests in Kubernetes manifests
- Consider removing some applications for lower-spec hardware
- Check cluster status: `make status`
- Disable NFS if not needed: `make disable-nfs`

### DNS resolution issues  
- Use IP addresses instead of hostnames if DNS isn't working
- Check your router's DNS settings
- Ensure static DHCP reservations are configured
- Verify network configuration in `ansible/inventory/group_vars/all.yml`

### ArgoCD/GitOps issues
- **Repository access denied**: Check credentials in `repository-credentials.yaml`
- **Applications not syncing**: Verify repository URL and path in ArgoCD Application
- **Storage class not found**: Ensure `make storage-stack` completed successfully
- **ArgoCD UI not accessible**: Check ArgoCD pods: `kubectl get pods -n argocd`
- **Applications stuck pending**: Check storage classes: `kubectl get storageclass`

### Storage issues
- **PVCs stuck pending**: Check storage provisioner pods
- **NFS mount failures**: Verify NFS server status on storage node
- **Local-path issues**: Check local-path provisioner: `kubectl get pods -n kube-system`
- **Wrong storage class**: Update PVC to use `local-path` or `nfs-client`

## 💡 Pro Tips

### **Deployment Strategy**
1. **Start Small**: Deploy just the basic cluster first, add applications gradually
2. **System First**: Get system components (monitoring, storage, ArgoCD) stable before applications
3. **Use Makefile**: Leverage `make setup`, `make infra`, `make status` for streamlined deployment
4. **Validate Early**: Run `make lint` and `make validate` before deploying changes

### **GitOps Best Practices**
5. **Separate Repositories**: Keep system configs (this repo) separate from workload configs (private repo)
6. **Test Storage Classes**: Verify both `local-path` and `nfs-client` work before deploying applications
7. **Monitor ArgoCD**: Use `make gitops-status` and ArgoCD UI to track application deployments
8. **Credential Security**: Never commit repository credentials to Git

### **Maintenance**
9. **Keep Notes**: Document your changes for future reference
10. **Backup Configs**: Keep your customized configs in a private fork
11. **Test Connectivity**: Use `make ping` to verify node connectivity before deployment
12. **Monitor Resources**: Check cluster health with `make status`

---

Remember: This is a reference configuration shared as a starting point. Don't hesitate to adapt it significantly for your needs - that's the whole point of open source!