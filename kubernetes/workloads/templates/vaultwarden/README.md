# Vaultwarden Password Manager

Vaultwarden is a self-hosted password manager compatible with Bitwarden clients. This workload template provides professional-grade credential management for users who want advanced password manager features.

## Quick Deploy

```bash
make deploy-vaultwarden
```

## Features

- 🔐 **Professional password management** with Bitwarden client compatibility
- 📱 **Mobile app support** via official Bitwarden apps
- 🌐 **Browser integration** with auto-fill and secure sharing
- 👥 **Multi-user support** for families and teams
- 📊 **Audit trail** and security reporting
- 🔄 **Sync across devices** with official Bitwarden ecosystem

## Access

After deployment:
- **Web UI**: http://vault.homelab.lan
- **Mobile Apps**: Use official Bitwarden apps, configure server URL
- **Browser Extensions**: Use Bitwarden extension, configure server URL

## Initial Setup

1. Navigate to http://vault.homelab.lan
2. Create your first account (email format required)
3. Configure organizations and collections as needed
4. Optionally disable signups via admin panel

## Configuration Options

### Basic Deployment
```bash
make deploy-vaultwarden
```

### Custom Configuration
```bash
# Custom storage size
make deploy-vaultwarden STORAGE_SIZE=10Gi

# Custom hostname
make deploy-vaultwarden HOSTNAME=passwords.homelab.lan

# Use local storage for performance
make deploy-vaultwarden STORAGE_CLASS=local-path

# Specific image version
make deploy-vaultwarden IMAGE_TAG=1.32.0

# With admin token for API access
make deploy-vaultwarden ADMIN_TOKEN=your-secure-admin-token
```

## vs. ZTC Built-in Credential Management

| Feature | ZTC Built-in (Sealed Secrets) | Vaultwarden |
|---------|-------------------------------|-------------|
| **Security** | ✅ Enterprise-grade encryption | ✅ Enterprise-grade encryption |
| **CLI Access** | ✅ `make show-credentials` | ⚠️ API or CLI tools needed |
| **Zero Touch** | ✅ Automatic setup | ❌ Manual account creation |
| **Browser Integration** | ❌ No auto-fill | ✅ Full browser integration |
| **Mobile Access** | ❌ CLI only | ✅ Native mobile apps |
| **Team Sharing** | ❌ Not designed for sharing | ✅ Organizations and sharing |
| **Complexity** | ✅ Simple, no UI needed | ⚠️ Additional service to maintain |

## When to Use Vaultwarden

Choose Vaultwarden if you need:
- Browser auto-fill integration
- Mobile device access to credentials  
- Family/team credential sharing
- Professional password manager workflow
- Integration with Bitwarden ecosystem

Stick with ZTC built-in credentials if you:
- Only need system administrator access
- Prefer CLI-based credential management
- Want zero maintenance overhead
- Don't need browser/mobile integration

## Resource Usage

- **Memory**: 64Mi request, 256Mi limit
- **CPU**: 50m request, 200m limit  
- **Storage**: 5Gi (configurable)
- **Network**: HTTP only (HTTPS requires cert-manager)

## Security Notes

- **Signups**: Initially enabled for setup, consider disabling after account creation
- **Admin Token**: Optional but recommended for API access and automation
- **HTTPS**: Consider enabling TLS via cert-manager for production use
- **Backup**: Data stored on persistent volume, included in cluster backups

## Troubleshooting

### Browser HTTPS Requirement
Modern browsers require HTTPS for Vaultwarden's Web Crypto API:

```bash
# Option 1: Port forward to localhost (bypasses HTTPS requirement)
kubectl port-forward -n vaultwarden svc/vaultwarden 8082:80
# Then access: http://localhost:8082

# Option 2: Use Bitwarden mobile/desktop apps (work with HTTP)
# Configure server URL: http://vault.homelab.lan

# Option 3: Enable TLS via cert-manager (recommended for production)
# See ZTC documentation for TLS setup
```

### Cannot Create Account
- Ensure you use email format: `user@domain.com` (not just username)
- Check that signups are enabled (default: true)
- Verify Vaultwarden is accessible via ingress

### Pod Won't Start
- Check storage class availability: `kubectl get storageclass`
- Verify persistent volume claim: `kubectl get pvc -n vaultwarden`
- Check pod logs: `kubectl logs -n vaultwarden deployment/vaultwarden`

## Uninstall

```bash
make undeploy-workload WORKLOAD=vaultwarden
```

**Note**: This removes the application but preserves the persistent volume. To completely remove data, also delete the PVC:
```bash
kubectl delete pvc vaultwarden-data -n vaultwarden
```