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
# STREAMLINED WORKFLOW (Recommended):
# 1. Pre-cluster setup (creates infrastructure secrets only)
make setup

# 2. Create autoinstall USB drives for each node
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-01 IP_OCTET=11

# 3. Deploy complete infrastructure (cluster + sealed secrets + applications)
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

### Development Workflow

```bash
# Complete cluster teardown for development iteration
make teardown      # ⚠️  DESTRUCTIVE: Removes everything for fresh start

# Development cycle
make teardown      # Clean slate
make setup         # New secrets and configuration  
make infra         # Deploy fresh cluster
make status        # Verify deployment
```

**When to use teardown:**
- Testing configuration changes
- Recovering from broken cluster state  
- Starting fresh after experiments
- Development iteration

**⚠️ Never use on production clusters with valuable data**

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
- **Git Protection**: Careful handling to prevent accidental secret commits
- **No Manual Editing**: Zero exposure to plaintext secrets during setup

### Secret Types & Encryption:
- **Infrastructure secrets**: `ansible/inventory/secrets.yml` (ansible-vault encrypted)
- **Kubernetes secrets**: Sealed Secrets (encrypted manifests safe to commit)
- **Recovery**: Single encrypted backup file contains all crown jewels
- **Git safeguards**: Careful workflows to prevent accidental secret exposure

### Key Security Features:
- ✅ **Zero plaintext secrets** on disk outside of memory
- ✅ **Automated secret generation** with strong defaults
- ✅ **Git workflow protection** via careful secret handling
- ✅ **One-command backup/recovery** for disaster scenarios
- ✅ **Production-ready encryption** using industry standard tools

### Emergency Recovery:
```bash
# Restore from backup after catastrophic failure
make recover-secrets
# Point to your encrypted backup file when prompted
```

**Important**: The setup uses the `ubuntu` user (not `admin`) for consistency with Ubuntu cloud images. The setup wizard handles this automatically.

## Private Git Server (Gitea)

**SELF-HOSTED GITOPS**: Zero Touch Cluster includes Gitea for private workload hosting, implementing ADR-003.

### Why Internal Git Server?
- **Privacy**: Keep your proprietary code within the cluster boundary
- **Resilience**: No dependency on external Git services (GitHub.com, etc.)
- **Simplicity**: Unified platform for both infrastructure and application development
- **Air-Gap Ready**: Complete GitOps workflow without internet dependency

### Gitea Management Commands:
```bash
# Deploy Gitea Git server
make gitea-stack

# Get admin credentials
make gitea-admin-password
# Output: Username: ztc-admin, Password: <generated-secure-password>

# Access Gitea web UI
# http://gitea.homelab.lan
```

### Git Operations:
```bash
# Clone via HTTPS (external access)
git clone http://gitea.homelab.lan/ztc-admin/my-workloads.git

# Clone via SSH (after adding SSH keys to Gitea)
git clone git@gitea.homelab.lan:30022/ztc-admin/my-workloads.git

# Standard Git workflow
cd my-workloads
echo "# My Private Workloads" > README.md
git add . && git commit -m "initial commit"
git push origin main
```

### Private Workload Workflow:
1. **Create Repository**: Use Gitea web UI to create new repository
2. **Clone Locally**: `git clone http://gitea.homelab.lan/user/repo.git`
3. **Add Kubernetes Manifests**: Create your application YAML files
4. **Configure ArgoCD**: ArgoCD automatically uses internal service URLs for repository access
5. **Deploy**: ArgoCD automatically syncs and deploys your applications

**Note**: The workload deployment system automatically handles the URL translation between external user access (`gitea.homelab.lan`) and internal cluster access (`gitea-http.gitea.svc.cluster.local:3000`) for seamless GitOps integration.

### Resource Usage:
- **Gitea**: ~200MB RAM, minimal CPU (homelab-optimized)
- **PostgreSQL**: ~100MB RAM (bundled database)
- **Storage**: 10GB for repositories + 2GB for database
- **Network**: HTTP (3000), SSH (30022 NodePort)

### Backup Strategy:
- **Automatic**: Gitea data stored on `nfs-client` persistent volume
- **Manual**: Repository export via Gitea admin interface
- **Integrated**: Included in `make backup-secrets` archive

### Troubleshooting:
```bash
# Check Gitea deployment status
kubectl get pods -n gitea
kubectl logs -n gitea deployment/gitea

# If pod is not ready, check startup progress
kubectl describe pod -n gitea -l app=gitea

# Reset admin credentials (if needed)
kubectl delete secret -n gitea gitea-admin-secret
make setup  # Regenerate credentials
```

### Common Issues and Solutions:

**1. Workload Deployment Fails with "Cannot retrieve Gitea admin password"**
```bash
# Check if sealed secret exists and has both username and password
kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data}' | jq
# Should show both "username" and "password" keys

# If missing, apply the sealed secret:
kubectl apply -f kubernetes/system/gitea/values-secret.yaml
```

**2. ArgoCD Applications Show Authentication Errors**
```bash
# Check if ArgoCD repository credentials are configured
kubectl get secret -n argocd gitea-repo-credentials -o yaml

# Verify the secret has all required fields (type, url, username, password)
# If missing, apply repository credentials for internal access:
kubectl apply -f kubernetes/system/argocd/config/gitea-repository-credentials.yaml

# Restart ArgoCD components to pick up new credentials
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl rollout restart statefulset/argocd-application-controller -n argocd
```

**3. Web UI Login Issues**
- **Username**: `ztc-admin`
- **Password**: Retrieved from sealed secret:
  ```bash
  kubectl get secret -n gitea gitea-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```
- If using default setup: `changeme123` (should be changed to sealed secret)

### Installation Notes:
- **First-time deployment**: Use default credentials, then run `make setup` for secure credentials
- **Startup time**: Allow 2-3 minutes for initial database setup
- **Resource requirements**: ~300MB RAM total for Gitea + PostgreSQL

## Private Workload Templates

**ZERO-TOUCH DEPLOYMENTS**: Pre-configured templates for common homelab services that deploy with single commands via GitOps.

### Quick Deployment
```bash
# Deploy essential homelab services with one command each
make deploy-n8n            # Workflow automation platform
make deploy-uptime-kuma    # Service monitoring and status page
make deploy-homepage       # Service dashboard
make deploy-vaultwarden    # Password manager
make deploy-code-server    # VS Code development environment

# Check deployment status
make list-workloads
make workload-status WORKLOAD=n8n
```

### Available Templates

**Automation**
- **n8n**: Workflow automation platform (256-512Mi RAM, local-path storage)
  - *Note: For heavy usage with many workflows, consider increasing memory: `make deploy-n8n MEMORY_LIMIT=1Gi`*

**Monitoring**  
- **Uptime Kuma**: Service monitoring and status pages (64-128Mi RAM, local-path storage)

**Organization**
- **Homepage**: Modern service dashboard (32-64Mi RAM, local-path storage)

**Security**
- **Vaultwarden**: Self-hosted password manager (64-128Mi RAM, nfs-client storage)

**Development**
- **Code Server**: VS Code in browser (256-512Mi RAM, nfs-client storage)

### Template Architecture

Each template automatically:
1. **Processes configuration** using yq and envsubst for variable substitution
2. **Creates private Git repository** in Gitea for GitOps workflow
3. **Generates Kubernetes manifests** with homelab-optimized resource limits
4. **Creates ArgoCD Application** for automated deployment and sync
5. **Monitors deployment** progress and provides access information

### Template Customization
```bash
# Override template defaults with user-friendly syntax
make deploy-n8n STORAGE_SIZE=10Gi
make deploy-n8n HOSTNAME=automation.homelab.lan  
make deploy-code-server MEMORY_LIMIT=1Gi STORAGE_CLASS=local-path

# Image version pinning for stability
make deploy-n8n IMAGE_TAG=1.64.0        # Use specific n8n version
make deploy-vaultwarden IMAGE_TAG=1.31.0 # Use specific Vaultwarden version

# Multiple overrides
make deploy-vaultwarden STORAGE_SIZE=5Gi HOSTNAME=passwords.homelab.lan IMAGE_TAG=1.31.0

# Available override options:
# STORAGE_SIZE, STORAGE_CLASS, HOSTNAME, IMAGE_TAG
# MEMORY_REQUEST, MEMORY_LIMIT, CPU_REQUEST, CPU_LIMIT
# ADMIN_TOKEN, PASSWORD (for applicable services)
```

### Workload Management
```bash
# List all deployed workloads
kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads

# Check specific workload status
kubectl get pods,svc,ingress -n n8n

# Access workload URLs (example hostnames)
curl http://n8n.homelab.lan
curl http://status.homelab.lan
curl http://home.homelab.lan
curl http://vault.homelab.lan
curl http://code.homelab.lan

# Remove workload (manual cleanup required)
kubectl delete application workload-n8n -n argocd
kubectl delete namespace n8n
```

### Benefits vs Manual Deployment

**Before Templates (8+ manual steps, 15-30 minutes)**:
1. Access Gitea web UI and create repository
2. Clone repository locally
3. Create directory structure for applications
4. Write Kubernetes YAML manifests (deployment, service, ingress, PVC)
5. Configure resource limits, storage classes, and networking
6. Commit and push to private repository  
7. Create ArgoCD Application manifest
8. Apply ArgoCD configuration and wait for sync

**After Templates (1 command, 2-3 minutes)**:
```bash
make deploy-n8n
# 🔄 Deploying n8n workflow automation...
# ✅ Repository ztc-admin/workloads updated
# ✅ n8n manifests generated and committed
# ✅ ArgoCD application created
# 🔄 Waiting for deployment...
# ✅ n8n deployed successfully!
# 🌐 Access: http://n8n.homelab.lan
```

### Learning Examples vs Production Templates

ZTC provides both educational tools and production applications:

**Learning Examples** (`kubernetes/learning-examples/`):
- 🎓 **Purpose**: Learn Kubernetes concepts and test cluster functionality
- 🧪 **Content**: Hello-world app, storage demos, basic patterns
- 📚 **Usage**: Reference for custom workloads, troubleshooting
- 🔄 **Deployment**: Automatically via ArgoCD `learning-examples` application

**Workload Templates** (`kubernetes/workloads/templates/`):
- 🚀 **Purpose**: Deploy production-ready homelab applications  
- 🏆 **Content**: n8n, Uptime Kuma, Homepage, Vaultwarden, Code Server
- ⚡ **Usage**: One-command deployment with automated GitOps
- 🛠️ **Deployment**: `make deploy-<service>` with customization options

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