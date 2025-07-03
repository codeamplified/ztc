# Zero Touch Cluster - Complete Teardown Guide

## Overview

This guide provides both automated and manual procedures for completely removing a Zero Touch Cluster deployment. This is primarily intended for **development iteration** where you need to reset the cluster to a clean state.

⚠️ **WARNING: These procedures are DESTRUCTIVE and IRREVERSIBLE**

## Quick Start (Automated)

For development workflow, use the automated teardown:

```bash
make teardown
```

Type `TEARDOWN` when prompted to confirm complete cluster destruction.

## When to Use Teardown

### Development Scenarios:
- ✅ Testing different configuration options
- ✅ Experimenting with new features
- ✅ Recovering from broken cluster state
- ✅ Starting fresh after major changes
- ✅ Debugging deployment issues

### **DO NOT** Use Teardown For:
- ❌ Production clusters with valuable data
- ❌ Clusters with important workloads
- ❌ Minor configuration changes (use `kubectl` instead)
- ❌ Temporary troubleshooting (try `make status` first)

## Automated Teardown (`make teardown`)

### What It Does

The automated teardown performs these steps:

1. **k3s Removal**: Uninstalls k3s from all cluster nodes
2. **Storage Cleanup**: Cleans NFS persistent storage  
3. **Secrets Removal**: Removes all vault passwords and encrypted secrets
4. **File Cleanup**: Removes generated ISOs and backup files
5. **SSH Cleanup**: Cleans SSH host keys for fresh node access
6. **Verification**: Confirms successful teardown

### Safety Features

- **Confirmation Required**: Must type `TEARDOWN` to proceed
- **Clear Warnings**: Shows exactly what will be destroyed
- **Error Handling**: Continues even if some steps fail
- **Status Output**: Shows progress for each step
- **Final Summary**: Confirms what was cleaned up

### Usage

```bash
# Interactive teardown with confirmation
make teardown

# The script will:
# 1. Show warning and list of operations
# 2. Require typing 'TEARDOWN' to confirm
# 3. Execute all teardown steps
# 4. Provide ready-for-setup instructions
```

## Manual Teardown Procedures

For situations where the automated script fails or you need granular control:

### Step 1: Uninstall k3s from Nodes

```bash
# Master node
ssh ubuntu@192.168.50.10 'sudo /usr/local/bin/k3s-uninstall.sh'

# Worker nodes  
ssh ubuntu@192.168.50.11 'sudo /usr/local/bin/k3s-agent-uninstall.sh'
ssh ubuntu@192.168.50.12 'sudo /usr/local/bin/k3s-agent-uninstall.sh'
ssh ubuntu@192.168.50.13 'sudo /usr/local/bin/k3s-agent-uninstall.sh'

# Verify removal
ssh ubuntu@192.168.50.10 'pgrep k3s || echo "k3s removed successfully"'
```

### Step 2: Clean Storage Node

```bash
# Clean NFS storage
ssh ubuntu@192.168.50.20 'sudo systemctl stop nfs-kernel-server'
ssh ubuntu@192.168.50.20 'sudo rm -rf /export/k8s/*'
ssh ubuntu@192.168.50.20 'sudo systemctl start nfs-kernel-server'

# Verify cleanup
ssh ubuntu@192.168.50.20 'ls -la /export/k8s/'
```

### Step 3: Remove Local Secrets and Configuration

```bash
# Remove all secrets and generated files
rm -f ansible/inventory/secrets.yml
rm -f .ansible-vault-password  
rm -f ansible/.vault_pass
rm -f ztc-secrets-backup-*.tar.gz.gpg
rm -f provisioning/downloads/*.iso

# Verify cleanup
ls -la ansible/inventory/secrets.yml* 2>/dev/null || echo "Secrets cleaned"
```

### Step 4: Clean SSH Host Keys

```bash
# Remove SSH host keys for all nodes
ssh-keygen -R 192.168.50.10  # k3s-master
ssh-keygen -R 192.168.50.11  # k3s-worker-01  
ssh-keygen -R 192.168.50.12  # k3s-worker-02
ssh-keygen -R 192.168.50.13  # k3s-worker-03
ssh-keygen -R 192.168.50.20  # k8s-storage
```

### Step 5: Verify Complete Removal

```bash
# Test node connectivity (should work)
ssh -o StrictHostKeyChecking=no ubuntu@192.168.50.10 'echo "Node accessible"'

# Verify no k3s processes
ssh ubuntu@192.168.50.10 'pgrep k3s || echo "No k3s processes"'

# Verify kubectl cannot connect
kubectl cluster-info  # Should fail with connection error

# Verify clean local state
ls -la ansible/inventory/secrets.yml* 2>/dev/null | wc -l  # Should be 1 (template only)
```

## Troubleshooting Teardown Issues

### Node Connection Issues

**Problem**: SSH connections fail during teardown
**Solution**: 
```bash
# Verify node IPs and connectivity
make ping

# Clean SSH keys manually
ssh-keygen -R <node-ip>

# Use direct IPs instead of hostnames
ssh -o StrictHostKeyChecking=no ubuntu@192.168.50.10 'command'
```

### k3s Uninstall Failures

**Problem**: k3s uninstall script not found
**Solution**:
```bash
# Check if k3s is actually installed
ssh ubuntu@192.168.50.10 'ls -la /usr/local/bin/k3s*'

# Manual k3s process cleanup
ssh ubuntu@192.168.50.10 'sudo pkill -f k3s; sudo rm -rf /var/lib/rancher/k3s'
```

### Storage Cleanup Issues

**Problem**: NFS service errors during cleanup
**Solution**:
```bash
# Force stop and clean
ssh ubuntu@192.168.50.20 'sudo systemctl stop nfs-kernel-server; sudo pkill -f nfs'
ssh ubuntu@192.168.50.20 'sudo rm -rf /export/k8s/*'
ssh ubuntu@192.168.50.20 'sudo systemctl start nfs-kernel-server'
```

### Ansible Vault Errors

**Problem**: Ansible commands fail due to missing vault file
**Solution**:
```bash
# Skip Ansible and use direct SSH
# The vault file removal is intentional during teardown
# Use direct SSH commands as shown in manual procedures
```

## After Teardown - Fresh Setup

Once teardown is complete, start fresh with:

```bash
# 1. Setup new secrets and configuration
make setup

# 2. Create USB drives for nodes (if needed)
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10

# 3. Boot nodes from USB (15 min each, unattended)

# 4. Deploy infrastructure  
make infra

# 5. Verify deployment
make status
```

## Emergency Recovery

If teardown fails partially and you're in a broken state:

### Nuclear Option - Manual Node Reset

⚠️ **Use only when all else fails**

```bash
# Connect to each node and reset manually
for ip in 192.168.50.10 192.168.50.11 192.168.50.12 192.168.50.13 192.168.50.20; do
    echo "Resetting node $ip"
    ssh -o StrictHostKeyChecking=no ubuntu@$ip '
        sudo pkill -f k3s 2>/dev/null || true
        sudo rm -rf /var/lib/rancher/k3s 2>/dev/null || true
        sudo rm -rf /etc/rancher/k3s 2>/dev/null || true
        sudo rm -f /usr/local/bin/k3s* 2>/dev/null || true
        sudo systemctl stop nfs-kernel-server 2>/dev/null || true
        sudo rm -rf /export/k8s/* 2>/dev/null || true
        sudo systemctl start nfs-kernel-server 2>/dev/null || true
        echo "Node $ip reset complete"
    '
done
```

### Clean Control Machine State

```bash
# Nuclear local cleanup
rm -rf ~/.kube/config
rm -f .ansible-vault-password ansible/.vault_pass
rm -f ansible/inventory/secrets.yml
rm -f ztc-secrets-backup-*.tar.gz.gpg
rm -f provisioning/downloads/*.iso
kubectl config delete-context ztc-cluster 2>/dev/null || true

# Reset SSH known hosts for ZTC nodes
cp ~/.ssh/known_hosts ~/.ssh/known_hosts.backup
grep -v "192.168.50." ~/.ssh/known_hosts > ~/.ssh/known_hosts.tmp
mv ~/.ssh/known_hosts.tmp ~/.ssh/known_hosts
```

## Integration with Development Workflow

### Typical Development Cycle

```bash
# 1. Develop/test changes
git checkout feature-branch

# 2. Deploy and test
make setup
make infra
make deploy-n8n  # test workloads

# 3. Found issues - reset completely  
make teardown

# 4. Try again with fixes
git commit -am "fix: resolve deployment issue"
make setup
make infra

# 5. Success - merge
git checkout main && git merge feature-branch
```

### Integration with CI/CD

The teardown command enables:
- Automated testing of full deployment cycles
- Clean environment for each test run
- Verification of setup procedures
- Testing teardown procedures themselves

```bash
# Example CI script
#!/bin/bash
set -e

# Deploy cluster
make setup
make infra

# Run tests
make validate
kubectl get pods --all-namespaces

# Always cleanup (even on failure)
trap 'make teardown || true' EXIT
```

## Security Considerations

### Secrets Handling During Teardown

- ✅ **Vault passwords**: Removed completely from disk
- ✅ **Encrypted secrets**: Removed (encrypted files safe to remove)
- ✅ **SSH keys**: Host keys removed, private keys preserved
- ✅ **Generated passwords**: Removed (can be regenerated)

### What is NOT Removed

- ❌ **SSH private/public keys**: `~/.ssh/id_*` (your personal keys)
- ❌ **Project source code**: Git repository remains intact
- ❌ **Ansible templates**: Template files preserved for reuse
- ❌ **Documentation**: All docs remain available

## Conclusion

The ZTC teardown capability provides a robust solution for development iteration and clean environment creation. The automated `make teardown` is the recommended approach for most use cases, with manual procedures available for troubleshooting and granular control.

Remember: **Teardown is destructive by design** - use it when you want a completely fresh start, not for minor configuration changes.