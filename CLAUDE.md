# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with Zero Touch Cluster.

## Product

### Mission
Zero Touch Cluster transforms bare metal into production-grade Kubernetes homelabs with zero manual configuration. Insert USB, press power, wait 15 minutes - your cluster is ready.

### Target Users
- **DevOps Engineers**: Production-like homelab for skill development and testing
- **Kubernetes Learners**: Hands-on experience without cloud costs or complexity
- **Homelab Enthusiasts**: Self-hosted services with enterprise-grade infrastructure
- **Educators**: Teaching modern DevOps practices with working examples

### Vision
Make Kubernetes infrastructure deployment as simple as installing an operating system, while maintaining enterprise-grade practices and security.

### Core Value Proposition
- **Zero Touch**: Fully automated deployment from bare metal to running workloads
- **Production Ready**: Real-world configuration that scales from homelab to enterprise
- **Educational**: Learn modern DevOps with working, documented examples
- **Self-Contained**: Private Git server, container registry, and GitOps workflow

## Standards

### Technology Stack
- **Container Orchestration**: k3s (lightweight Kubernetes distribution)
- **Infrastructure as Code**: Ansible for declarative automation
- **GitOps**: ArgoCD for application deployment and sync
- **Monitoring**: Prometheus + Grafana stack
- **Storage**: Hybrid local-path + Longhorn/MinIO
- **Networking**: Flannel CNI + Traefik ingress
- **Security**: Sealed Secrets, Ansible Vault, SSH keys
- **Container Registry**: Gitea with integrated registry

### Architecture Principles
- **Infrastructure as Code**: All configuration version controlled
- **GitOps Native**: Application deployments via Git workflows
- **Zero Touch Automation**: Minimize manual intervention
- **Hybrid Approach**: System components (Helm) + Applications (ArgoCD)
- **Security by Default**: Encrypted secrets, no plaintext passwords
- **Self-Contained**: Private Git server and container registry

### Development Standards
- **Commit Messages**: Conventional Commits format
  ```
  <type>(<scope>): <subject>
  feat(storage): add MinIO S3-compatible object storage
  fix(setup): resolve shell syntax error in setup wizard
  ```
- **Code Quality**: `make lint` and `make validate` before commits
- **Testing**: Validate against real infrastructure
- **Documentation**: Keep CLAUDE.md focused, detailed docs in /docs/

### File Organization
```
├── ansible/           # Infrastructure automation
├── kubernetes/        # K8s configurations
│   ├── system/       # Helm charts (monitoring, storage, ArgoCD)
│   └── workloads/    # ArgoCD application templates
├── provisioning/     # USB creation and cloud-init
├── tui/              # Terminal user interface
└── scripts/          # Automation scripts
```

## Specs

### Core Workflows

#### Quick Start Workflow
```bash
# 1. Prerequisites and configuration
make check                              # Verify system readiness
make prepare-auto                       # Generate cluster config with defaults

# 2. Node provisioning (15 min per node, unattended)
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
# Boot node with dual-USB method, type "yes" when prompted

# 3. Complete deployment
make setup                              # Deploy cluster + applications

# 4. Access services
# Primary dashboard: http://homelab.lan
# Git server: http://gitea.homelab.lan  
# GitOps: http://argocd.homelab.lan
# Monitoring: http://grafana.homelab.lan
```

#### Application Deployment
```bash
# Individual workloads
make deploy-n8n                        # Workflow automation
make deploy-uptime-kuma                 # Service monitoring
make deploy-vaultwarden                 # Password manager

# Workload bundles
make deploy-bundle-starter              # Homepage + monitoring
make deploy-bundle-productivity         # Code Server + n8n

# Custom applications
make deploy-custom-app APP_NAME=my-app IMAGE_TAG=latest
```

#### Credential Management
```bash
# View service credentials
make show-credentials                   # All service passwords
make show-credentials SERVICE=gitea     # Specific service
make copy-password SERVICE=grafana      # Copy to clipboard

# Backup and recovery
make backup-secrets                     # Encrypted backup
make export-credentials FILE=backup.txt # Export for recovery
```

### Essential Commands Reference

| Task | Command | Description |
|------|---------|-------------|
| **Setup** | `make prepare-auto` | Non-interactive cluster configuration |
| | `make setup` | Deploy complete infrastructure |
| **Status** | `make status` | Cluster health and component status |
| | `make validate-config` | Validate cluster configuration |
| **Storage** | `make storage` | Deploy configured storage stack |
| | `make longhorn-stack` | Deploy distributed storage |
| | `make minio-stack` | Deploy S3-compatible storage |
| **Credentials** | `make show-credentials` | Display all service passwords |
| | `make backup-secrets` | Create encrypted credential backup |
| **Workloads** | `make deploy-bundle-starter` | Deploy essential homelab services |
| | `make list-workloads` | List deployed applications |
| **Development** | `make teardown` | ⚠️ Complete cluster reset |
| | `make lint` | Validate Ansible/YAML syntax |

### Infrastructure Requirements

#### Hardware (Minimum per node)
- **RAM**: 8GB (16GB recommended)
- **CPU**: 2 cores (4 cores recommended)  
- **Storage**: 128GB (256GB NVMe recommended)
- **Network**: Gigabit Ethernet

#### Network Configuration
- **Default Subnet**: 192.168.50.0/24
- **Node IPs**: .10 (master), .11-.13 (workers), .20 (storage)
- **DNS**: homelab.lan domain for service access
- **Ingress**: Traefik (included with k3s)

#### Storage Classes
- **local-path**: Fast local storage (default, always available)
- **longhorn**: Distributed storage with replication (optional)
- **minio**: S3-compatible object storage (optional)

### Security Features

#### Secrets Management
- **Infrastructure Secrets**: Ansible Vault encryption
- **Application Secrets**: Kubernetes Sealed Secrets
- **Zero Plaintext**: All passwords auto-generated and encrypted
- **CLI Access**: `make show-credentials` for secure retrieval

#### Access Control
- **SSH Keys**: Ed25519 preferred, RSA compatible
- **Kubernetes RBAC**: Role-based access control
- **Private Registry**: Gitea with container registry
- **Network Security**: Private subnet, no external dependencies

### Service Architecture

#### Core Services (Always Deployed)
- **ZTC Dashboard**: `http://homelab.lan` - Unified service portal
- **Monitoring**: Prometheus + Grafana + AlertManager stack
- **GitOps**: ArgoCD for application deployment
- **Git Server**: Gitea with container registry

#### Optional Workloads
- **Automation**: n8n workflow platform
- **Monitoring**: Uptime Kuma service monitoring
- **Security**: Vaultwarden password manager
- **Development**: Code Server (VS Code in browser)

### Configuration Files

| File | Purpose |
|------|----------|
| `cluster.yaml` | Main cluster configuration |
| `ansible/inventory/secrets.yml` | Encrypted infrastructure secrets |
| `ansible/inventory/hosts.ini` | Node definitions and IPs |
| `provisioning/cloud-init/user-data` | Node bootstrap template |

### Extension Points

#### Custom Workload Templates
- Location: `kubernetes/workloads/templates/`
- Format: Jinja2 templates with variable substitution
- Deployment: `make deploy-<service>` with customization options

#### Bundle System
- Grouped deployments for different use cases
- Starter, Monitoring, Productivity, Security, Development bundles
- Single-command deployment of related services

#### Development Environment
- Container registry integration
- CI/CD with Gitea Actions
- Custom application deployment templates

### Quality Assurance

#### Validation Commands
```bash
make lint                               # Ansible playbook and YAML validation
make validate                           # Kubernetes manifest validation
make validate-config                    # Cluster configuration validation
make ping                               # Test Ansible connectivity
```

#### Testing Strategy
- **Configuration Validation**: JSON Schema validation for cluster.yaml
- **Connectivity Testing**: Ansible ping tests before deployment
- **Deployment Verification**: Health checks and status validation
- **Real Infrastructure**: Testing against actual hardware, not mocks

### Troubleshooting

#### Common Issues
- **USB Creation**: Use `make usb-list` to identify correct device
- **Network Config**: Update `ansible/inventory/hosts.ini` for your subnet
- **Credentials**: Use `make show-credentials` for secure access
- **Storage**: Check `make storage-status` for storage deployment issues

#### Debug Commands
```bash
# System status
make status                             # Overall cluster health
kubectl get nodes -o wide               # Node status and IPs
kubectl get pods --all-namespaces       # All pod status

# Component-specific
make longhorn-status                    # Longhorn storage status  
make minio-status                       # MinIO object storage status
make gitops-status                      # ArgoCD application status

# Logs and events
kubectl logs -n <namespace> <pod>       # Pod logs
kubectl get events --sort-by=.metadata.creationTimestamp  # Recent events
```

### Development Guidelines

#### Code Style
- **No Comments**: Code should be self-documenting
- **Conventional Commits**: Use standard prefixes (feat, fix, docs, etc.)
- **YAML Formatting**: 2-space indentation, explicit string quoting
- **Make Targets**: Descriptive names with help text

#### Testing Requirements
- **Validate Before Commit**: Always run `make lint` and `make validate`
- **Real Infrastructure Testing**: Test changes on actual cluster
- **Configuration Schema**: Validate cluster.yaml against JSON schema
- **Ansible Syntax**: Use ansible-lint for playbook validation

#### Documentation Standards
- **CLAUDE.md**: Standards, Product, Specs only - keep concise
- **Detailed Docs**: Use `/docs/` directory for comprehensive guides
- **Code Comments**: Avoid unless absolutely necessary for complex logic
- **README Updates**: Keep README.md focused on getting started

---

*For detailed documentation, troubleshooting guides, and advanced configuration, see `/docs/` directory.*