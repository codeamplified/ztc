# Zero Touch Cluster Configuration Schema

This directory contains the JSON Schema for Zero Touch Cluster configuration files.

## Files

- `cluster-schema.json` - Complete JSON Schema for `cluster.yaml` configuration
- `README.md` - This documentation file

## Schema Features

### 🔍 **Validation**
- Complete structure validation
- Type checking for all fields
- Pattern validation for IPs, domains, resource specifications
- Enum validation for predefined values
- Required field enforcement

### 📝 **IDE Support**
- Autocompletion in VS Code, IntelliJ, and other schema-aware editors
- Inline documentation and examples
- Real-time validation as you edit
- Property suggestions and value completion

### 🛠️ **Tool Integration**
- CI/CD pipeline validation
- Command-line validation tools
- Integration with configuration management tools

## Usage

### IDE Integration

Add this header to your `cluster.yaml` file for IDE support:

```yaml
# yaml-language-server: $schema=./schema/cluster-schema.json
```

### Command Line Validation

```bash
# Comprehensive validation (requires ajv-cli)
./scripts/lib/validate-schema.sh validate cluster.yaml

# Basic validation (yq only)
./scripts/lib/validate-schema.sh basic cluster.yaml

# Show schema information
./scripts/lib/validate-schema.sh info

# Via Makefile
make validate-schema
```

### Installing ajv-cli for Full Validation

```bash
# Install globally
npm install -g ajv-cli

# Verify installation
ajv --help
```

## Schema Structure

The schema defines the complete structure for Zero Touch Cluster configurations:

```json
{
  "cluster": {
    "name": "string (pattern: ^[a-z0-9-]+$)",
    "description": "string",
    "version": "string (pattern: ^\\d+\\.\\d+\\.\\d+$)"
  },
  "network": {
    "subnet": "string (CIDR format)",
    "dns": {
      "enabled": "boolean",
      "server_ip": "string (IPv4)",
      "domain": "string (domain format)"
    }
  },
  "nodes": {
    "ssh": { "key_path": "string", "username": "string" },
    "cluster_nodes": { /* node definitions */ },
    "storage_node": { /* storage node definitions */ }
  },
  "storage": {
    "strategy": "enum [local-only, hybrid, longhorn, nfs-only]",
    "default_class": "enum [local-path, nfs-client, longhorn]",
    /* storage configuration */
  },
  "components": {
    "monitoring": { "enabled": "boolean" },
    "gitea": { "enabled": "boolean" },
    "homepage": { "enabled": "boolean" }
    /* component configurations */
  },
  "workloads": {
    "auto_deploy_bundles": "array of enum [starter, monitoring, ...]"
  }
}
```

## Validation Features

### Pattern Validation
- **IP Addresses**: IPv4 format validation
- **CIDR Notation**: Network subnet validation
- **Domain Names**: DNS domain format validation
- **Resource Specs**: Kubernetes resource format (e.g., "4Gi", "200m")
- **Node Names**: Kubernetes-compatible naming

### Enum Validation
- **Storage Strategies**: `local-only`, `hybrid`, `longhorn`, `nfs-only`
- **Node Roles**: `master`, `worker`, `storage`
- **Workload Bundles**: `starter`, `monitoring`, `productivity`, `security`, `development`
- **Reclaim Policies**: `Delete`, `Retain`

### Range Validation
- **Cluster Name**: 3-32 characters
- **Password Length**: 8-64 characters
- **Timeout Minutes**: 5-60 minutes
- **Longhorn Replicas**: 1-10 replicas

## Examples

### Valid Configuration Snippets

```yaml
cluster:
  name: "ztc-homelab"           # ✅ Valid: lowercase, hyphens
  name: "Production_Cluster"    # ❌ Invalid: uppercase, underscore

network:
  subnet: "192.168.50.0/24"     # ✅ Valid: CIDR format
  subnet: "192.168.50"          # ❌ Invalid: missing subnet mask

storage:
  strategy: "hybrid"            # ✅ Valid: enum value
  strategy: "distributed"       # ❌ Invalid: not in enum

workloads:
  auto_deploy_bundles:          # ✅ Valid: known bundles
    - "starter"
    - "monitoring"
  auto_deploy_bundles:          # ❌ Invalid: unknown bundle
    - "unknown-bundle"
```

## Extending the Schema

To add new configuration options:

1. **Update Schema**: Add new properties to `cluster-schema.json`
2. **Add Validation**: Include pattern/enum validation as needed
3. **Add Examples**: Provide example values and descriptions
4. **Update Documentation**: Update this README and main docs
5. **Test**: Validate against existing configurations

### Example Extension

```json
{
  "properties": {
    "my_new_section": {
      "type": "object",
      "description": "My new configuration section",
      "properties": {
        "enabled": {
          "type": "boolean",
          "default": false
        },
        "my_option": {
          "type": "string",
          "enum": ["option1", "option2"],
          "description": "My configuration option"
        }
      }
    }
  }
}
```

## Schema Maintenance

The schema should be updated when:
- New configuration options are added
- Validation rules change
- New workload bundles are introduced
- Field types or formats change

Always test schema changes against existing configuration files to ensure backward compatibility.

## Troubleshooting

### Common Issues

1. **Schema Not Found**: Ensure the schema path in the YAML header is correct
2. **ajv-cli Errors**: Install ajv-cli or use basic validation
3. **Pattern Validation**: Check format examples in schema descriptions
4. **IDE Not Showing Validation**: Restart IDE or check YAML language server setup

### Debug Commands

```bash
# Test schema syntax
cat schema/cluster-schema.json | jq '.'

# Validate specific field
yq eval '.cluster.name' cluster.yaml

# Show schema version
jq -r '."$id"' schema/cluster-schema.json
```

---

For more information, see the main [Configuration System Documentation](../docs/configuration-system.md).