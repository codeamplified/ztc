# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zero Touch Cluster is a Kubernetes homelab automation project using k3s and Ansible. The infrastructure consists of:
- 4-node k3s cluster (1 master, 3 workers) on mini PCs
- Hybrid storage approach with local-path (built-in) and optional Longhorn
- Ansible for infrastructure provisioning and application deployment
- "Bootstrappable USB" provisioning workflow

## ZTC Entry Point

**UNIFIED ACCESS**: ZTC provides a professional dashboard at `http://homelab.lan` as the primary entry point to your cluster.

### Dashboard Features
- **Automatic Service Discovery**: Discovers ZTC services via Kubernetes annotations
- **Real-Time Cluster Metrics**: Live status of nodes, pods, CPU, and memory usage
- **Hot Configuration Reload**: Updates instantly without restarts when services change
- **Service Widgets**: Interactive widgets showing service health and metrics
- **Professional Interface**: Modern dark theme with ZTC branding
- **Zero Configuration Flash**: Loads ZTC content immediately without default page

### Core Services Access
- **Primary Portal**: `http://homelab.lan` - ZTC Dashboard and unified entry point
- **Git Server**: `http://gitea.homelab.lan` - Source code and container registry
- **GitOps**: `http://argocd.homelab.lan` - Deployment management and status
- **Monitoring**: `http://grafana.homelab.lan` - Metrics, logs, and dashboards

### First-Time User Experience
1. Complete infrastructure deployment with `make setup`
2. Access `http://homelab.lan` in your browser
3. Explore the dashboard to see all available services
4. Click service tiles for direct access to each application
5. View cluster health and deployment status in real-time

The ZTC dashboard automatically discovers deployed workloads and provides a consistent navigation experience across your entire homelab platform.

## Common Commands

### Infrastructure Provisioning
```bash
# STREAMLINED WORKFLOW (Recommended):
# 1. Check prerequisites and prepare infrastructure secrets
make check
make prepare-auto        # Non-interactive setup with homelab template + defaults
# OR for customization:
make prepare            # Interactive wizard for custom configuration

# 2. Create autoinstall USB drives for each node
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-worker-01 IP_OCTET=11

# 3. Deploy complete infrastructure (cluster + sealed secrets + applications)
make setup

# 4. Access your ZTC cluster
# Primary entry point: http://homelab.lan
# Provides unified access to all services and cluster status

# 5. Create encrypted backup of all secrets
make backup-secrets

# LEGACY WORKFLOW (Manual):
# Generate SSH key if needed (choose Ed25519 for better security)
ssh-keygen -t ed25519 -C "your-email@example.com"
# OR for RSA compatibility: ssh-keygen -t rsa -b 4096

# Setup secrets manually (NOT RECOMMENDED - use 'make prepare' instead)
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
make setup
```

### Kubernetes Cluster Verification
```bash
# Verify cluster status
make status

# Verify and configure storage
make storage              # Deploy default storage (local-path + NFS)
make storage NFS=false    # Deploy storage without NFS
make storage LONGHORN=true # Deploy storage with Longhorn
make storage-status       # Check storage deployment status

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

### Cluster Configuration Commands

**Prepare Commands** - Infrastructure setup with different modes:
```bash
# Quick setup with sensible defaults (recommended for most users)
make prepare-auto         # Non-interactive: uses homelab template
                         # - 4 nodes (1 master, 3 workers) + storage node
                         # - Hybrid storage (local-path + NFS)
                         # - All core components enabled
                         # - Starter bundle auto-deployed

# Interactive customization (for advanced users)
make prepare             # Interactive wizard with full customization
                         # - Choose node count and IPs
                         # - Select storage strategy
                         # - Enable/disable components
                         # - Configure workload bundles

# Template-based setup (alternative approach)
./scripts/lib/config-reader.sh templates     # List available templates
./scripts/lib/config-reader.sh use-template homelab  # Use specific template
make prepare             # Still need to run prepare for secrets

# Configuration validation and management
make validate-config     # Validate cluster.yaml against schema
./scripts/lib/config-reader.sh summary      # Show configuration overview
./scripts/lib/config-reader.sh validate     # Comprehensive validation
```

**When to use each prepare command:**
- **`prepare-auto`**: CI/CD pipelines, quick demos, containerized environments
- **`prepare`**: Custom network ranges, specific component selection, learning
- **Template approach**: Starting point for manual configuration editing

### Development Workflow

```bash
# Complete cluster teardown for development iteration
make teardown      # ⚠️  DESTRUCTIVE: Removes everything for fresh start

# Development cycle
make teardown      # Clean slate
make prepare       # New secrets and configuration  
make setup         # Deploy fresh cluster
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

**SECURE BY DEFAULT**: Zero Touch Cluster implements enterprise-grade secrets management using Kubernetes Sealed Secrets, providing zero-touch automation with strong security.

### Architecture Overview

ZTC uses a **two-layer security architecture**:

#### **Layer 1: Infrastructure Secrets (Ansible Vault)**
- SSH keys and cluster tokens in `ansible/inventory/secrets.yml`
- Ansible vault password in `.ansible-vault-password`
- k3s cluster initialization tokens
- **Encrypted at rest** and **never committed in plaintext**

#### **Layer 2: Application Secrets (Sealed Secrets)**
- Service passwords encrypted as Kubernetes secrets
- GitOps repository access tokens
- Monitoring stack authentication
- **Automatically generated** and **encrypted before cluster deployment**

### Credential Access

#### **Primary: Enhanced CLI Commands**
```bash
# Show all system credentials
make show-credentials

# Show specific service credentials
make show-credentials SERVICE=gitea
make show-credentials SERVICE=grafana
make show-credentials SERVICE=argocd

# Quick password access (password only)
make show-password SERVICE=gitea

# Copy password to clipboard (macOS/Linux)
make copy-password SERVICE=grafana

# Export all credentials to file
make export-credentials
make export-credentials FILE=my-backup.txt
```

#### **Advanced CLI Access**
```bash
# Direct kubectl access (if needed)
kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d
kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Security Features

#### **Zero-Touch Security:**
- ✅ **Automatic secret generation** with cryptographically secure passwords
- ✅ **No plaintext secrets** ever stored on disk (except in memory during setup)
- ✅ **Git-safe encryption** - all secrets encrypted before committing
- ✅ **No manual credential management** required

#### **Enterprise-Grade Protection:**
- ✅ **Sealed Secrets encryption** - secrets can only be decrypted in target cluster
- ✅ **Ansible Vault protection** for infrastructure secrets
- ✅ **Strong password generation** (32+ character base64 passwords)
- ✅ **Namespace isolation** prevents secret access across services

### Workflow

#### **Setup Phase** (Fully Automated):
1. `make prepare` creates infrastructure secrets (Ansible Vault)
2. `make setup` deploys cluster and generates application secrets
3. Sealed Secrets controller automatically decrypts secrets in cluster
4. All services start with secure, auto-generated credentials
5. User accesses credentials via `make show-credentials`

#### **Daily Use**:
```bash
# Quick access to any service
make show-credentials SERVICE=grafana
# Copy password and paste into browser

# Or copy directly to clipboard
make copy-password SERVICE=gitea
# Password now in clipboard for immediate paste
```

#### **Backup & Recovery**:
```bash
# Export all credentials for backup
make export-credentials FILE=ztc-backup-$(date +%Y%m%d).txt

# Store backup file securely (encrypted drive, password manager, etc.)
# Credentials can be recovered from this file if cluster is lost
```

### Optional: Professional Password Manager

For users who need advanced password management features, Vaultwarden can be deployed as an **optional workload**:

```bash
# Deploy Vaultwarden for advanced password management
make deploy-vaultwarden
```

**Vaultwarden provides:**
- 🌐 Browser auto-fill integration
- 📱 Mobile app access via Bitwarden apps  
- 👥 Multi-user sharing for families/teams
- 🔄 Sync across all devices
- 📊 Advanced security reporting

**See:** `kubernetes/workloads/templates/vaultwarden/README.md` for full details.

### Credential Management Comparison

| Feature | ZTC Built-in (Sealed Secrets) | Optional Vaultwarden |
|---------|-------------------------------|---------------------|
| **Setup** | ✅ Fully automatic | ⚠️ Manual account creation |
| **Security** | ✅ Enterprise-grade | ✅ Enterprise-grade |
| **CLI Access** | ✅ `make show-credentials` | ❌ API/CLI tools needed |
| **Browser Integration** | ❌ Manual copy/paste | ✅ Auto-fill |
| **Mobile Access** | ❌ CLI only | ✅ Native apps |
| **Maintenance** | ✅ Zero maintenance | ⚠️ Additional service |

**Recommendation**: Use ZTC built-in credentials for system administration. Deploy Vaultwarden only if you need browser/mobile integration or team sharing features.

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
- **Quick access**: `make show-credentials SERVICE=gitea`

### Installation Notes:
- **Secure credentials**: Automatically generated via Sealed Secrets during deployment
- **Credential access**: Use `make show-credentials SERVICE=gitea` to retrieve current password
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
- **Homepage**: Customizable service dashboard with Kubernetes integration (128-256Mi RAM, ConfigMap storage)
  - *Features: Service discovery, cluster metrics, custom themes, hot-reload configuration*

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

## Workload Bundles

**GROUPED DEPLOYMENTS**: ZTC bundles group related workloads for different user types and use cases, reducing multi-service deployment from 8+ commands to single bundle deployments.

### Quick Bundle Deployment
```bash
# Deploy complete stacks with one command
make deploy-bundle-starter      # Essential homelab services
make deploy-bundle-monitoring   # Complete monitoring solution
make deploy-bundle-productivity # Development and automation toolkit
make deploy-bundle-security     # Password management and security

# Bundle management
make list-bundles               # List all available bundles
make bundle-status              # Check deployment status of all bundles
```

### Available Bundles

**🚀 Starter Bundle** (192Mi RAM, 2Gi storage)
- **Perfect for**: First-time ZTC users, minimal resource usage
- **Services**: Homepage dashboard + Uptime Kuma monitoring
- **Use case**: Learning Kubernetes, testing cluster functionality

**📊 Monitoring Bundle** (192Mi RAM, 3Gi storage)
- **Perfect for**: Homelab operators wanting comprehensive monitoring
- **Services**: Uptime Kuma monitoring + Homepage dashboard
- **Use case**: 24/7 service monitoring and status pages

**🛠️ Productivity Bundle** (1Gi RAM, 15Gi storage)
- **Perfect for**: Developers, DevOps engineers, automation enthusiasts
- **Services**: Code Server + n8n automation platform
- **Use case**: Development environment and workflow automation

**🔒 Security Bundle** (128Mi RAM, 5Gi storage)
- **Perfect for**: Security-conscious users prioritizing credential management
- **Services**: Vaultwarden password manager
- **Use case**: Professional password management with browser integration

### Bundle vs Individual Deployment

**Individual Services** (traditional approach):
```bash
make deploy-homepage        # Just the dashboard
make deploy-uptime-kuma     # Just monitoring
make deploy-n8n             # Just automation
make deploy-code-server     # Just development environment
```

**Bundle Services** (streamlined approach):
```bash
make deploy-bundle-starter      # Homepage + Uptime Kuma
make deploy-bundle-productivity # Code Server + n8n
# Deploy related services together with optimized configuration
```

### Bundle Architecture

Each bundle includes:
- **Metadata**: Description, category, resource requirements
- **Workloads**: Services with deployment priority and dependencies
- **Overrides**: Optimized configuration for each service
- **Documentation**: Access URLs and post-installation steps

Templates remain available individually AND in meaningful bundles, providing flexibility for different deployment preferences and use cases.

## Custom Application Development

**INTEGRATED DEVELOPMENT**: ZTC provides a complete development platform for building and deploying custom applications with integrated container registry and CI/CD.

### Development Bundle

**Complete development infrastructure with one command:**
```bash
# Deploy development bundle for custom application development
make deploy-bundle-development

# This provides:
# - Enhanced Gitea with container registry (gitea.homelab.lan:5000)
# - Gitea Actions CI/CD runners for automated builds
# - VS Code development environment (http://code.homelab.lan)
# - n8n automation platform (http://automation.homelab.lan)
```

### Development Workflow

**Code to Production in Minutes:**
```bash
# 1. Create project in Gitea
git clone http://gitea.homelab.lan/ztc-admin/my-webapp.git
cd my-webapp

# 2. Add application code and Dockerfile
echo "FROM node:18-alpine" > Dockerfile
echo "COPY . /app" >> Dockerfile
echo "WORKDIR /app" >> Dockerfile
echo "EXPOSE 8080" >> Dockerfile
echo "CMD [\"npm\", \"start\"]" >> Dockerfile

# 3. Add CI/CD workflow
mkdir -p .gitea/workflows
cat > .gitea/workflows/build.yml <<EOF
name: Build and Push
on: [push]
jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: gitea.homelab.lan:5000
          username: \${{ secrets.REGISTRY_USER }}
          password: \${{ secrets.REGISTRY_PASSWORD }}
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: gitea.homelab.lan:5000/ztc-admin/my-webapp:\${{ github.sha }}
EOF

# 4. Push code - triggers automatic build
git add . && git commit -m "Initial commit" && git push

# 5. Deploy application via GitOps
make deploy-custom-app APP_NAME=my-webapp IMAGE_TAG=${COMMIT_SHA}

# 6. Application accessible immediately
curl http://my-webapp.homelab.lan
```

### Custom Application Commands

```bash
# Deploy custom application
make deploy-custom-app APP_NAME=my-api IMAGE_TAG=v1.0.0

# Deploy with custom configuration
make deploy-custom-app APP_NAME=my-web-service \
  IMAGE_TAG=latest \
  PORT=3000 \
  MEMORY_LIMIT=512Mi \
  STORAGE_ENABLED=true

# Container registry commands
make registry-login    # Login to ZTC registry
make registry-info     # Show registry information

# CI/CD runner deployment
make deploy-gitea-runner  # Deploy additional runners if needed
```

### Container Registry Integration

**ZTC includes enhanced Gitea with container registry:**
- **Registry URL**: `gitea.homelab.lan:5000`
- **Authentication**: Integrated with Gitea user accounts
- **Storage**: 40Gi dedicated for container images
- **API**: Docker-compatible registry API at `/v2` endpoint

### Custom Application Features

**Flexible deployment template supports:**
- **Any container image** from ZTC registry
- **Custom ports and hostnames**
- **Optional persistent storage**
- **Resource limits and requests**
- **Environment variables**
- **Health checks**
- **Security contexts**

### Development Benefits

**Complete Self-Contained Platform:**
- **No External Dependencies**: Everything runs within ZTC
- **Integrated Workflow**: Git → Build → Registry → Deploy → Live
- **GitOps Native**: All deployments managed by ArgoCD
- **Browser-Based Development**: Code from any device
- **Automated CI/CD**: Push-to-deploy workflow

**Professional Development Experience:**
- **Container Registry**: Private registry for custom images
- **CI/CD Pipeline**: Gitea Actions for automated builds
- **IDE Integration**: VS Code with extensions and Git integration
- **Automation**: n8n for DevOps workflows and integrations

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

**THREE-TIER STORAGE ARCHITECTURE**: Zero Touch Cluster supports local-path, Longhorn, and MinIO storage to meet diverse homelab requirements.

### When to Use Each Storage Class

**local-path (always available)**
- Built into k3s, zero configuration overhead
- System monitoring (Prometheus, Grafana, AlertManager)  
- Logs and temporary data
- Single-pod applications requiring fastest I/O
- Any workload that doesn't need to be shared across nodes

**longhorn (configurable, disabled by default)**
- **Production-grade distributed storage** for larger clusters (3+ nodes)
- **High availability** with automatic replication across nodes
- **Advanced features**: snapshots, backups, encryption, web UI
- **Fault tolerance** - survives node failures without data loss
- **Critical databases** and applications requiring enterprise storage

**minio (configurable, disabled by default)**
- **S3-compatible object storage** for modern cloud-native applications
- **Backup target** for Longhorn and application data
- **Large file storage** for media, documents, and assets
- **Multi-application sharing** via S3 API
- **Web console** for easy file management and bucket administration

### Storage Selection Guide

**Choose your storage architecture based on cluster scale and requirements:**

#### Learning/Development (1-2 nodes)
```bash
# Use only local-path (default)
# No additional configuration needed
```

#### Small Homelab (2-4 nodes)  
```bash
# Use local-path + MinIO (recommended)
make enable-minio        # Enable in configuration
make minio-stack         # Deploy MinIO object storage
```

#### Production Homelab (3+ nodes)
```bash
# Use local-path + Longhorn + MinIO (recommended)
make enable-longhorn     # Enable in configuration
make enable-minio        # Enable in configuration
make longhorn-stack      # Deploy Longhorn
make minio-stack         # Deploy MinIO
```

#### Advanced/Testing (Any size)
```bash
# Use all three storage classes
# Workloads choose optimal storage per use case
make storage LONGHORN=true MINIO=true  # Deploy all storage types
```

### Storage Commands

**Basic Storage Management:**
```bash
# View available storage classes
kubectl get storageclass

# Longhorn management
make longhorn-stack     # Deploy Longhorn distributed storage
make enable-longhorn    # Enable Longhorn in configuration  
make disable-longhorn   # Disable Longhorn (destroys data!)
make longhorn-status    # Check Longhorn deployment status

# MinIO management
make minio-stack        # Deploy MinIO object storage
make enable-minio       # Enable MinIO in configuration
make disable-minio      # Disable MinIO in configuration
make minio-status       # Check MinIO deployment status
make minio-console      # Access MinIO web console

# Storage verification
make storage            # Deploy configured storage stack
```

**Longhorn Specific Commands:**
```bash
# Access Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Then browse to http://localhost:8080

# Check Longhorn pods
kubectl get pods -n longhorn-system

# View Longhorn volumes
kubectl get pv | grep longhorn
```

**MinIO Specific Commands:**
```bash
# Access MinIO Console (Web UI)
# Direct browser access: http://minio-console.homelab.lan
make minio-console      # Or use port-forward method

# Access S3 API endpoint
# S3 endpoint: http://s3.homelab.lan
curl http://s3.homelab.lan/health/live

# Check MinIO pods and services
kubectl get pods,svc -n minio

# View MinIO credentials
make show-credentials SERVICE=minio
# Or direct kubectl access:
kubectl get secret -n minio minio-credentials -o jsonpath='{.data.access-key}' | base64 -d
kubectl get secret -n minio minio-credentials -o jsonpath='{.data.secret-key}' | base64 -d

# Create S3 bucket via API (example with aws-cli)
aws --endpoint-url http://s3.homelab.lan s3 mb s3://my-bucket
aws --endpoint-url http://s3.homelab.lan s3 ls
```

### Storage Architecture Examples

**Your 3+ Node Production Setup** (recommended):
```yaml
# cluster.yaml
storage:
  strategy: "hybrid"
  longhorn:
    enabled: true  # Enable Longhorn for production storage
  minio:
    enabled: true  # Enable MinIO for object storage
    storage_class: "longhorn"  # Use Longhorn for MinIO persistence

# Available storage classes:
# - local-path (fast, local storage)
# - longhorn (replicated, fault-tolerant storage)
# - minio (S3-compatible object storage)
```

**Template Usage with Storage Classes:**
```bash
# Use Longhorn for critical workloads
make deploy-vaultwarden STORAGE_CLASS=longhorn
make deploy-n8n STORAGE_CLASS=longhorn

# Use local-path for high-performance workloads  
make deploy-uptime-kuma STORAGE_CLASS=local-path

# Let templates choose defaults (varies by service)
make deploy-homepage    # Uses local-path by default

# Use MinIO for backup targets and large file storage
# (Applications configure S3 endpoints directly)
# S3 endpoint: http://s3.homelab.lan
# Console: http://minio-console.homelab.lan
```

**MinIO Integration Examples:**
```bash
# Configure Longhorn backups to use MinIO
kubectl patch settings.longhorn.io backup-target \
  --type merge -p '{"value":"s3://longhorn-backups@us-east-1/"}'

# Configure application backups to MinIO (example)
# App deployment with S3 backup configuration:
env:
- name: S3_ENDPOINT
  value: "http://s3.homelab.lan"
- name: S3_BUCKET
  value: "app-backups"
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: minio-credentials
      key: access-key
```

### Longhorn Prerequisites

**Before deploying Longhorn, ensure all nodes have:**
```bash
# Install open-iscsi (required dependency)
sudo apt update && sudo apt install -y open-iscsi

# Enable and start iscsid
sudo systemctl enable iscsid
sudo systemctl start iscsid

# Verify iscsi is working
sudo systemctl status iscsid
```

**This is handled automatically by the Ansible playbooks when `longhorn_enabled: true`**

### Storage Performance Comparison

| Storage Class | Performance | Availability | Use Case |
|---------------|-------------|--------------|----------|
| **local-path** | 🚀 Fastest | ❌ Node-tied | Logs, cache, single-pod apps |
| **longhorn** | ⚡ Good | ✅ Highly available | Databases, critical data, production |
| **minio** | 🌐 Network-dependent | ✅ Highly available | Object storage, backups, media files |

### Migration Between Storage Classes

**Moving from Local-Path to Longhorn:**
```bash
# 1. Deploy Longhorn
make longhorn-stack

# 2. Redeploy workloads with Longhorn storage
make deploy-vaultwarden STORAGE_CLASS=longhorn
make deploy-n8n STORAGE_CLASS=longhorn

# 3. Migrate data manually if needed
kubectl cp old-pod:/data new-pod:/data

# 4. Update default storage class if desired
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

### Storage Troubleshooting

**Longhorn Issues:**
```bash
# Check node readiness
kubectl get nodes -o wide

# Check Longhorn manager logs  
kubectl logs -n longhorn-system -l app=longhorn-manager

# Verify CSI driver
kubectl get csidriver

# Check storage class
kubectl describe storageclass longhorn
```

**Common Longhorn Problems:**
- **Pods stuck attaching**: Check if `open-iscsi` is running on all nodes
- **UI not accessible**: Verify Longhorn frontend service is running
- **Slow performance**: Check network between nodes, consider replica count
- **Volume stuck**: Check Longhorn manager logs for disk/node issues

**MinIO Issues:**
```bash
# Check MinIO installation job status
kubectl get job -n minio minio-installer

# Check MinIO installer logs
kubectl logs -n minio job/minio-installer

# Verify MinIO pods are running
kubectl get pods -n minio -l app=minio

# Check MinIO service endpoints
kubectl get ingress -n minio

# Verify MinIO credentials secret
kubectl get secret -n minio minio-credentials -o yaml
```

**Common MinIO Problems:**
- **Console not accessible**: Check if ingress is configured and DNS resolves
- **S3 API connection failed**: Verify MinIO pods are running and ingress routes
- **Installation stuck**: Check if underlying storage class (Longhorn/local-path) is available
- **Credentials not working**: Verify minio-credentials secret exists and is valid

**General Storage Issues:**
- **No storage classes**: Run `make storage` to deploy storage components
- **PVC stuck pending**: Check if appropriate storage class exists
- **Permission issues**: Verify pod security context and filesystem permissions

## Important Notes

- **Hardware Focus**: This is designed for physical mini PC deployment, not cloud
- **Hybrid GitOps**: System components via Helm, applications via ArgoCD with local examples
- **Infrastructure as Code**: All changes should be managed through Ansible and version controlled  
- **Single Master**: Current setup uses single k3s master (can be upgraded to HA later)
- **Production Security**: ADR-001 compliant secrets management with Vaultwarden password manager
- **Credential Management**: No plaintext passwords - all credentials managed via self-hosted Vaultwarden
- **Immediate Value**: Working cluster with example apps and secure credential access right after deployment
- **Simplified Storage**: Uses local-path (built-in) and optional Longhorn for production workloads

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