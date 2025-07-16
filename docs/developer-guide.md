# Zero Touch Cluster - Developer Guide

This guide is for developers, DevOps engineers, and power users who want direct access to ZTC's tools and full control over cluster configuration.

## Overview

Developer mode provides:
- **Direct command execution** via `./ztc-tui` wrapper
- **Full access to Makefile targets** and Ansible playbooks
- **Custom configuration editing** without templates
- **Advanced troubleshooting** capabilities
- **CI/CD integration** for automated deployments

## Getting Started

### Prerequisites

**Option 1: Docker (Recommended)**
- Docker or Podman installed
- SSH keys in `~/.ssh/`
- That's it!

**Option 2: Native Tools**
- make, ansible, kubectl, helm, yq, jq
- SSH keys configured
- Network access to target nodes

### Quick Start

```bash
# Check system readiness
./ztc-tui check

# Generate configuration (non-interactive)
./ztc-tui prepare-auto

# OR interactive customization
./ztc-tui prepare

# Deploy cluster
./ztc-tui setup

# Check status
./ztc-tui status
```

## Core Commands

### Configuration Management

```bash
# Generate infrastructure secrets
./ztc-tui prepare               # Interactive wizard
./ztc-tui prepare-auto          # Non-interactive with defaults

# Validate configuration
./ztc-tui validate-config       # Check cluster.yaml
./ztc-tui validate-schema       # Validate against JSON schema

# Show configuration
./ztc-tui show-config           # Display current config
./scripts/lib/config-reader.sh summary    # Detailed summary
```

### Cluster Operations

```bash
# Deploy complete cluster
./ztc-tui setup                 # Full deployment

# Individual phases
./ztc-tui cluster               # Just k3s cluster
./ztc-tui storage               # Storage configuration
./ztc-tui monitoring-stack      # Monitoring components
./ztc-tui argocd               # GitOps setup

# Check status
./ztc-tui status               # Overall cluster health
./ztc-tui ping                 # Test node connectivity
```

### Application Management

```bash
# Bundle deployments
./ztc-tui deploy-bundle-starter           # Homepage + monitoring
./ztc-tui deploy-bundle-monitoring        # Full monitoring stack
./ztc-tui deploy-bundle-productivity      # Development tools
./ztc-tui deploy-bundle-security          # Security tools

# Individual applications
./ztc-tui deploy-n8n                      # Workflow automation
./ztc-tui deploy-vaultwarden              # Password manager
./ztc-tui deploy-code-server              # VS Code in browser

# List available options
./ztc-tui list-bundles                    # Available bundles
./ztc-tui list-workloads                  # Available templates
```

### USB Provisioning

```bash
# List USB devices
./ztc-tui usb-list

# Create installation USBs
./ztc-tui autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
./ztc-tui autoinstall-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11

# Bulk creation
./scripts/provisioning/bulk-create-usbs.sh
```

### Credentials & Access

```bash
# Show all credentials
./ztc-tui show-credentials

# Specific service credentials
./ztc-tui show-password SERVICE=gitea
./ztc-tui show-password SERVICE=grafana
./ztc-tui show-password SERVICE=argocd

# Copy to clipboard
./ztc-tui copy-password SERVICE=vaultwarden

# Backup all secrets
./ztc-tui backup-secrets
```

## Configuration Files

### cluster.yaml
The main configuration file that defines your cluster:

```yaml
cluster:
  name: "my-cluster"
  description: "Custom Kubernetes cluster"
  version: "1.0.0"

network:
  subnet: "192.168.1.0/24"
  dns:
    enabled: true
    server_ip: "192.168.1.10"
    domain: "cluster.local"

nodes:
  ssh:
    key_path: "~/.ssh/id_rsa.pub"
    username: "ubuntu"
  
  cluster_nodes:
    master-01:
      ip: "192.168.1.10"
      role: "master"
      resources:
        cpu: "4"
        memory: "8Gi"
    worker-01:
      ip: "192.168.1.11"
      role: "worker"
      resources:
        cpu: "2"
        memory: "4Gi"

storage:
  strategy: "longhorn"
  default_class: "longhorn"
  longhorn:
    enabled: true
    replica_count: 3

components:
  monitoring:
    enabled: true
    namespace: "monitoring"
    components:
      prometheus: true
      grafana: true
      alertmanager: true
  
  gitea:
    enabled: true
    namespace: "gitea"
    features:
      container_registry: true
      actions_runner: true
```

### Templates
Use existing templates as starting points:

```bash
# List available templates
./scripts/lib/config-reader.sh templates

# Use a template
./scripts/lib/config-reader.sh use-template production
```

Available templates:
- **homelab**: 4 nodes, hybrid storage, all components
- **small**: 3 nodes, local storage, minimal components
- **production**: 6+ nodes, Longhorn, full monitoring
- **ha-example**: Multi-master setup with load balancer

## Advanced Usage

### Custom Ansible Playbooks

```bash
# Run specific playbooks
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/01-k8s-storage-setup.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/02-k3s-cluster.yml

# With specific tags
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/02-k3s-cluster.yml --tags "k3s-install"

# Check mode (dry run)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/02-k3s-cluster.yml --check
```

### Direct kubectl Operations

```bash
# After cluster deployment, kubectl is automatically configured
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get applications -n argocd

# Apply custom manifests
kubectl apply -f my-custom-app.yaml

# Port forwarding for local access
kubectl port-forward -n monitoring svc/grafana 3000:80
```

### Custom Workload Development

```bash
# Create custom workload template
cp kubernetes/workloads/templates/n8n/ kubernetes/workloads/templates/my-app/
# Edit template files
# Deploy with template engine
./scripts/workloads/deploy-workload.sh my-app
```

## Directory Structure

```
/
├── ansible/                   # Infrastructure automation
│   ├── inventory/            # Node definitions and secrets
│   ├── playbooks/            # Deployment playbooks
│   └── roles/                # Reusable automation roles
├── kubernetes/               # Kubernetes configurations
│   ├── system/               # System components (Helm)
│   ├── argocd-apps/          # ArgoCD applications
│   └── workloads/            # Application templates
├── scripts/                  # Utility scripts
│   ├── lib/                  # Shared libraries
│   ├── provisioning/         # USB creation scripts
│   └── workloads/            # Workload management
├── templates/                # Configuration templates
├── schema/                   # JSON schema validation
└── docs/                     # Documentation
```

## Development Workflow

### 1. Configuration Development
```bash
# Edit cluster configuration
vim cluster.yaml

# Validate changes
./ztc-tui validate-config

# Generate Ansible inventory
./ztc-tui generate-inventory

# Test connectivity
./ztc-tui ping
```

### 2. Iterative Development
```bash
# Clean slate for testing
./ztc-tui teardown

# Deploy with new configuration
./ztc-tui setup

# Test specific components
./ztc-tui deploy-bundle-starter
```

### 3. Custom Application Development
```bash
# Create custom application
mkdir -p kubernetes/workloads/templates/my-app

# Develop and test
./ztc-tui deploy-custom-app APP_NAME=my-app

# Version control
git add kubernetes/workloads/templates/my-app/
git commit -m "Add custom application template"
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy ZTC Cluster
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup ZTC
      run: |
        chmod +x ztc-tui
        ./ztc-tui prepare-auto
    
    - name: Deploy Cluster
      run: ./ztc-tui setup
      env:
        ANSIBLE_HOST_KEY_CHECKING: false
    
    - name: Validate Deployment
      run: ./ztc-tui status
```

### Docker Usage

```bash
# Build ZTC image
./ztc-tui --docker-build

# Run in container
./ztc-tui --docker-shell

# Or use directly
docker run -it --rm -v $(pwd):/workspace ztc:latest prepare-auto
```

## Troubleshooting

### Common Issues

**1. Connection Issues**
```bash
# Test connectivity
./ztc-tui ping

# Check SSH keys
ssh-add -l

# Test manual SSH
ssh ubuntu@192.168.50.10
```

**2. Configuration Errors**
```bash
# Validate configuration
./ztc-tui validate-config

# Check schema compliance
./ztc-tui validate-schema

# Debug configuration
./scripts/lib/config-reader.sh get storage.strategy
```

**3. Deployment Failures**
```bash
# Check Ansible logs
tail -f ansible/ansible.log

# Debug playbook execution
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/02-k3s-cluster.yml -vvv

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces
```

### Advanced Debugging

```bash
# Enable debug mode
export ZTC_DEBUG=true

# Verbose Ansible output
export ANSIBLE_STDOUT_CALLBACK=debug

# Check cluster events
kubectl get events --sort-by=.metadata.creationTimestamp

# Debug specific workload
kubectl logs -f -n monitoring -l app=prometheus
```

## Best Practices

### Configuration Management
- Version control your `cluster.yaml`
- Use templates as starting points
- Validate before deployment
- Back up working configurations

### Security
- Use Ed25519 SSH keys
- Enable RBAC
- Regularly update secrets
- Use network policies

### Monitoring
- Enable full monitoring stack
- Set up alerting
- Monitor resource usage
- Plan for capacity

### Development
- Use feature branches
- Test in isolated environments
- Document custom configurations
- Share templates with team

## Migration from Guided Setup

If you started with guided setup and want to move to developer mode:

1. **Understand your configuration**: Review the generated `cluster.yaml`
2. **Learn the commands**: Start with `./ztc-tui status` and `./ztc-tui show-config`
3. **Explore templates**: See what other configurations are available
4. **Customize gradually**: Make small changes and test thoroughly
5. **Use version control**: Track your configuration changes

The developer mode gives you full control over your ZTC cluster while maintaining the same underlying reliability and automation.