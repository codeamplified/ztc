# Zero Touch Cluster - Docker Setup Guide

**Zero Dependencies**: Run ZTC with just Docker - no need to install Ansible, kubectl, Helm, yq, or any other tools locally.

## Quick Start

### One-Command Installation

```bash
# Install ZTC with zero dependencies
curl -sSL https://raw.githubusercontent.com/zero-touch-cluster/ztc/main/install.sh | bash

# Navigate to ZTC directory
cd ~/ztc

# Use ZTC (all commands work identically)
./ztc prepare    # Same as 'make prepare' but in container
./ztc setup      # Same as 'make setup' but in container
./ztc status     # Same as 'make status' but in container
```

### Manual Installation

```bash
# Clone repository
git clone https://github.com/zero-touch-cluster/ztc.git
cd ztc

# Build Docker image
make docker-build

# Use ZTC wrapper
./ztc help
```

## Docker Wrapper Usage

The `./ztc` script is a Docker wrapper that provides seamless execution of all ZTC commands.

### Basic Commands

```bash
# All standard ZTC commands work through the wrapper
./ztc help                    # Show ZTC help
./ztc prepare                 # Run setup wizard
./ztc setup                   # Deploy cluster
./ztc status                  # Check cluster status
./ztc validate-config         # Validate configuration
./ztc deploy-bundle-starter   # Deploy workload bundles
```

### Docker-Specific Commands

```bash
# Docker environment management
./ztc --docker-build         # Build ZTC container image
./ztc --docker-status        # Show Docker environment info
./ztc --docker-shell         # Open interactive shell in container
./ztc --native               # Force use of native tools (bypass Docker)
```

### Volume Mounts

The Docker wrapper automatically mounts necessary directories:

- **SSH Keys**: `~/.ssh` → `/home/ztc/.ssh` (read-only)
- **Workspace**: Current directory → `/workspace`
- **Kubectl Config**: `~/.kube` → `/home/ztc/.kube` (read-only, if exists)

## Benefits

### For New Users
- **Zero Dependencies**: Only Docker required
- **Consistent Environment**: Identical tool versions
- **Cross-Platform**: Works on Linux, macOS, Windows
- **No Conflicts**: Isolated environment

### For Existing Users
- **Backward Compatible**: All existing `make` commands still work
- **Choice**: Use Docker wrapper or native tools
- **Migration**: Gradual transition at your own pace

## Requirements

### System Requirements
- **Docker**: Version 20.10+ or Podman 3.0+
- **Operating System**: Linux, macOS, or Windows with WSL2
- **Memory**: 4GB RAM (2GB for container, 2GB for host)
- **Storage**: 2GB for Docker image and build cache

### Network Requirements
- **Internet Access**: For initial image build and tool downloads
- **SSH Access**: To target cluster nodes (keys mounted from `~/.ssh`)
- **Host Networking**: Container uses host network for cluster access

## Installation Options

### Option 1: Automatic Installation (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/zero-touch-cluster/ztc/main/install.sh | bash
```

**What it does:**
- Detects your operating system
- Installs Docker if not present
- Clones ZTC repository
- Builds Docker image
- Adds `ztc` alias to your shell

### Option 2: Manual Docker Installation

**Ubuntu/Debian:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install ZTC
git clone https://github.com/zero-touch-cluster/ztc.git
cd ztc
make docker-build
```

**macOS:**
```bash
# Install Docker Desktop from https://www.docker.com/products/docker-desktop
# Then clone and build ZTC
git clone https://github.com/zero-touch-cluster/ztc.git
cd ztc
make docker-build
```

**Windows (WSL2):**
```bash
# Install Docker Desktop with WSL2 integration
# In WSL2 terminal:
git clone https://github.com/zero-touch-cluster/ztc.git
cd ztc
make docker-build
```

### Option 3: Podman (Docker Alternative)

```bash
# Install Podman
sudo apt install podman  # Ubuntu
brew install podman      # macOS

# Use ZTC (automatically detects Podman)
git clone https://github.com/zero-touch-cluster/ztc.git
cd ztc
make docker-build  # Works with Podman too
./ztc help
```

## Docker Image Details

### Base Image
- **OS**: Ubuntu 22.04 LTS
- **Size**: ~800MB (optimized with multi-stage build)
- **Architecture**: linux/amd64 (matches typical cluster nodes)

### Included Tools
- **Ansible**: 9.0.1 with kubernetes.core collection
- **kubectl**: Latest stable version
- **Helm**: v3.13.3
- **yq**: v4.35.2 (YAML processor)
- **jq**: Latest (JSON processor)
- **kubeseal**: v0.24.5 (Sealed Secrets)
- **System Tools**: ssh, curl, git, make, python3

### Build Optimization
- **Layer Caching**: Efficient rebuilds
- **Multi-stage**: Minimal final image size
- **.dockerignore**: Excludes unnecessary files
- **Security**: Non-root user execution

## Troubleshooting

### Common Issues

#### 1. Docker Permission Denied
```bash
# Error: permission denied while trying to connect to Docker daemon
# Solution: Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

#### 2. SSH Key Mount Issues
```bash
# Error: SSH keys not accessible in container
# Check: SSH directory exists and has correct permissions
ls -la ~/.ssh/
chmod 700 ~/.ssh/
chmod 600 ~/.ssh/id_*
```

#### 3. Container Build Failures
```bash
# Error: Docker build fails
# Solution: Clean up and rebuild
docker system prune -f
make docker-build
```

#### 4. Network Connectivity Issues
```bash
# Error: Can't reach cluster nodes from container
# Check: Host networking and firewall
docker run --rm --network host alpine ping 192.168.50.10
```

### Debug Commands

```bash
# Check Docker environment
./ztc --docker-status

# Test container functionality
make docker-test

# Open interactive shell for debugging
./ztc --docker-shell

# Check container logs
docker logs $(docker ps -q --filter ancestor=ztc:latest)

# Force native tools (bypass Docker)
./ztc --native check
```

### Performance Optimization

#### Image Build Optimization
```bash
# Clean Docker cache
docker system prune -a

# Build with no cache (force fresh build)
docker build --no-cache -t ztc:latest .

# Multi-platform build (if needed)
docker buildx build --platform linux/amd64 -t ztc:latest .
```

#### Runtime Optimization
```bash
# Use memory limit if needed
./ztc() {
    docker run --rm --memory=2g --network host \
        -v ~/.ssh:/home/ztc/.ssh:ro \
        -v $(pwd):/workspace \
        ztc:latest "$@"
}
```

## Advanced Usage

### Custom Container Configuration

Create a custom wrapper script for specific needs:

```bash
#!/bin/bash
# custom-ztc.sh - Custom Docker wrapper

# Custom image name
ZTC_IMAGE="my-ztc:latest"

# Additional volume mounts
EXTRA_MOUNTS=(
    "-v" "/my/custom/path:/workspace/custom"
    "-v" "/etc/hosts:/etc/hosts:ro"
)

docker run --rm --network host \
    -v ~/.ssh:/home/ztc/.ssh:ro \
    -v $(pwd):/workspace \
    "${EXTRA_MOUNTS[@]}" \
    "$ZTC_IMAGE" "$@"
```

### Development Workflow

```bash
# Development cycle with Docker
./ztc prepare                 # Generate configuration
./ztc validate-config         # Validate before deployment
./ztc setup                   # Deploy cluster
./ztc status                  # Verify deployment
./ztc deploy-bundle-starter   # Deploy test workloads
```

### CI/CD Integration

```yaml
# .github/workflows/deploy.yml
name: Deploy ZTC Cluster
on: [workflow_dispatch]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build ZTC image
        run: docker build -t ztc:latest .
      - name: Deploy cluster
        run: |
          docker run --rm --network host \
            -v ${{ secrets.SSH_PRIVATE_KEY }}:/tmp/ssh_key:ro \
            -v $(pwd):/workspace \
            ztc:latest setup
```

## Migration from Native Tools

### Gradual Migration

You can use both approaches during transition:

```bash
# Continue using native tools
make prepare
make setup

# Or use Docker wrapper
./ztc prepare
./ztc setup

# Both work identically
```

### Full Migration

To switch completely to Docker:

```bash
# Remove native tools (optional)
sudo apt remove ansible kubectl helm

# Use only Docker wrapper
alias make='./ztc'  # Redirect all make commands
```

## Comparison: Docker vs Native

| Aspect | Docker Wrapper | Native Tools |
|--------|----------------|--------------|
| **Setup Time** | 5 minutes | 15-30 minutes |
| **Dependencies** | Docker only | 8-10 tools |
| **Consistency** | ✅ Identical everywhere | ❌ Version differences |
| **Isolation** | ✅ No conflicts | ❌ Dependency hell |
| **Performance** | ~10% overhead | Native speed |
| **Disk Usage** | ~800MB image | ~200MB tools |
| **Updates** | Rebuild image | Update each tool |

## Support

### Getting Help

```bash
# ZTC help
./ztc help

# Docker environment status
./ztc --docker-status

# Interactive debugging
./ztc --docker-shell
```

### Reporting Issues

When reporting Docker-related issues, include:

```bash
# System information
docker --version
./ztc --docker-status

# Container logs
docker logs $(docker ps -q --filter ancestor=ztc:latest)

# Host connectivity test
ping 192.168.50.10
```

---

**Next Steps**: See [Configuration System Guide](configuration-system.md) for cluster setup details.