# GitOps Implementation Guide

## Overview

This document describes the hybrid GitOps implementation that combines the reliability of Helm charts for base components with the power of ArgoCD for application deployment.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Homelab Infrastructure                        │
├─────────────────────────────────────────────────────────────────┤
│  Ansible (Infrastructure)                                       │
│  ├── Cluster Setup (k3s)                                       │
│  └── Node Configuration                                         │
├─────────────────────────────────────────────────────────────────┤
│  Helm Charts (System Components)                                │
│  ├── Monitoring Stack (Prometheus, Grafana, AlertManager)      │
│  ├── Storage Stack (local-path + optional NFS)                 │
│  └── ArgoCD Installation                                        │
├─────────────────────────────────────────────────────────────────┤
│  ArgoCD (Application Management)                                │
│  └── Private Workloads Repository                               │
│      ├── Applications                                           │
│      ├── Secrets (SOPS/Sealed Secrets)                        │
│      └── Environment-specific configs                          │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Deploy Infrastructure with GitOps
```bash
# This now deploys everything including ArgoCD
make infra
```

This single command will:
- Deploy cluster infrastructure (Ansible)
- Install monitoring stack (Helm)
- Install storage stack (Helm)
- Install and configure ArgoCD (Kustomize)

### 2. Configure Private Repository Access
```bash
# Copy and edit repository credentials
cp kubernetes/system/argocd/config/repository-credentials.yaml.template \
   kubernetes/system/argocd/config/repository-credentials.yaml

# Edit with your private repository URL and credentials
vim kubernetes/system/argocd/config/repository-credentials.yaml

# Apply the credentials
kubectl apply -f kubernetes/system/argocd/config/repository-credentials.yaml
```

### 3. Deploy ArgoCD Applications
```bash
# Deploy applications pointing to private repository
make argocd-apps

# Check status
make gitops-status
```

## Component Architecture

### System Components (Helm Charts)

#### Monitoring Stack
- **Location**: `kubernetes/system/monitoring/`
- **Components**: Prometheus, Grafana, AlertManager
- **Command**: `make monitoring-stack`
- **Features**:
  - Configurable storage class (local-path or NFS)
  - Resource limits optimized for homelab
  - k3s-specific metric collection
  - Traefik ingress integration

#### Storage Stack
- **Location**: `kubernetes/system/storage/`
- **Components**: Local-path (default) + optional NFS provisioner
- **Command**: `make storage-stack`
- **Features**:
  - Hybrid storage approach
  - Configurable NFS server settings
  - Example PVCs for testing

### ArgoCD Configuration

#### Installation
- **Location**: `kubernetes/system/argocd/install/`
- **Method**: Kustomize overlays on official ArgoCD manifests
- **Features**:
  - Traefik ingress configuration
  - Insecure mode for internal access
  - RBAC configuration

#### Applications
- **Location**: `kubernetes/argocd-apps/`
- **Target**: Private workloads repository
- **Features**:
  - Automatic sync with self-healing
  - Namespace auto-creation
  - Configurable retry policies

## Usage Patterns

### Development Workflow

1. **Infrastructure Changes**:
   ```bash
   # Make changes to system components
   make monitoring-stack  # or storage-stack
   ```

2. **Application Changes**:
   ```bash
   # Commit to private workloads repository
   git push origin main
   # ArgoCD automatically syncs changes
   ```

3. **Manual Sync**:
   ```bash
   make gitops-sync
   ```

### Monitoring and Status

```bash
# Overall cluster status
make status

# GitOps-specific status
make gitops-status

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Or via ingress: http://argocd.homelab.local
```

## Next Steps

### Creating Private Workloads Repository

1. **Create Repository Structure**:
   ```
   private-workloads/
   ├── applications/
   │   ├── nextcloud/
   │   ├── home-assistant/
   │   └── custom-apps/
   ├── secrets/
   └── environments/
   ```

2. **Configure Applications**:
   - Use Kustomize for configuration management
   - Implement secrets management (SOPS or Sealed Secrets)
   - Create environment-specific overlays

3. **Update ArgoCD Application**:
   - Edit `kubernetes/argocd-apps/private-workloads.yaml`
   - Update repository URL to your private repository
   - Adjust path and sync policies as needed

## Benefits of This Approach

### ✅ Operational Excellence
- **Fast Bootstrap**: Single command deployment
- **Reliable Base**: Helm charts for stable components
- **Modern GitOps**: ArgoCD for application management
- **Clear Separation**: Infrastructure vs. Applications

### ✅ Development Experience
- **Infrastructure as Code**: All changes version controlled
- **Automated Sync**: Applications deploy automatically
- **Easy Rollbacks**: Git-based rollback mechanism
- **Monitoring**: Built-in observability stack

### ✅ Security & Compliance
- **Private Workloads**: Sensitive applications in private repository
- **Secrets Management**: Encrypted secrets with proper tooling
- **RBAC**: Role-based access control
- **Audit Trail**: Git history for all changes

## Troubleshooting

### Common Issues

1. **ArgoCD Sync Failures**:
   ```bash
   make gitops-status
   kubectl logs -n argocd deployment/argocd-application-controller
   ```

2. **Repository Access Issues**:
   ```bash
   kubectl get secrets -n argocd
   kubectl describe secret private-repo-creds -n argocd
   ```

3. **Helm Chart Issues**:
   ```bash
   helm list -A
   helm status monitoring -n monitoring
   ```