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

# Kubernetes applications (if deploying apps)
kubernetes/apps/*/values.yaml
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
# kubernetes/apps/*/values-secret.yaml       # From values-secret.yaml.template
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
# In kubernetes/apps/*/ingress.yaml:
# Change any hardcoded domains to your preferences
# Example: grafana.homelab.local → grafana.yourname.local
```

### Storage Configuration
**Reference Setup**: NFS server with 1TB+ available space (NFS enabled by default)
**Your Setup**: Adjust storage configuration based on your needs

```bash
# Storage configuration in ansible/inventory/group_vars/all.yml:
nfs_enabled: true     # Set to false to disable NFS
nfs_export_path: "/export/k8s"
storage_type: "hybrid"  # Supports both local-path and NFS

# In kubernetes/apps/*/values.yaml:
# Modify storage requests:
# persistence.size: 100Gi → 50Gi (for smaller setups)
```

## 🚀 Deployment Customization

### Quick Start Commands
```bash
# Initial setup (creates secret templates)
make setup

# Deploy infrastructure after configuring secrets
make infra

# Verify deployment
make status
```

### Selective Deployment
You can deploy components individually:

```bash
# Deploy only storage server
make storage

# Deploy only k3s cluster
make cluster

# NFS storage management
make enable-nfs      # Enable NFS storage
make disable-nfs     # Disable NFS storage
make deploy-nfs      # Deploy NFS provisioner to cluster
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

Before deploying, verify:
- [ ] All IP addresses updated in inventory
- [ ] SSH key path correct in secrets.yml
- [ ] Hostnames updated consistently across files
- [ ] Network subnet matches your router configuration
- [ ] Storage sizing appropriate for your hardware
- [ ] DNS/domain names updated if using custom domains
- [ ] Resource limits adjusted for your hardware specs
- [ ] Run validation commands:
  ```bash
  make lint      # Validate YAML syntax and Ansible playbooks
  make validate  # Validate Kubernetes manifests
  make ping      # Test connectivity to nodes
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

## 💡 Pro Tips

1. **Start Small**: Deploy just the basic cluster first, add applications gradually
2. **Use Makefile**: Leverage `make setup`, `make infra`, `make status` for streamlined deployment
3. **Validate Early**: Run `make lint` and `make validate` before deploying changes
4. **Keep Notes**: Document your changes for future reference
5. **Backup Configs**: Keep your customized configs in a private fork
6. **Test Connectivity**: Use `make ping` to verify node connectivity before deployment
7. **Monitor Resources**: Check cluster health with `make status`

---

Remember: This is a reference configuration shared as a starting point. Don't hesitate to adapt it significantly for your needs - that's the whole point of open source!