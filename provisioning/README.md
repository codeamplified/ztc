# Autoinstall USB Provisioning

Unattended Ubuntu Server installation for Kubernetes homelab nodes using dual-USB autoinstall approach.

## 🚀 Quick Start

```bash
# 1. Create main Ubuntu USB (once)
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10

# 2. Create cloud-init ISOs for additional nodes (efficient)
make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11
make cidata-iso HOSTNAME=k3s-worker-02 IP_OCTET=12
make cidata-iso HOSTNAME=k3s-worker-03 IP_OCTET=13
make cidata-iso HOSTNAME=k8s-storage IP_OCTET=20

# 3. Burn cloud-init ISOs to small USB drives
sudo dd if=provisioning/downloads/k3s-worker-01-cidata.iso of=/dev/sdX bs=4M status=progress

# 4. Boot nodes with dual-USB + kernel parameter → Deploy infrastructure
make infra
```

## 🎯 Key Features

### ✅ **Dual-USB Approach**
- **Main Ubuntu USB**: Standard Ubuntu Server installer (reusable)
- **Cloud-init USB**: Small ISO with node-specific config (368KB each)
- **Efficient workflow**: Create main USB once, generate config ISOs as needed

### ✅ **--cidata-only Flag** 
- **Efficient provisioning**: Skip main USB recreation for config changes
- **Quick generation**: Create config ISOs in seconds
- **Batch friendly**: Easy to generate multiple node configs

### ✅ **Zero-Touch Installation**
- **No manual interaction**: Fully automated 10-15 minute installation
- **Static IP configuration**: Each node gets correct IP automatically
- **SSH key authentication**: Password auth disabled, keys pre-installed
- **Kubernetes prerequisites**: Swap disabled, kernel modules loaded, passwordless sudo

## 🛠️ Usage Options

### **Makefile Integration**
```bash
# Interactive mode (prompts for hostname/IP)
make autoinstall-usb DEVICE=/dev/sdb

# Direct mode with parameters
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10

# Cloud-init ISO only (efficient for additional nodes)
make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11

# Streamlined: Create and write cidata to USB in one step
make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11

# List available USB devices
make usb-list

# With custom password
make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11 PASSWORD=mypass
```

### **Direct Script Usage**
```bash
# Full USB creation
./create-autoinstall-usb.sh /dev/sdb k3s-master 10

# Cloud-init ISO only
./create-autoinstall-usb.sh --cidata-only k3s-worker-01 11

# Interactive mode
./create-autoinstall-usb.sh /dev/sdb

# List available USB devices
./create-autoinstall-usb.sh -l

# Force creation without prompts
./create-autoinstall-usb.sh -f /dev/disk2 k3s-worker-01 11

# Custom SSH key and password
./create-autoinstall-usb.sh -k ~/.ssh/homelab.pub -p mypass --cidata-only k8s-storage 20
```

## 🏗️ Installation Process

### **Phase 1: USB Preparation**
```bash
# 1. Create main Ubuntu installer USB (once)
make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10

# 2. Create cloud-init ISOs for remaining nodes
for node in "k3s-worker-01 11" "k3s-worker-02 12" "k3s-worker-03 13" "k8s-storage 20"; do
  hostname=$(echo $node | cut -d' ' -f1)
  ip_octet=$(echo $node | cut -d' ' -f2)
  make cidata-iso HOSTNAME=$hostname IP_OCTET=$ip_octet
done

# 3. Burn cloud-init ISOs to small USB drives
sudo dd if=provisioning/downloads/k3s-worker-01-cidata.iso of=/dev/sdX bs=4M status=progress
# Repeat for each node...
```

### **Phase 2: Node Installation (10-15 minutes each)**
1. **Insert dual USBs**: Main Ubuntu USB + node-specific cloud-init USB
2. **Boot from main USB**: F12/F8/Delete for boot menu, select Ubuntu installer
3. **Automatic detection**: Ubuntu automatically detects the cidata ISO and prompts: **"Use autoinstall? (yes/no)"**
4. **Confirm**: Type **"yes"** - installation proceeds completely hands-off
5. **Wait**: Fully automated installation, node reboots when ready

### **Phase 3: Infrastructure Deployment**
```bash
# Verify all nodes are accessible
ansible k3s_cluster -m ping
ansible k8s_storage -m ping

# Deploy complete infrastructure
make infra
```

## 📚 Node Configuration Reference

| Hostname | IP Octet | Full IP | Role | USB Requirements |
|----------|----------|---------|------|------------------|
| k3s-master | 10 | 192.168.50.10 | Kubernetes control plane | Main USB (full) |
| k3s-worker-01 | 11 | 192.168.50.11 | Kubernetes worker | Main + Cloud-init |
| k3s-worker-02 | 12 | 192.168.50.12 | Kubernetes worker | Main + Cloud-init |
| k3s-worker-03 | 13 | 192.168.50.13 | Kubernetes worker | Main + Cloud-init |
| k8s-storage | 20 | 192.168.50.20 | Dedicated Kubernetes storage | Main + Cloud-init |

## ⚙️ Script Options Reference

```bash
Usage: ./create-autoinstall-usb.sh [OPTIONS] <usb_device> [hostname] [ip_octet]

Options:
    -h, --help           Show this help message
    -l, --list-devices   List available USB devices
    -f, --force          Skip confirmation prompts
    -i, --interactive    Force interactive mode even if args provided
    -k, --ssh-key FILE   SSH public key file (default: ~/.ssh/id_ed25519.pub)
    -p, --password PASS  Emergency password (default: ubuntu)
    --cidata-only        Create only cloud-init ISO (skip main USB creation)
    --keep-mount         Keep USB mounted after creation

Examples:
    ./create-autoinstall-usb.sh /dev/sdb                                    # Interactive mode
    ./create-autoinstall-usb.sh /dev/sdb k3s-master 10                     # Direct arguments
    ./create-autoinstall-usb.sh -i /dev/sdb                                # Force interactive
    ./create-autoinstall-usb.sh -f /dev/disk2 k3s-worker-01 11             # Force creation without prompts
    ./create-autoinstall-usb.sh --cidata-only k3s-worker-01 11             # Create only cloud-init ISO (no USB)
    ./create-autoinstall-usb.sh -l                                         # List available USB devices
```

## 🔧 Technical Details

### **Autoinstall Configuration**
- **Template-based**: Single `user-data.template` with runtime variable substitution
- **Variables**: `__HOSTNAME__`, `__IP_OCTET__`, `__SSH_PUBLIC_KEY__`, `__USER_PASSWORD_HASH__`
- **Network fixed**: Resolved netplan errors with proper interface matching
- **Sudo configured**: Passwordless sudo automatically set up during installation

### **Dual-USB Architecture**
- **Main USB**: Standard Ubuntu 24.04.2 live server ISO (read-only)
- **Cloud-init USB**: Tiny ISO (368KB) with NoCloud datasource
- **Boot process**: Kernel parameter `autoinstall ds=nocloud` triggers autoinstall
- **Data source**: Cloud-init finds configuration on second USB automatically

### **Security Model**
- **SSH keys**: Ed25519 or RSA key authentication only
- **Password auth**: Disabled by default
- **Emergency access**: Configurable password with SHA-512 hashing
- **User setup**: ubuntu user with passwordless sudo

## 🐛 Troubleshooting

### **USB Creation Issues**
```bash
# List available devices
./create-autoinstall-usb.sh -l

# Check device permissions
ls -la /dev/sd*  # Linux
diskutil list    # macOS

# Verify ISO exists
ls -la downloads/ubuntu-24.04.2-live-server-amd64.iso

# Check template syntax
grep "__.*__" cloud-init/user-data.template
```

### **Boot Issues**
- **Boot Order**: Set USB as first boot device
- **Autoinstall Prompt**: When prompted "Use autoinstall? (yes/no)", type "yes"
- **USB Compatibility**: Try different USB ports (2.0 vs 3.0)

### **Installation Issues**
```bash
# SSH to node and check status
ssh ubuntu@192.168.50.<ip_octet>
sudo cloud-init status --wait
sudo journalctl -u cloud-init

# Check autoinstall logs
sudo cat /var/log/installer/autoinstall-user-data
sudo cat /var/log/cloud-init.log

# Verify network configuration
ip addr show
cat /etc/netplan/*.yaml
```

### **Network Issues**
- **Netplan errors**: Fixed with proper interface matching in template
- **Static IPs**: Ensure DHCP range doesn't overlap (use 192.168.50.100-200)
- **Gateway**: Verify 192.168.50.1 is accessible
- **DNS**: Check 192.168.50.1, 1.1.1.1, 8.8.8.8 resolution

## 📁 Directory Structure

```
provisioning/
├── README.md                          # This documentation
├── cloud-init/
│   ├── user-data.template              # Parameterized autoinstall config
│   └── meta-data.template              # Cloud-init metadata template
├── create-autoinstall-usb.sh           # Main USB creation script
└── downloads/                          # ISO cache directory
    ├── ubuntu-24.04.2-live-server-amd64.iso    # Main Ubuntu installer
    ├── k3s-master-cidata.iso                   # Node-specific configs
    ├── k3s-worker-01-cidata.iso
    ├── k3s-worker-02-cidata.iso
    ├── k3s-worker-03-cidata.iso
    └── k8s-storage-cidata.iso
```

## 🔄 Integration with Homelab

### **Phase Integration**
- **Autoinstall**: Nodes ready for Ansible (Phase 1)
- **Infrastructure**: Ansible deploys k3s + NFS (Phase 2)
- **Applications**: Direct kubectl/Helm deployment (Phase 3)

### **Network Design**
- **Subnet**: 192.168.50.0/24
- **Static IPs**: 192.168.50.10-13 (k3s), 192.168.50.20 (nas)
- **DHCP**: 192.168.50.100-200 (recommended range)
- **Gateway/DNS**: 192.168.50.1

### **Next Steps After Provisioning**
```bash
# 1. Verify connectivity
make ping

# 2. Deploy infrastructure
make infra           # Full deployment
# OR step by step:
make storage        # Dual-purpose storage setup
make cluster        # k3s cluster deployment
```

## 🆚 Advantages Over Traditional Approach

### **Efficiency Gains**
- ✅ **95% faster**: Cloud-init ISOs vs full USB recreation
- ✅ **Less USB wear**: Reuse main Ubuntu USB
- ✅ **Batch friendly**: Generate multiple configs in seconds
- ✅ **Storage efficient**: 368KB ISOs vs 2.8GB full USBs

### **Operational Benefits**
- ✅ **Consistent base**: Same Ubuntu ISO for all nodes
- ✅ **Easy updates**: Update template, regenerate configs
- ✅ **Error recovery**: Quick config regeneration
- ✅ **Documentation**: Clear separation of concerns

### **Security Benefits**
- ✅ **Immutable base**: Ubuntu ISO integrity maintained
- ✅ **Auditable configs**: Clear config generation process
- ✅ **Key management**: Centralized SSH key deployment
- ✅ **Password policy**: Configurable emergency access