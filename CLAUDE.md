# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zero Touch Cluster is a Kubernetes homelab automation project using k3s and Ansible. The infrastructure consists of:
- 4-node k3s cluster (1 master, 3 workers) on mini PCs
- Dedicated storage node for Kubernetes persistent volumes
- Ansible for infrastructure provisioning and application deployment
- "Bootstrappable USB" provisioning workflow

## Common Commands

### Infrastructure Provisioning
```bash
# MODERN WORKFLOW (Recommended):
# 1. Interactive setup wizard (handles all secrets automatically)
make setup

# 2. Create autoinstall USB drives for each node
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-01 IP_OCTET=11

# 3. Deploy complete infrastructure after nodes boot
make infra

# 4. Create encrypted backup of all secrets
make backup-secrets

# LEGACY WORKFLOW (Manual):
# Generate SSH key if needed (choose Ed25519 for better security)
ssh-keygen -t ed25519 -C "your-email@example.com"
# OR for RSA compatibility: ssh-keygen -t rsa -b 4096

# Setup secrets manually (NOT RECOMMENDED - use 'make setup' instead)
ansible-vault create ansible/inventory/secrets.yml
# Make sure to set the correct SSH key path in secrets.yml:
# ansible_ssh_private_key_file: ~/.ssh/id_ed25519  # or ~/.ssh/id_rsa

# Create autoinstall USB drives for each node (interactive mode)
make autoinstall-usb DEVICE=/dev/sdb

# Or direct mode with parameters
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-01 IP_OCTET=11
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-02 IP_OCTET=12
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-03 IP_OCTET=13
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k8s-storage IP_OCTET=20

# Boot nodes from USB drives (10-15 minutes each, unattended)
# Nodes will automatically install and be ready for Ansible

# Deploy infrastructure after all nodes are booted
make infra
```

### Kubernetes Cluster Verification
```bash
# Verify cluster status
make status

# Verify storage
make deploy-storage

# NFS storage management (optional)
make deploy-nfs     # Deploy NFS provisioner
make enable-nfs     # Enable NFS on storage node
make disable-nfs    # Disable NFS storage

# Test basic functionality
kubectl create deployment test --image=nginx
kubectl get pods
kubectl delete deployment test
```

### USB Provisioning
```bash
# Create autoinstall USB drives (interactive or parameterized)
make autoinstall-usb DEVICE=/dev/sdb
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10

# List available USB devices
make usb-list
```

**Dual-USB Installation Process:**

**One-time setup:**
- Create main Ubuntu installer USB once: `make autoinstall-usb DEVICE=/dev/sdb` (reusable for all nodes)

**Per-node process:**
1. **Streamlined (recommended):** `make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=2`
2. **Alternative (manual):** 
   - Generate ISO: `make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=2`
   - Write to USB: `dd if=provisioning/downloads/k3s-worker-01-cidata.iso of=/dev/sdc bs=4M status=progress`
3. Insert both USB drives into target node:
   - USB #1: Main Ubuntu installer (reusable)
   - USB #2: Node-specific cidata ISO
4. Boot from USB #1 (Ubuntu installer) - use F12/F8/Delete for boot menu
5. Ubuntu automatically detects the cidata ISO and prompts: **"Use autoinstall? (yes/no)"**
6. Type **"yes"** - installation proceeds completely hands-off
7. Wait 10-15 minutes for unattended installation
8. Node reboots automatically when finished

**Efficiency tip:** Keep the main Ubuntu USB, only recreate the small cidata ISO for each node.

### Testing Commands
```bash
# Install prerequisites first (platform-specific)
# macOS: brew install multipass ansible
# Ubuntu/Linux: sudo snap install multipass && sudo apt install ansible

# Validate configuration files
make lint          # Lint Ansible playbooks and YAML files
make validate      # Validate Kubernetes manifests

# Test connectivity to nodes
make ping          # Test Ansible connectivity to all nodes
```

### Node Management
```bash
# Gracefully remove node
kubectl drain <node-name> --ignore-daemonsets
kubectl delete node <node-name>

# Check cluster status
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# Alternative: Use Makefile commands
make restart-node NODE=<node-name>      # Restart specific node
make drain-node NODE=<node-name>        # Drain node for maintenance
make uncordon-node NODE=<node-name>     # Uncordon node after maintenance
```

## Architecture Overview

### Directory Structure
- `ansible/` - Infrastructure automation (roles, playbooks, inventory)
- `kubernetes/` - Kubernetes configuration
  - `system/` - System components deployed via Helm (monitoring, storage, ArgoCD)
  - `argocd-apps/` - ArgoCD Application definitions for GitOps workloads
- `provisioning/` - USB creation scripts and cloud-init configs
- `docs/` - Detailed documentation and guides

### Hybrid GitOps Architecture
- **System Components**: Deployed via Helm charts (monitoring, storage, ArgoCD)
- **Application Workloads**: Deployed via ArgoCD
  - **Default**: Local example workloads (immediate functionality)
  - **Production**: Migrate to private Git repositories when ready
- **Storage Strategy**: 
  - System components use local-path for performance
  - Applications can use nfs-client for shared persistent data

### Immediate Functionality
- **Example Applications**: Hello-world app and storage demos deploy automatically
- **Zero Configuration**: Working cluster with sample apps after `make infra`
- **GitOps Ready**: Transition to private repos when ready for production workloads

### Key Configuration Files
- `ansible/inventory/hosts.ini` - Ansible inventory with node definitions
- `ansible/ansible.cfg` - Ansible configuration with vault settings
- `provisioning/cloud-init/user-data` - Cloud-init template for node bootstrap

## Secrets Management

**SECURE BY DEFAULT**: Zero Touch Cluster implements production-ready secrets management following ADR-001.

### Modern Secure Architecture:
- **Interactive Setup**: `make setup` wizard handles all secrets automatically
- **Encrypted Storage**: All secrets encrypted (Ansible Vault + Sealed Secrets)
- **Automated Backup**: `make backup-secrets` creates encrypted recovery archive
- **Pre-commit Protection**: Automatic prevention of plaintext secret commits
- **No Manual Editing**: Zero exposure to plaintext secrets during setup

### Secret Types & Encryption:
- **Infrastructure secrets**: `ansible/inventory/secrets.yml` (ansible-vault encrypted)
- **Kubernetes secrets**: Sealed Secrets (encrypted manifests safe to commit)
- **Recovery**: Single encrypted backup file contains all crown jewels
- **Pre-commit hooks**: detect-secrets prevents accidental secret exposure

### Key Security Features:
- ✅ **Zero plaintext secrets** on disk outside of memory
- ✅ **Automated secret generation** with strong defaults
- ✅ **Git commit protection** via pre-commit hooks
- ✅ **One-command backup/recovery** for disaster scenarios
- ✅ **Production-ready encryption** using industry standard tools

### Emergency Recovery:
```bash
# Restore from backup after catastrophic failure
make recover-secrets
# Point to your encrypted backup file when prompted
```

**Important**: The setup uses the `ubuntu` user (not `admin`) for consistency with Ubuntu cloud images. The setup wizard handles this automatically.

## Network Configuration

- **Subnet**: 192.168.50.0/24 (update `ansible/inventory/hosts.ini` for your network)
- **Node IPs**: 
  - k3s-master: 192.168.50.10
  - k3s-worker-01: 192.168.50.11
  - k3s-worker-02: 192.168.50.12
  - k3s-worker-03: 192.168.50.13
  - k8s-storage: 192.168.50.20 (dedicated Kubernetes storage)
- **Ingress**: Traefik (bundled with k3s)
- **Storage**: Hybrid approach - local-path (default) + NFS enabled
  - **local-path**: Fast local storage for monitoring, single-pod workloads
  - **nfs-client**: Shared storage for multi-pod applications, persistent data

### Debugging Commands
```bash
# Ansible debugging
ansible all -m ping -vvv
ansible-playbook <playbook> --check --diff

# Kubernetes debugging
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod-name> -n <namespace>
```

## Storage Strategy

### When to Use Each Storage Class

**local-path (default)**
- System monitoring (Prometheus, Grafana, AlertManager)  
- Logs and temporary data
- Single-pod applications requiring fast I/O
- Any workload that doesn't need to be shared across nodes

**nfs-client (enabled by default)**
- Multi-pod applications requiring shared storage
- Databases that need persistent, shared volumes  
- File sharing applications
- Backup storage
- Any data that should survive pod restarts across different nodes

### Storage Commands
```bash
# View available storage classes
kubectl get storageclass

# NFS management (both storage classes enabled by default)
make enable-nfs      # Re-enable NFS storage if disabled 
make disable-nfs     # Disable NFS storage (keeps local-path)

# Storage verification
make deploy-storage  # Verify storage setup
```

## Important Notes

- **Hardware Focus**: This is designed for physical mini PC deployment, not cloud
- **Hybrid GitOps**: System components via Helm, applications via ArgoCD with local examples
- **Infrastructure as Code**: All changes should be managed through Ansible and version controlled  
- **Single Master**: Current setup uses single k3s master (can be upgraded to HA later)
- **Production Security**: ADR-001 compliant secrets management with automated safeguards
- **Immediate Value**: Working cluster with example apps right after deployment

## Development Guidelines

### Commit Message Standards

This project uses **Conventional Commits** for clear, consistent commit history:

```
<type>(<scope>): <subject>

<body>
```

**Types:**
- `fix`: Bug fixes
- `feat`: New features  
- `docs`: Documentation changes
- `refactor`: Code restructuring without functionality changes
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Scopes:**
- `setup`: Setup wizard and initial configuration
- `ansible`: Ansible playbooks, roles, inventory
- `k8s`: Kubernetes manifests and helm charts
- `storage`: Storage configuration and provisioning
- `monitoring`: Prometheus, Grafana, alerting
- `argocd`: GitOps and ArgoCD configuration
- `backup`: Backup and recovery functionality
- `adr`: Architecture Decision Records

**Examples:**
```bash
# Good: Short, descriptive commits
git commit -m "fix(setup): resolve shell syntax error in setup wizard"
git commit -m "feat(monitoring): add Grafana dashboard for storage metrics"
git commit -m "docs(adr): add ADR-002 resilient infrastructure automation"

# Avoid: Verbose commit messages with excessive detail
# Keep commit subject under 50 characters
# Use body for additional context if needed
```

### Code Quality

- **YAML Validation**: 
  - Use `make lint` to validate Ansible playbooks and YAML syntax
  - Use `make validate` to validate Kubernetes manifests
  - Run validation before deploying changes

## ADR References
- Use @docs/adr/adr-template.md for ADR format