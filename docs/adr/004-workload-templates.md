# ADR-004: Essential Workload Templates

**Status:** Accepted

**Date:** 2025-07-02

**Supersedes:** None (extends ADR-003)

## Context and Problem Statement

With ADR-003 implementing private Git hosting via Gitea, users can now deploy private workloads using GitOps. However, the current process requires users to manually create Kubernetes manifests, understand YAML syntax, configure ingress, set up persistent storage, and manage ArgoCD applications.

This manual approach contradicts ZTC's core philosophy of "Zero Touch" automation and creates barriers for users who want to quickly deploy common homelab services like n8n, Grafana, or PostgreSQL.

### Current User Experience Pain Points

**Manual Workload Deployment Process:**
1. Access Gitea web UI and create repository
2. Clone repository locally
3. Create directory structure for applications
4. Write Kubernetes YAML manifests (deployment, service, ingress, PVC)
5. Configure resource limits, storage classes, and networking
6. Commit and push to private repository  
7. Create ArgoCD Application manifest
8. Apply ArgoCD configuration and wait for sync

**Problems with Current Approach:**
- **Complexity**: Requires Kubernetes expertise and YAML knowledge
- **Error-prone**: Manual YAML creation leads to syntax errors and misconfigurations
- **Time-consuming**: 15-30 minutes per workload for experienced users
- **Inconsistent**: No standardization of naming, resource limits, or configurations
- **Violates ZTC Principles**: Manual processes contradict "zero-touch" automation

## Decision Drivers

- **Simplicity**: Align with ZTC's core value of hiding complexity behind simple interfaces
- **Speed**: Enable rapid deployment of common homelab services
- **Consistency**: Standardize workload configurations and best practices
- **Self-Sufficiency**: No external dependencies beyond ZTC repository
- **Extensibility**: Foundation for future template expansion
- **Quality**: Curated, tested configurations that work reliably

## Decision

We will implement **Essential Workload Templates** as a built-in ZTC feature, providing pre-configured Kubernetes manifests for common homelab services accessible via simple `make` commands.

### Selected Essential Templates

Based on homelab community preferences (r/homelab, r/selfhosted) and practical deployment considerations, we will provide these 5 core templates:

1. **n8n** - Workflow automation platform for integrating homelab services
2. **Uptime Kuma** - Beautiful service monitoring and status pages  
3. **Homepage** - Modern dashboard for organizing all homelab services
4. **Vaultwarden** - Self-hosted Bitwarden-compatible password manager
5. **Code Server** - VS Code development environment accessible via browser

**Selection Criteria:**
- **High community demand**: All appear consistently in "essential homelab services" discussions
- **Immediate value**: Provide practical functionality from day one of deployment
- **Diverse use cases**: Cover automation, monitoring, organization, security, and development
- **Resource appropriate**: Lightweight enough for mini PC homelab hardware
- **Template friendly**: Services with straightforward configuration and deployment patterns

### Template Location and Structure

Templates will be stored in the ZTC repository at:
```
kubernetes/workloads/templates/
├── README.md                    # Template documentation
├── n8n/                        # Workflow automation platform
│   ├── template.yaml           # Template metadata and configuration
│   ├── deployment.yaml         # Kubernetes deployment
│   ├── service.yaml            # Service definition
│   ├── ingress.yaml            # Traefik ingress configuration
│   └── pvc.yaml                # Persistent volume claim
├── uptime-kuma/                # Service monitoring and status page
├── homepage/                   # Modern service dashboard
├── vaultwarden/                # Self-hosted password manager
└── code-server/                # VS Code development environment
```

### Template-to-Deployment Automation

Users will deploy workloads via simple Makefile targets:
```bash
# Zero-configuration deployment with sensible defaults
make deploy-n8n            # Workflow automation platform
make deploy-uptime-kuma    # Service monitoring and status page
make deploy-homepage       # Modern service dashboard
make deploy-vaultwarden    # Self-hosted password manager
make deploy-code-server    # VS Code development environment

# Check deployment status
make list-workloads
make workload-status WORKLOAD=n8n
```

### Template Processing Pipeline

1. **Template Selection**: User runs `make deploy-<service>`
2. **Configuration Generation**: Apply defaults and user overrides
3. **Repository Management**: Automatically create/update private Git repository
4. **Manifest Creation**: Generate Kubernetes YAML from templates
5. **Git Operations**: Commit and push to private repository
6. **ArgoCD Integration**: Create/update ArgoCD Application
7. **Deployment Monitoring**: Wait for successful deployment and report status

## Implementation Strategy

### Phase 1: Core Infrastructure (Week 1)

**1.1 Template System Architecture**
```bash
# New directory structure
kubernetes/workloads/
├── templates/           # Template definitions
├── lib/                # Template processing scripts
│   ├── template-engine.sh
│   ├── deploy-workload.sh
│   └── workload-manager.sh
└── examples/           # Generated example configurations
```

**1.2 Template Processing Engine**
```bash
# provisioning/lib/template-engine.sh
#!/bin/bash
# Core template processing functionality

process_template() {
    local template_name="$1"
    local template_dir="kubernetes/workloads/templates/$template_name"
    local output_dir="/tmp/workload-$template_name"
    local template_config="$template_dir/template.yaml"
    
    # Check dependencies
    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: yq is required for template processing"
        exit 1
    fi
    
    # Parse template configuration using yq
    export WORKLOAD_NAME=$(yq e '.metadata.name' "$template_config")
    export WORKLOAD_NAMESPACE=$(yq e '.metadata.namespace' "$template_config")
    export STORAGE_SIZE=$(yq e '.defaults.storage_size' "$template_config")
    export STORAGE_CLASS=$(yq e '.defaults.storage_class' "$template_config")
    export HOSTNAME=$(yq e '.defaults.hostname' "$template_config")
    export MEMORY_REQUEST=$(yq e '.defaults.resources.requests.memory' "$template_config")
    export MEMORY_LIMIT=$(yq e '.defaults.resources.limits.memory' "$template_config")
    export CPU_REQUEST=$(yq e '.defaults.resources.requests.cpu' "$template_config")
    export CPU_LIMIT=$(yq e '.defaults.resources.limits.cpu' "$template_config")
    
    # Apply variable substitution to Kubernetes manifests
    mkdir -p "$output_dir"
    for file in "$template_dir"/*.yaml; do
        if [[ "$(basename "$file")" != "template.yaml" ]]; then
            envsubst < "$file" > "$output_dir/$(basename "$file")"
        fi
    done
}
```

**1.3 Makefile Integration**
```makefile
##@ Private Workloads

deploy-n8n: ## Deploy n8n workflow automation platform
	@./provisioning/lib/deploy-workload.sh n8n

deploy-uptime-kuma: ## Deploy Uptime Kuma service monitoring
	@./provisioning/lib/deploy-workload.sh uptime-kuma

deploy-homepage: ## Deploy Homepage service dashboard
	@./provisioning/lib/deploy-workload.sh homepage

deploy-vaultwarden: ## Deploy Vaultwarden password manager
	@./provisioning/lib/deploy-workload.sh vaultwarden

deploy-code-server: ## Deploy Code Server development environment
	@./provisioning/lib/deploy-workload.sh code-server

list-workloads: ## List all deployed workloads
	@kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads

workload-status: ## Check specific workload status (usage: make workload-status WORKLOAD=n8n)
	@if [ -z "$(WORKLOAD)" ]; then \
		echo "$(RED)❌ Usage: make workload-status WORKLOAD=<name>$(RESET)"; \
		exit 1; \
	fi
	@kubectl get pods,svc,ingress -n $(WORKLOAD) 2>/dev/null || echo "$(YELLOW)⚠️  Workload $(WORKLOAD) not found$(RESET)"
```

### Phase 2: Essential Templates (Week 2)

**2.1 n8n Template - Workflow Automation**
```yaml
# kubernetes/workloads/templates/n8n/template.yaml
metadata:
  name: n8n
  description: "Workflow automation platform for homelab integrations"
  namespace: n8n
  category: automation
  
defaults:
  storage_size: "5Gi"
  storage_class: "local-path"
  hostname: "n8n.homelab.local"
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi" 
      cpu: "300m"
```

**2.2 Uptime Kuma Template - Service Monitoring**
```yaml
# kubernetes/workloads/templates/uptime-kuma/template.yaml
metadata:
  name: uptime-kuma
  description: "Beautiful service monitoring and status page"
  namespace: uptime-kuma
  category: monitoring
  
defaults:
  storage_size: "1Gi"
  storage_class: "local-path"
  hostname: "status.homelab.local"
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "200m"
```

**2.3 Homepage Template - Service Dashboard**
```yaml
# kubernetes/workloads/templates/homepage/template.yaml
metadata:
  name: homepage
  description: "Modern dashboard for organizing homelab services"
  namespace: homepage
  category: dashboard
  
defaults:
  storage_size: "500Mi"
  storage_class: "local-path"
  hostname: "home.homelab.local"
  resources:
    requests:
      memory: "32Mi"
      cpu: "25m"
    limits:
      memory: "64Mi"
      cpu: "100m"
```

**2.4 Vaultwarden Template - Password Manager**
```yaml
# kubernetes/workloads/templates/vaultwarden/template.yaml
metadata:
  name: vaultwarden
  description: "Self-hosted Bitwarden-compatible password manager"
  namespace: vaultwarden
  category: security
  
defaults:
  storage_size: "2Gi"
  storage_class: "nfs-client"  # Shared storage for family access
  hostname: "vault.homelab.local"
  admin_token: "auto-generated"
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "200m"
```

**2.5 Code Server Template - Development Environment**
```yaml
# kubernetes/workloads/templates/code-server/template.yaml
metadata:
  name: code-server
  description: "VS Code development environment in browser"
  namespace: code-server
  category: development
  
defaults:
  storage_size: "10Gi"
  storage_class: "nfs-client"  # Persistent workspace across devices
  hostname: "code.homelab.local"
  password: "auto-generated"
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

### Phase 3: Advanced Features (Week 3)

**3.1 Template Validation**
```bash
# Template testing and validation
make validate-templates    # Lint all templates
make test-template n8n     # Deploy template to test namespace
```

**3.2 Workload Management**
```bash
# Workload lifecycle management
make remove-workload n8n   # Remove workload and cleanup
make update-workload n8n   # Update workload from template
make backup-workload n8n   # Backup workload data
```

**3.3 Template Customization**
```bash
# Override template defaults
make deploy-n8n STORAGE_SIZE=10Gi HOSTNAME=automation.homelab.local
```

## User Experience Transformation

### Before: Manual YAML Creation
```bash
# 8-step manual process (15-30 minutes)
1. Access Gitea web UI
2. Create repository
3. Clone locally  
4. Write 4-5 YAML files
5. Configure resources, networking, storage
6. Commit and push
7. Create ArgoCD Application
8. Debug deployment issues
```

### After: One-Command Deployment
```bash
# Single command (2-3 minutes each)
make deploy-n8n          # Workflow automation
make deploy-uptime-kuma   # Service monitoring  
make deploy-homepage      # Service dashboard
make deploy-vaultwarden   # Password manager
make deploy-code-server   # Development environment

# Example output for n8n:
# 🔄 Deploying n8n workflow automation...
# ✅ Repository ztc-admin/workloads updated
# ✅ n8n manifests generated and committed
# ✅ ArgoCD application created
# 🔄 Waiting for deployment...
# ✅ n8n deployed successfully!
# 
# 🌐 Access: http://n8n.homelab.local
# 📊 Status: kubectl get pods -n n8n

# Complete homelab platform deployed in ~15 minutes!
```

## Template Standards and Best Practices

### Security Requirements
- **Non-root containers**: All templates use non-root security contexts
- **Resource limits**: CPU and memory limits defined for all workloads
- **Network policies**: Isolated namespaces with appropriate ingress/egress rules
- **Secret management**: Auto-generated secrets using Kubernetes native mechanisms

### Storage Configuration
- **Local-path**: Fast storage for single-pod applications (Grafana, n8n)
- **NFS-client**: Shared storage for databases and multi-pod applications
- **Size guidelines**: Conservative defaults with easy override options

### Networking Standards
- **Ingress**: Standardized Traefik ingress with consistent hostname patterns
- **Service discovery**: ClusterIP services with DNS-based internal communication
- **Port conventions**: Standard ports for each service type

### Resource Management
- **Homelab-optimized**: Resource requests/limits appropriate for mini PC hardware
- **QoS classes**: Burstable QoS for optimal resource utilization
- **Scaling**: Prepared for horizontal scaling when needed

## Consequences

### Positive Outcomes

#### For ZTC Users
- **Dramatic simplification**: Deploy complex workloads with single commands
- **Faster time-to-value**: From 30 minutes to 3 minutes per workload
- **Reduced errors**: Pre-tested, validated configurations eliminate common mistakes
- **Consistent experience**: Standardized naming, networking, and resource patterns
- **Lower learning curve**: No Kubernetes YAML expertise required

#### For ZTC Project
- **Stronger value proposition**: Complete platform experience beyond just infrastructure
- **User retention**: Users get immediate value from deployed applications
- **Community foundation**: Template system prepared for future community contributions
- **Documentation benefits**: Living examples of best practices and configurations

### Implementation Challenges

#### Maintenance Overhead
- **Template updates**: Keep templates current with upstream application changes
- **Testing requirements**: Validate templates across different ZTC configurations
- **Version compatibility**: Ensure templates work with target Kubernetes versions
- **Security maintenance**: Regular security reviews and updates

#### Template Quality Assurance
- **Resource sizing**: Balance between conservative defaults and performance
- **Configuration completeness**: Ensure templates include necessary configuration options
- **Error handling**: Graceful handling of deployment failures and rollbacks
- **Documentation**: Comprehensive template documentation and troubleshooting guides

#### Scope Management
- **Template selection**: Choose essential templates without feature creep
- **Customization balance**: Provide flexibility without excessive complexity
- **Maintenance boundaries**: Clear guidelines for what templates ZTC will maintain

### Risk Mitigation

#### Template Reliability
- **Automated testing**: CI/CD pipeline tests all templates against ZTC clusters
- **Version pinning**: Use specific application versions for predictable behavior
- **Rollback capability**: Easy removal and restoration of workloads
- **Monitoring integration**: Templates include basic health checks and monitoring

#### User Expectations
- **Clear documentation**: Explain template scope, limitations, and customization options
- **Migration path**: Easy transition from templates to custom configurations
- **Support boundaries**: Clear guidance on when users need custom solutions

## Success Metrics

### Quantitative Measures
- **Deployment time**: Target <5 minutes from command to accessible application
- **Error rate**: <5% deployment failures for essential templates
- **Adoption rate**: >60% of ZTC users deploy at least one workload template
- **User satisfaction**: >80% positive feedback on workload template experience

### Qualitative Indicators
- **User feedback**: Simplified workload deployment experience
- **Community engagement**: Requests for additional templates
- **ZTC positioning**: Recognition as complete homelab platform, not just infrastructure
- **Documentation quality**: Self-service capability for workload deployment

## Alternatives Considered

### Alternative A: External Template Repository
**Description**: Maintain templates in separate ztc-templates repository
- **Pros**: Clean separation, independent updates, community contributions
- **Cons**: External dependency, version synchronization complexity, bootstrap problems
- **Verdict**: Rejected for initial implementation - adds unnecessary complexity

### Alternative B: Interactive Template Generator
**Description**: Wizard-based template customization and generation
- **Pros**: Maximum flexibility, guided configuration process
- **Cons**: Complex implementation, slower deployment, analysis paralysis
- **Verdict**: Future consideration - focus on simple commands first

### Alternative C: Helm Chart Integration
**Description**: Use existing Helm charts instead of custom templates
- **Pros**: Leverage existing ecosystem, comprehensive configurations
- **Cons**: Complex dependency management, external registry requirements, harder to customize
- **Verdict**: Rejected - conflicts with ZTC self-sufficiency principles

### Alternative D: No Templates (Status Quo)
**Description**: Continue with manual workload deployment process
- **Pros**: No additional development effort, maximum flexibility
- **Cons**: Poor user experience, violates ZTC principles, limits adoption
- **Verdict**: Rejected - fails to address core user pain points

## Implementation Roadmap

**Note**: Timeline assumes single developer with ZTC familiarity. Add 50% buffer for thorough testing and documentation.

### Dependencies
- **yq**: YAML processor for template parsing (will auto-install if missing)
- **envsubst**: Variable substitution (standard on most Linux distributions)
- **Existing ZTC components**: Gitea (ADR-003), ArgoCD, SealedSecrets (ADR-001)

### Week 1: Foundation
**Goal**: Template processing infrastructure and Makefile integration

**Deliverables**:
- Template directory structure (`kubernetes/workloads/templates/`)
- Template processing engine with yq-based YAML parsing (`provisioning/lib/template-engine.sh`)
- Workload deployment script (`provisioning/lib/deploy-workload.sh`)
- Makefile targets for essential workloads
- Dependency checking and auto-installation

**Acceptance Criteria**:
- Template processing pipeline functional with proper YAML parsing
- Basic deployment automation working end-to-end
- Error handling and user feedback implemented
- yq dependency resolved automatically

### Week 2: Essential Templates
**Goal**: Create and test core homelab workload templates

**Deliverables**:
- n8n template (workflow automation platform)
- Uptime Kuma template (service monitoring and status page)
- Homepage template (modern service dashboard)
- Vaultwarden template (self-hosted password manager)
- Code Server template (VS Code development environment)

**Acceptance Criteria**:
- All templates deploy successfully on homelab hardware
- Ingress and networking configured properly with .homelab.local domains
- Persistent storage working correctly (local-path and nfs-client)
- Resource limits optimized for mini PC environments
- Auto-generated secrets and credentials working securely

### Week 3: Polish and Documentation
**Goal**: Production-ready template system with comprehensive documentation

**Deliverables**:
- Template validation and testing scripts
- Workload management commands (remove, update, status)
- Comprehensive documentation in CLAUDE.md
- Error handling and troubleshooting guides

**Acceptance Criteria**:
- Complete end-to-end testing
- User documentation covers all scenarios
- Error messages provide actionable guidance
- Template system ready for production use

## Future Considerations

### Template Ecosystem Evolution
- **Community templates**: External template repository and contribution process
- **Template marketplace**: Discovery and rating system for community templates
- **Template versioning**: Multiple versions and compatibility matrix
- **Template composition**: Combining multiple templates for complex applications

### Advanced Features
- **Template inheritance**: Base templates with specialized derivatives
- **Dynamic configuration**: Runtime configuration changes without redeployment
- **Multi-cluster templates**: Templates that span multiple ZTC clusters
- **Integration templates**: Pre-configured integrations between services

### Enterprise Extensions
- **Template governance**: Approval workflows and security scanning
- **Custom template registries**: Private template repositories for organizations
- **Template analytics**: Usage metrics and optimization recommendations
- **SLA monitoring**: Template-specific performance and availability metrics

## Conclusion

ADR-004 represents a natural evolution of ZTC's capabilities, extending the "Zero Touch" philosophy from infrastructure deployment to application deployment. By providing essential workload templates, ZTC transforms from an infrastructure automation tool into a complete homelab platform.

This approach maintains ZTC's core principles:
- **Simplicity**: Complex workload deployment reduced to single commands
- **Self-sufficiency**: All templates included in ZTC repository
- **Reliability**: Curated, tested configurations with consistent behavior
- **User-friendly**: No Kubernetes expertise required for common deployments

The template system provides immediate value through essential homelab services while establishing the foundation for future community-driven template ecosystems. Users get a complete platform experience that delivers working applications within minutes of infrastructure deployment.

**Next Steps**:
1. Implement template processing infrastructure
2. Create essential workload templates (n8n, Uptime Kuma, Homepage, Vaultwarden, Code Server)
3. Integrate with existing Gitea and ArgoCD workflows
4. Comprehensive testing and documentation
5. Community feedback and iteration

This architectural decision positions ZTC as the leading solution for complete homelab automation, addressing the full lifecycle from infrastructure to applications while maintaining the simplicity and reliability that defines the ZTC experience.