# Zero Touch Cluster - Guided Setup

The guided setup provides a beautiful, interactive experience for building your Kubernetes cluster. Perfect for new users who want a streamlined, error-free deployment process.

## Quick Start

```bash
# One command to start the guided setup
./ztc
```

That's it! The guided setup wizard will walk you through the entire process.

## What is Guided Setup?

Guided setup is a Terminal User Interface (TUI) that provides:

- **Visual welcome screen** with system prerequisite checks
- **Interactive configuration wizard** for cluster design
- **USB creation workflow** with device detection and validation
- **Real-time deployment monitoring** with progress tracking
- **Success dashboard** with service URLs and credentials

## Requirements

### System Requirements
- **Docker** (only dependency - everything else runs in container)
- **4+ Physical nodes** (mini PCs, servers, or workstations)
- **USB drives** for node installation (one per node)
- **Network switch** and ethernet cables

### Hardware Recommendations
- **Master node**: 4GB+ RAM, 32GB+ storage
- **Worker nodes**: 4GB+ RAM, 32GB+ storage each
- **Storage node**: 2GB+ RAM, 200GB+ storage
- **Network**: Gigabit switch, static IP range

## Guided Setup Flow

### 1. Welcome & Prerequisites
```
╔═══════════════════════════════════════════════════════╗
║          Zero Touch Cluster - Guided Setup            ║
╠═══════════════════════════════════════════════════════╣
║                                                       ║
║  Welcome! Let's build your Kubernetes cluster.        ║
║                                                       ║
║  ✓ Docker available                                   ║
║  ✓ SSH keys found                                     ║
║  ⚠ Network subnet not configured                      ║
║  ✓ Disk space sufficient                              ║
║                                                       ║
║  [Start Setup]  [Help]  [Quit]                        ║
╚═══════════════════════════════════════════════════════╝
```

The wizard automatically checks:
- Docker availability
- SSH key configuration
- Network connectivity
- Disk space requirements

### 2. Cluster Configuration
Interactive screens guide you through:
- **Basic settings**: Cluster name, description
- **Network configuration**: Subnet, DNS domain
- **Storage strategy**: Local, NFS, or hybrid
- **Component selection**: Monitoring, Git server, dashboard
- **Review and confirm**: Final configuration summary

### 3. USB Creation
- **Device detection**: Automatically finds available USB drives
- **Node assignment**: Maps each USB to a cluster node
- **Parallel creation**: Creates multiple USBs simultaneously
- **Validation**: Verifies each USB drive is bootable

### 4. Deployment Monitoring
```
Cluster Deployment
==================

● Infrastructure    [████████████████████████████████] 100%
● Secrets          [████████████████████████████████] 100%
◐ Networking       [████████████████████░░░░░░░░░░░░] 75%
○ Storage          [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%
○ Components       [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%
○ GitOps          [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%
○ Workloads       [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%

Recent activity:
  Installing k3s on master node...
  Configuring cluster networking...
  Verifying node connectivity...
```

Real-time monitoring shows:
- **Phase progress**: Each deployment phase with progress bars
- **Live logs**: Recent activity and command output
- **Error handling**: Guided troubleshooting if issues occur

### 5. Success & Access
```
🎉 Cluster Deployment Complete!

Available Services:
==================

→ ✓ Homepage Dashboard
    URL: http://homelab.lan
    Unified entry point to all services

  ✓ Gitea Git Server
    URL: http://gitea.homelab.lan
    Private Git hosting and container registry

  ✓ ArgoCD GitOps
    URL: http://argocd.homelab.lan
    Continuous deployment management

Next Steps:
==========
1. Visit http://homelab.lan to explore your cluster
2. Configure services using the generated credentials
3. Deploy additional applications via ArgoCD
```

## Key Benefits

### For New Users
- **Zero configuration required** - sensible defaults for everything
- **Visual feedback** - see exactly what's happening
- **Error prevention** - validates configuration before deployment
- **Guided recovery** - helpful suggestions when things go wrong

### For Automation
- **Consistent deployments** - same configuration every time
- **Reproducible results** - generates documented cluster configs
- **CI/CD friendly** - can be scripted for automated testing

### For Learning
- **Educational** - shows what each step does
- **Transparent** - generates human-readable configurations
- **Documented** - creates setup logs and documentation

## Configuration Templates

The guided setup includes pre-configured templates:

### Homelab Template (Default)
- **4 nodes**: 1 master + 3 workers + 1 storage
- **Network**: 192.168.50.0/24
- **Storage**: Hybrid (local-path + NFS)
- **Components**: Monitoring, Git, Dashboard, GitOps
- **Workloads**: Homepage + Uptime Kuma

### Small Template
- **3 nodes**: 1 master + 2 workers
- **Network**: 192.168.1.0/24
- **Storage**: Local-path only
- **Components**: Essential only
- **Workloads**: None

### Production Template
- **6+ nodes**: 3 masters + 3+ workers + 1 storage
- **Network**: Custom subnet
- **Storage**: Longhorn distributed storage
- **Components**: Full monitoring stack
- **Workloads**: Security bundle

## Advanced Features

### Session Management
- **Resume capability**: Continue where you left off
- **State persistence**: Saves progress between runs
- **Backup integration**: Automatically backs up configurations

### Customization
- **Template modification**: Edit templates before deployment
- **Component selection**: Choose which services to install
- **Resource allocation**: Adjust CPU/memory limits

### Troubleshooting
- **Built-in diagnostics**: Automated problem detection
- **Guided recovery**: Step-by-step issue resolution
- **Log aggregation**: Centralized deployment logging

## Comparison with Developer Mode

| Feature | Guided Setup | Developer Mode |
|---------|--------------|----------------|
| **Target Users** | New users, demos | Developers, power users |
| **Interface** | Interactive TUI | Command line |
| **Dependencies** | Docker only | Multiple tools |
| **Customization** | Template-based | Full control |
| **Error Handling** | Guided recovery | Raw errors |
| **Learning Curve** | Minimal | Steep |
| **Automation** | Repeatable | Scriptable |

## FAQ

### Q: Can I customize the cluster configuration?
A: Yes! The wizard provides template customization and you can edit the generated `cluster.yaml` file before deployment.

### Q: What if something goes wrong during deployment?
A: The guided setup includes error detection and recovery suggestions. You can also resume from where you left off.

### Q: Can I use this for production deployments?
A: The guided setup is perfect for learning and development. For production, consider using the developer mode for more control.

### Q: How do I access my cluster after deployment?
A: Visit `http://homelab.lan` for the unified dashboard, or use the specific service URLs shown in the completion screen.

### Q: Can I add more applications later?
A: Yes! Use the ArgoCD interface or the developer mode commands to deploy additional applications.

## Next Steps

After completing the guided setup:

1. **Explore your cluster**: Visit the dashboard and familiarize yourself with the services
2. **Deploy more applications**: Use the workload bundles or create custom deployments
3. **Learn the developer mode**: Graduate to full control with `./ztc-tui`
4. **Join the community**: Share your experience and get help from other users

The guided setup is designed to get you from zero to a working cluster in minutes, not hours. Enjoy building your Kubernetes homelab!