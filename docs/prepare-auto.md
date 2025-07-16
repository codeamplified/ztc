# Non-Interactive Setup with prepare-auto

The `prepare-auto` command provides a streamlined, non-interactive setup for Zero Touch Cluster that's perfect for automation, CI/CD pipelines, and containerized environments.

## Quick Start

```bash
# One-command setup with sensible defaults
./ztc prepare-auto

# OR using Make directly
make prepare-auto
```

## What prepare-auto Does

1. **Generates cluster.yaml** using the homelab template
2. **Creates Ansible vault** with auto-generated password
3. **Generates infrastructure secrets** (SSH keys, cluster tokens)
4. **Validates configuration** automatically
5. **No user interaction required** - runs completely unattended

## When to Use prepare-auto

✅ **Perfect for:**
- CI/CD pipelines and automation
- Docker/containerized environments
- Quick demos and testing
- First-time users who want to get started quickly
- Environments where TTY/interactive input isn't available

❌ **Use interactive `prepare` instead for:**
- Custom network ranges (non-192.168.50.x)
- Different node counts or storage strategies
- Learning how ZTC configuration works
- Specific component selection

## Default Configuration

The homelab template provides:

**Cluster:**
- **4 nodes**: 1 master (192.168.50.10) + 3 workers (192.168.50.11-13)
- **Storage node**: Dedicated storage (192.168.50.20)
- **Network**: 192.168.50.0/24 subnet

**Components:**
- ✅ Monitoring stack (Prometheus, Grafana)
- ✅ Gitea Git server with container registry
- ✅ Homepage dashboard
- ✅ ArgoCD GitOps
- ✅ Sealed secrets management

**Storage:**
- **Strategy**: Hybrid (local-path + NFS)
- **Default class**: local-path (fast)
- **Shared storage**: NFS for multi-pod apps

**Auto-deploy:**
- **Starter bundle**: Homepage + Uptime Kuma

## Customization After prepare-auto

```bash
# Edit configuration before deploying
nano cluster.yaml

# Validate your changes
./ztc validate-config

# Show configuration summary
./scripts/lib/config-reader.sh summary

# Deploy with your customizations
./ztc setup
```

## Comparison with Interactive Mode

| Feature | prepare-auto | prepare (interactive) |
|---------|-------------|---------------------|
| **Speed** | ⚡ Instant | 🐌 2-3 minutes |
| **Customization** | ❌ Template only | ✅ Full control |
| **CI/CD Ready** | ✅ Yes | ❌ No |
| **Learning** | ❌ No guidance | ✅ Educational |
| **Docker Friendly** | ✅ Works in containers | ⚠️ Needs TTY |

## Integration Examples

**GitHub Actions:**
```yaml
- name: Setup ZTC
  run: ./ztc prepare-auto
```

**Docker/CI:**
```bash
docker run --rm -v $(pwd):/workspace ztc:latest prepare-auto
```

**Makefile automation:**
```bash
.PHONY: deploy-cluster
deploy-cluster:
    make prepare-auto
    make setup
```

The prepare-auto command ensures ZTC can be deployed reliably in any environment while maintaining the same professional cluster configuration that powers production homelabs.