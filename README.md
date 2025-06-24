# Zero Touch Cluster

**Infrastructure-as-Code Kubernetes Homelab with GitOps**

Zero Touch Cluster is an open-source project that transforms bare metal into a production-grade Kubernetes homelab using modern DevOps practices. Built with k3s, Ansible, and automated USB provisioning, it delivers a complete 4-node cluster with monitoring, storage, and GitOps-ready infrastructure - all deployable with zero manual configuration.

> 🚀 **Zero Touch Promise**: Insert USB, press power, wait 15 minutes. Your node is deployed, configured, and ready to join the cluster.

## Why Zero Touch Cluster?

- **🤖 Fully Automated**: No manual configuration, no SSH sessions, no manual package installation
- **📦 Production Ready**: Real-world configuration that scales from homelab to enterprise
- **🔧 Highly Extensible**: Use as-is or customize for your specific needs
- **📚 Educational**: Learn modern DevOps practices with working examples
- **💰 Cost Effective**: Runs on mini PCs, old hardware, or cloud VMs
- **🏠 Homelab Focused**: Designed for home environments, not cloud complexity

## Quick Start

### Option 1: Use Our Reference Configuration
Perfect if you want to learn or already have compatible hardware (Raspberry Pis, mini PCs, or old laptops):

```bash
# 1. Clone the repository
git clone https://github.com/codeamplified/ztc
cd ztc

# 2. Setup secrets
make setup
edit ansible/inventory/secrets.yml
# Add your SSH key path: ansible_ssh_private_key_file: ~/.ssh/id_ed25519

# 3. Create USB drives and boot nodes (15 min each, unattended)
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10
# ... repeat for workers and storage

# 4. Deploy infrastructure
make infra

# 5. Verify cluster
kubectl get nodes -o wide
```

### Option 2: Customize for Your Environment

Adapt the configuration for your network, hardware, and requirements:

```bash
# 1. Fork this repository
# 2. Update network configuration in ansible/inventory/hosts.ini
# 3. Modify provisioning/cloud-init/user-data.template for your network
# 4. Follow deployment steps above
```

## Architecture Overview

Zero Touch Cluster implements a clean separation of concerns across five main components:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Control Node  │    │  k3s Master     │    │  k3s Workers    │
│   (Your PC)     │    │  (Mini PC)      │    │  (3x Mini PCs)  │
│                 │    │                 │    │                 │
│  • Ansible      │───▶│  • k3s Server   │◀──▶│  • k3s Agent    │
│  • kubectl      │    │  • Control Plane│    │  • Workloads    │
│  • USB Creation │    │  • 192.168.50.10│    │  • .50.11-.13   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                │
                       ┌─────────────────┐
                       │   Storage Node  │
                       │   (Mini PC)     │
                       │                 │
                       │  • NFS Server   │
                       │  • K8s Storage  │
                       │  • 192.168.1.20 │
                       └─────────────────┘
```

### Technology Stack

- **🎯 Kubernetes**: k3s (lightweight, single-binary, production-ready)
- **📋 Orchestration**: Ansible (infrastructure-as-code, repeatable deployments)
- **💾 Storage**: Hybrid local-path + NFS storage (both enabled by default)
- **🌐 Networking**: Flannel CNI + Traefik ingress (zero configuration)
- **🔧 Provisioning**: Cloud-init + dual-USB approach (scriptable, reliable)
- **🚢 GitOps**: ArgoCD for application deployment with hybrid Helm+GitOps architecture
- **🔐 Security**: SSH keys, encrypted secrets, RBAC

## Zero Touch Deployment Process

The magic of Zero Touch Cluster is in our "Bootstrappable USB" workflow:

### 1. Preparation (One-time setup)
```bash
# Create main Ubuntu installer USB (reusable for all nodes)
make autoinstall-usb DEVICE=/dev/sdb

# Generate node-specific cloud-init configs
make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11
make cidata-iso HOSTNAME=k3s-worker-02 IP_OCTET=12
```

### 2. Node Deployment (15 minutes each, unattended)
1. **Insert both USBs**: Main installer + node-specific config
2. **Boot from USB**: Press F12/F8 for boot menu, select Ubuntu installer
3. **Automatic detection**: Ubuntu finds cloud-init and prompts "Use autoinstall? (yes/no)"
4. **Confirm**: Type "yes" - installation proceeds completely hands-off
5. **Wait**: Node installs, configures, and reboots automatically
6. **Ready**: Node is accessible via SSH with your key, ready for Ansible

### 3. Cluster Integration
```bash
# Deploy complete infrastructure (includes system components + ArgoCD)
make infra

# Verify system components
kubectl get nodes -o wide
make gitops-status

# Configure private repository (optional)
# Then deploy your applications via ArgoCD
make argocd-apps
```

## Customization Guide

### Network Configuration

Update these files for your network:

```bash
# 1. Node IP addresses
vim ansible/inventory/hosts.ini           # Change 192.168.50.x to your IPs

# 2. Cloud-init network config  
vim provisioning/cloud-init/user-data.template  # Update subnet/gateway

# 3. DNS/routing (if needed)
vim ansible/roles/common/tasks/main.yml  # Network-specific tasks
```

### Hardware Requirements

**Minimum per node:**
- 8GB RAM, 2 CPU cores, 128GB storage

**Recommended (our reference):**
- 16GB RAM, 4 CPU cores, 256GB NVMe storage

**Tested alternatives:**
- Raspberry Pi 4 (8GB model)
- Intel NUCs or equivalent mini PCs
- Repurposed laptops/desktops
- Cloud VMs (adapt network configuration)

### Hybrid GitOps Architecture

Zero Touch Cluster separates **system infrastructure** from **application workloads**:

#### **System Components (Helm)**
```bash
# Deploy core infrastructure directly via Helm:
make system-components    # ztc-monitoring, ztc-storage, ArgoCD
```

#### **Application Workloads (ArgoCD)**
```bash
# 1. Create separate repository for your applications
# 2. Configure repository credentials:
cp kubernetes/system/argocd/config/repository-credentials.yaml.template \
   kubernetes/system/argocd/config/repository-credentials.yaml
# 3. ArgoCD automatically deploys from Git
make argocd-apps
```

**Why this approach?**
- ✅ **System stability**: Core infrastructure managed directly
- ✅ **GitOps benefits**: Applications follow Git-driven workflows  
- ✅ **Separation of concerns**: Infrastructure vs application lifecycle
- ✅ **Security**: Private workloads in separate repositories

## Directory Structure

```
zero-touch-cluster/
├── ansible/                    # Infrastructure automation
│   ├── inventory/             # Host definitions and secrets
│   ├── roles/                 # Reusable Ansible roles
│   └── playbooks/            # Deployment playbooks
├── kubernetes/                # Kubernetes configurations
│   ├── system/               # System components (ZTC Helm charts)
│   │   ├── monitoring/       # ztc-monitoring (Prometheus, Grafana, AlertManager)
│   │   ├── storage/          # ztc-storage (local-path + NFS for homelabs)
│   │   └── argocd/           # GitOps platform
│   └── argocd-apps/         # ArgoCD Application definitions
├── provisioning/             # USB creation and cloud-init
│   └── cloud-init/          # Node bootstrap configurations
└── docs/                     # Detailed documentation
```

## Common Operations

### Adding a New Node
```bash
# 1. Create cloud-init USB
make cidata-iso HOSTNAME=new-worker IP_OCTET=14

# 2. Boot node with dual-USB method
# 3. Update inventory
echo "192.168.50.14 ansible_host=192.168.50.14" >> ansible/inventory/hosts.ini

# 4. Deploy to new node
ansible-playbook ansible/playbooks/02-k3s-cluster.yml --limit=new-worker
```

### Removing a Node
```bash
# Gracefully drain and remove
kubectl drain <node-name> --ignore-daemonsets
kubectl delete node <node-name>
```

### Updating the Cluster
```bash
# Re-run Ansible playbooks
make infra

# Or update specific components
ansible-playbook ansible/playbooks/02-k3s-cluster.yml
```

## Storage Options

Zero Touch Cluster supports flexible storage:

### Local-Path Storage (Default)
- **Performance**: ⚡ Fastest (local NVMe)
- **Use case**: Databases, single-pod applications
- **Access modes**: ReadWriteOnce

### NFS Storage (Optional)
- **Performance**: 🌐 Network-dependent
- **Use case**: Shared storage, multi-pod applications  
- **Access modes**: ReadWriteOnce, ReadOnlyMany, ReadWriteMany

```bash
# Enable NFS storage
# Set nfs_enabled: true in ansible/inventory/group_vars/all.yml
make storage
```

## Security

- **SSH Key Authentication**: Password authentication disabled
- **Encrypted Secrets**: All sensitive data encrypted with ansible-vault
- **Network Security**: Kubernetes RBAC + private network
- **Container Security**: Regular image updates, security policies

## Reference Hardware Setup

This configuration is tested on:
- **5x Mini PCs**: 16GB RAM, 4 cores, 256GB NVMe each
- **Network**: Single flat network (192.168.50.0/24)
- **Power**: ~75W total cluster power consumption
- **Form factor**: Fits on a single shelf

## Community & Contributing

Zero Touch Cluster is designed to be extended and customized:

### Ways to Contribute
- **Share your hardware configs**: Add support for different hardware
- **Network topologies**: Contribute configurations for different network setups
- **Applications**: Add Kubernetes application examples
- **Documentation**: Improve guides and tutorials

### Getting Help
- **Issues**: Report bugs or request features via GitHub Issues
- **Discussions**: Ask questions or share your setups
- **Documentation**: Check `docs/customization-guide.md` for setup guidance

### Contributing Process
1. Fork the repository
2. Create a feature branch
4. Submit pull request with clear description

## Extensions and Examples

### Popular Extensions
- **GitOps**: ArgoCD integration for application deployment
- **Monitoring**: Prometheus + Grafana stack (included)
- **Service Mesh**: Istio or Linkerd integration
- **CI/CD**: Jenkins or Tekton pipelines
- **Backup**: Velero for cluster backups

### Real-World Use Cases
- **Home Lab**: Learning Kubernetes and cloud-native technologies
- **Development**: Testing applications in production-like environment
- **Edge Computing**: Lightweight Kubernetes for edge deployments
- **Education**: Teaching DevOps and container orchestration
- **Prototyping**: Validating architectures before cloud deployment

## Documentation

Available documentation:
- **Customization Guide**: `docs/customization-guide.md` - Adapting for your environment
- **Provisioning**: `provisioning/README.md` - USB creation and cloud-init details
- **Storage**: Hybrid approach (local-path + NFS) via `kubernetes/system/storage/`
- **Monitoring**: Helm chart configuration via `kubernetes/system/monitoring/`

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Zero Touch Cluster** - Because infrastructure should deploy itself.

*Star this repo if it helped you build your homelab! 🌟*