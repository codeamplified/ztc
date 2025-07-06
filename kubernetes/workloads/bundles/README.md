# ZTC Workload Bundles

The ZTC Bundle System groups related workloads into convenient deployment packages, making it easier to get started with your homelab. Instead of deploying services one by one, you can deploy complete stacks with a single command.

## Quick Start

```bash
# Deploy a complete bundle with one command
make deploy-bundle-starter      # Essential homelab services
make deploy-bundle-monitoring   # Complete monitoring solution
make deploy-bundle-productivity # Development and automation tools
make deploy-bundle-security     # Password management and security

# List all available bundles
make list-bundles

# Check deployment status
make bundle-status
```

## Available Bundles

### 🚀 Starter Bundle
**Perfect for**: First-time ZTC users, learning Kubernetes, minimal resource usage

**Services**: Homepage dashboard + Uptime Kuma monitoring  
**Resources**: 192Mi RAM, 75m CPU, 2Gi storage  
**Command**: `make deploy-bundle-starter`

**What you get**:
- Beautiful service dashboard at `http://home.homelab.lan`
- Service health monitoring at `http://status.homelab.lan`
- Minimal resource usage perfect for learning
- Great foundation before adding more services

### 📊 Monitoring Bundle
**Perfect for**: Homelab operators wanting comprehensive monitoring

**Services**: Uptime Kuma monitoring + Homepage dashboard  
**Resources**: 192Mi RAM, 100m CPU, 3Gi storage  
**Command**: `make deploy-bundle-monitoring`

**What you get**:
- 24/7 monitoring of all homelab services
- Status pages for communicating availability
- Visual dashboard for family and guests
- Persistent configuration that survives restarts

### 🛠️ Productivity Bundle
**Perfect for**: Developers, DevOps engineers, automation enthusiasts

**Services**: Code Server + n8n automation platform  
**Resources**: 1Gi RAM, 300m CPU, 15Gi storage  
**Command**: `make deploy-bundle-productivity`

**What you get**:
- Full VS Code development environment at `http://code.homelab.lan`
- Workflow automation platform at `http://automation.homelab.lan`
- Browser-based development accessible from any device
- Visual workflow builder requiring no coding experience

### 🔒 Security Bundle
**Perfect for**: Security-conscious users prioritizing credential management

**Services**: Vaultwarden password manager  
**Resources**: 128Mi RAM, 50m CPU, 5Gi storage  
**Command**: `make deploy-bundle-security`

**What you get**:
- Professional password manager at `http://vault.homelab.lan`
- Browser extensions for auto-fill capabilities
- Compatible with all Bitwarden clients
- Secure sharing for family members

## Bundle System Benefits

### Traditional Approach (8+ steps, 15-30 minutes)
1. Research which services you need
2. Deploy each service individually
3. Configure networking and storage
4. Set up monitoring for each service
5. Organize service access
6. Remember all the URLs and credentials
7. Troubleshoot individual deployment issues
8. Configure integrations between services

### Bundle Approach (1 command, 2-3 minutes)
```bash
make deploy-bundle-starter
```
✅ **Done!** - Complete working stack with monitoring and dashboard

## Individual vs Bundle Deployment

**You can still deploy services individually:**
```bash
make deploy-homepage        # Just the dashboard
make deploy-uptime-kuma     # Just monitoring
make deploy-n8n             # Just automation
make deploy-code-server     # Just development environment
make deploy-vaultwarden     # Just password manager
```

**Or deploy complete stacks:**
```bash
make deploy-bundle-starter      # Homepage + Uptime Kuma
make deploy-bundle-monitoring   # Uptime Kuma + Homepage (monitoring-focused)
make deploy-bundle-productivity # Code Server + n8n
make deploy-bundle-security     # Vaultwarden
```

## Bundle Architecture

Each bundle includes:
- **metadata.yaml**: Bundle description, category, and tags
- **workloads**: List of services with deployment priority
- **overrides**: Custom configuration for each service
- **resource_requirements**: Total resource usage estimates
- **documentation**: Access URLs and setup instructions

## Advanced Usage

### Customizing Bundle Deployments

Bundles use sensible defaults but you can still customize individual services:

```bash
# Deploy bundle with custom overrides
OVERRIDE_STORAGE_CLASS=longhorn make deploy-bundle-security
OVERRIDE_MEMORY_LIMIT=256Mi make deploy-bundle-starter

# Deploy individual services with custom settings
make deploy-homepage HOSTNAME=dashboard.homelab.lan
make deploy-n8n STORAGE_SIZE=20Gi IMAGE_TAG=1.64.0
```

### Bundle Status and Management

```bash
# Check which bundles are deployed
make bundle-status

# Check specific workload status
make workload-status WORKLOAD=homepage
make workload-status WORKLOAD=n8n

# List all deployed workloads
make list-workloads

# Remove specific workload
make undeploy-workload WORKLOAD=homepage
```

## Deployment Order

Services within bundles are deployed in priority order:
1. **Priority 1**: Core services (dashboards, essential tools)
2. **Priority 2**: Supporting services (monitoring, automation)
3. **Priority 3**: Optional services (additional tools)

This ensures dependencies are met and critical services start first.

## Resource Planning

### Small Homelab (2-4 nodes, 4-8GB RAM total)
- ✅ **Starter Bundle** - Essential services with minimal resources
- ✅ **Security Bundle** - Add password management
- ⚠️ **Monitoring Bundle** - Use if you have adequate monitoring needs
- ❌ **Productivity Bundle** - May be resource-intensive

### Medium Homelab (4-6 nodes, 8-16GB RAM total)
- ✅ **All Bundles** - Deploy any combination
- ✅ **Multiple Bundles** - Starter + Security + Monitoring
- ✅ **Productivity Bundle** - Full development environment

### Large Homelab (6+ nodes, 16GB+ RAM total)
- ✅ **All Bundles** - Deploy all bundles simultaneously
- ✅ **Custom Overrides** - Scale services as needed
- ✅ **Advanced Storage** - Use Longhorn for critical data

## Troubleshooting

### Bundle Deployment Issues

**Problem**: Bundle deployment fails with "workload not found"
```bash
# Check if templates exist
ls kubernetes/workloads/templates/
# Should show: n8n, uptime-kuma, homepage, vaultwarden, code-server
```

**Problem**: Services not accessible after deployment
```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check pod status
kubectl get pods -n <service-name>

# Check ingress configuration
kubectl get ingress -A
```

**Problem**: Resource constraints
```bash
# Check node resource usage
kubectl top nodes
kubectl top pods -A

# Scale down non-essential services
make undeploy-workload WORKLOAD=<service-name>
```

### Getting Help

```bash
# Show available commands
make help

# List bundle options
make list-bundles

# Check cluster status
make status

# Show bundle deployment status
make bundle-status
```

## Next Steps

1. **Start Simple**: Deploy the starter bundle to get familiar with the system
2. **Add Security**: Deploy the security bundle for credential management
3. **Expand Monitoring**: Deploy the monitoring bundle for comprehensive oversight
4. **Enable Development**: Deploy the productivity bundle for development work
5. **Customize**: Use individual service deployments for specific needs

## Integration with ZTC

Bundles integrate seamlessly with the ZTC ecosystem:
- **GitOps**: All services deployed via ArgoCD
- **Storage**: Automatic storage class selection
- **Networking**: Traefik ingress with homelab.lan domains
- **Secrets**: Sealed Secrets for secure configuration
- **Monitoring**: Prometheus scraping for system metrics

The bundle system builds on ZTC's "Zero Touch" philosophy - complex multi-service deployments reduced to single commands with sensible defaults and easy customization.