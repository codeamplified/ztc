# Essential Workload Templates

This directory contains pre-configured Kubernetes templates for common homelab services. These templates implement the "Zero Touch" philosophy by reducing complex workload deployment from 8+ manual steps to single `make` commands.

## Available Templates

### Automation
- **n8n** - Workflow automation platform for integrating homelab services

### Monitoring  
- **uptime-kuma** - Beautiful service monitoring and status pages

### Organization
- **homepage** - Modern dashboard for organizing all homelab services

### Security
- **vaultwarden** - Self-hosted Bitwarden-compatible password manager

### Development
- **code-server** - VS Code development environment accessible via browser

## Quick Deployment

```bash
# Deploy any service with a single command
make deploy-n8n            # Workflow automation
make deploy-uptime-kuma    # Service monitoring
make deploy-homepage       # Service dashboard
make deploy-vaultwarden    # Password manager
make deploy-code-server    # Development environment

# Check deployment status
make list-workloads
make workload-status WORKLOAD=n8n
```

## Template Structure

Each template includes:
- `template.yaml` - Metadata and configuration defaults
- `deployment.yaml` - Kubernetes deployment
- `service.yaml` - Service definition
- `ingress.yaml` - Traefik ingress configuration
- `pvc.yaml` - Persistent volume claim

## Resource Requirements

All templates are optimized for mini PC homelab environments:
- **Memory**: 32Mi - 512Mi depending on service
- **CPU**: 25m - 500m depending on service
- **Storage**: 500Mi - 10Gi with appropriate storage class selection

## Storage Strategy

- **local-path**: Fast local storage for single-pod applications (n8n, uptime-kuma, homepage)
- **nfs-client**: Shared storage for multi-device access (vaultwarden, code-server)

## Customization

Override template defaults:
```bash
make deploy-n8n STORAGE_SIZE=10Gi HOSTNAME=automation.homelab.local
make deploy-n8n IMAGE_TAG=1.64.0  # Pin to specific version
make deploy-vaultwarden MEMORY_LIMIT=256Mi IMAGE_TAG=1.31.0

# Available overrides: STORAGE_SIZE, STORAGE_CLASS, HOSTNAME, IMAGE_TAG,
#                     MEMORY_REQUEST, MEMORY_LIMIT, CPU_REQUEST, CPU_LIMIT
```

## Architecture

Templates automatically:
1. Generate Kubernetes manifests from templates
2. Create/update private Git repository in Gitea
3. Create ArgoCD Application for GitOps deployment
4. Monitor deployment progress and report status
5. Provide access URLs and credentials

This transforms the manual 15-30 minute deployment process into a 2-3 minute automated experience.