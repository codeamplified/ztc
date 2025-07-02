# ADR-003: Self-Hosted GitOps Development Platform

**Status:** Draft

**Date:** 2025-07-02

**Supersedes:** None (extends ADR-001 and ADR-002)

**Contributors:** Claude Code, ZTC Team

## Context

Zero Touch Cluster (ZTC) currently provides excellent infrastructure automation and secrets management (ADR-001, ADR-002), but faces a fundamental limitation in its GitOps approach: **external dependency on third-party Git providers** for user workloads.

### Current Architecture Limitations

The existing model requires users to:
1. Create external GitHub/GitLab accounts for private workloads
2. Manage SSH keys and authentication to external services
3. Rely on internet connectivity for GitOps operations
4. Handle complex repository access controls and permissions
5. Split their development workflow between local cluster and external Git services

### Market Gap Analysis

**Educational/Learning Environments:**
- Students learning Kubernetes need external Git accounts
- Corporate training environments require internet access for GitOps
- Homelab enthusiasts want fully self-contained development platforms

**Enterprise/Air-Gapped Scenarios:**
- Companies want complete control over their development pipeline
- Security-conscious organizations prefer no external dependencies
- Compliance requirements mandate on-premises source control

**Developer Experience Friction:**
- Context switching between local cluster and external Git providers
- Complex credential management across multiple services
- Limited offline development capabilities

### Opportunity: Platform as Code

Modern development increasingly favors **platform engineering** approaches where infrastructure provides complete development environments, not just compute resources. ZTC is positioned to evolve from "cluster automation" to "development platform automation."

## Decision

We will extend Zero Touch Cluster to become a **Self-Hosted GitOps Development Platform** by adding GitLab and container registry as system components, enabling completely self-contained development workflows.

### Architectural Vision

#### Core Platform Components (Infrastructure)
```
ZTC System Components (Open Source):
├── Kubernetes Cluster (k3s)
├── Storage (local-path + NFS)
├── Monitoring (Prometheus/Grafana)
├── Secrets Management (Sealed Secrets + Ansible Vault)
├── GitLab Community Edition (New)
├── Container Registry (Harbor/GitLab Registry) (New)
└── ArgoCD with User Management (Enhanced)
```

#### User Workload Components (Private)
```
Per-User Repositories (On-Cluster GitLab):
├── my-workloads.git
│   ├── apps/
│   │   ├── n8n/
│   │   ├── personal-dashboard/
│   │   └── data-pipeline/
│   └── argocd-applications/
└── my-infrastructure.git (optional)
    ├── terraform/
    └── ansible/
```

### Multi-Tenant GitOps Architecture

#### 1. **Infrastructure Layer (Shared)**
```yaml
# Deployed by ZTC maintainers via Helm
System Components:
  - GitLab: Source control for all user workloads
  - Harbor: Container registry for custom images  
  - ArgoCD: GitOps controller with RBAC
  - Monitoring: Observability for all workloads
  - Storage: Persistent data for GitLab/Harbor
```

#### 2. **User Layer (Isolated)**
```yaml
# Auto-created per user via GitLab integration
Per User:
  - GitLab Account: john@homelab.local
  - Kubernetes Namespaces: john-dev, john-prod
  - ArgoCD Applications: Auto-synced from user repos
  - RBAC: Restricted to user's namespaces only
  - Resource Quotas: CPU/memory limits per user
```

#### 3. **Workload Templates (Standardized)**
```yaml
# Provided by ZTC for quick start
Template Repositories:
  - webapp-template: React/Vue.js + Node.js API
  - python-api-template: FastAPI with PostgreSQL
  - ml-pipeline-template: Jupyter + MLflow
  - database-template: PostgreSQL with automated backups
  - monitoring-template: Custom Grafana dashboards
```

## Implementation Strategy

### Phase 1: GitLab Integration (Weeks 1-2)

**1.1 GitLab System Component**
```yaml
# kubernetes/system/gitlab/Chart.yaml
apiVersion: v2
name: gitlab-ce
version: 1.0.0
dependencies:
  - name: gitlab
    version: "7.7.0"
    repository: "https://charts.gitlab.io/"

# kubernetes/system/gitlab/values.yaml
gitlab:
  edition: ce  # Community Edition
  global:
    hosts:
      domain: homelab.local
      gitlab:
        name: gitlab.homelab.local
    ingress:
      enabled: true
      class: traefik
  
  # Use cluster storage
  postgresql:
    persistence:
      storageClass: "nfs-client"
  redis:
    persistence:
      storageClass: "local-path"
  gitaly:
    persistence:
      storageClass: "nfs-client"
      size: 50Gi
  
  # Integrated container registry
  registry:
    enabled: true
    ingress:
      enabled: true
      hosts: ["registry.homelab.local"]
```

**1.2 Enhanced Setup Wizard**
```bash
# provisioning/lib/setup-wizard.sh (enhanced)
setup_gitlab_integration() {
    echo "🦊 Configuring GitLab integration..."
    
    # Generate GitLab root password
    GITLAB_ROOT_PASSWORD=$(generate_secure_password)
    
    # Create GitLab admin token for ArgoCD integration
    GITLAB_ADMIN_TOKEN=$(generate_secure_password)
    
    # Create SealedSecret for GitLab credentials
    create_sealed_secret "gitlab-admin" "monitoring" \
        --from-literal=root-password="$GITLAB_ROOT_PASSWORD" \
        --from-literal=admin-token="$GITLAB_ADMIN_TOKEN"
}
```

**1.3 User Onboarding Automation**
```bash
# New Makefile target
create-user: ## Create new user with GitLab account and ArgoCD apps
	@echo "$(CYAN)Creating user environment...$(RESET)"
	@./scripts/create-user.sh $(USER) $(EMAIL)

# scripts/create-user.sh
#!/bin/bash
USER=$1
EMAIL=$2

# Create GitLab user account
gitlab_create_user() {
    curl -X POST "http://gitlab.homelab.local/api/v4/users" \
        --header "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
        --data "name=$USER" \
        --data "username=$USER" \
        --data "email=$EMAIL"
}

# Create user namespaces with RBAC
create_user_namespaces() {
    kubectl create namespace ${USER}-dev
    kubectl create namespace ${USER}-prod
    
    # Apply RBAC to restrict user to their namespaces
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: ${USER}-dev
  name: ${USER}-dev-admin
subjects:
- kind: User
  name: ${USER}@homelab.local
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
EOF
}

# Create ArgoCD Application template
create_argocd_application() {
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${USER}-workloads
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitlab.homelab.local/${USER}/workloads.git
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: ${USER}-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
}
```

### Phase 2: Container Registry Integration (Weeks 3-4)

**2.1 Harbor Registry Deployment**
```yaml
# kubernetes/system/harbor/values.yaml
harbor:
  expose:
    ingress:
      hosts:
        core: registry.homelab.local
  
  persistence:
    persistentVolumeClaim:
      registry:
        storageClass: "nfs-client"
        size: 100Gi
      database:
        storageClass: "local-path"
        size: 5Gi
  
  # Integration with GitLab
  core:
    configureUserSettings: |
      auth_mode = oidc_auth
      oidc_name = GitLab
      oidc_endpoint = https://gitlab.homelab.local
```

**2.2 CI/CD Pipeline Integration**
```yaml
# Template: .gitlab-ci.yml for user workloads
stages:
  - build
  - deploy

build:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t registry.homelab.local/john/my-app:$CI_COMMIT_SHA .
    - docker push registry.homelab.local/john/my-app:$CI_COMMIT_SHA
  only:
    - main

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/my-app app=registry.homelab.local/john/my-app:$CI_COMMIT_SHA -n john-dev
  only:
    - main
```

### Phase 3: Template Repository System (Weeks 5-6)

**3.1 Workload Templates**
```bash
# New directory structure
kubernetes/templates/
├── webapp-starter/
│   ├── README.md
│   ├── Dockerfile
│   ├── k8s/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── .gitlab-ci.yml
├── api-starter/
├── ml-pipeline/
└── database/
```

**3.2 Template Provisioning**
```bash
# New Makefile target
create-from-template: ## Create user workload from template
	@echo "$(CYAN)Available templates:$(RESET)"
	@ls kubernetes/templates/
	@echo "$(CYAN)Creating workload from template...$(RESET)"
	@./scripts/create-from-template.sh $(USER) $(TEMPLATE) $(WORKLOAD_NAME)

# scripts/create-from-template.sh
#!/bin/bash
USER=$1
TEMPLATE=$2
WORKLOAD_NAME=$3

# Create GitLab project from template
create_project_from_template() {
    # Copy template to new GitLab project
    gitlab_create_project "$USER" "$WORKLOAD_NAME" \
        --template="kubernetes/templates/$TEMPLATE"
    
    # Customize template for user
    sed -i "s/{{USER}}/$USER/g" "$TEMP_DIR/k8s/*.yaml"
    sed -i "s/{{WORKLOAD_NAME}}/$WORKLOAD_NAME/g" "$TEMP_DIR/k8s/*.yaml"
    
    # Initial commit to GitLab
    git_push_to_gitlab "$USER" "$WORKLOAD_NAME"
}
```

### Phase 4: Advanced Platform Features (Weeks 7-8)

**4.1 Multi-Environment Support**
```yaml
# ArgoCD ApplicationSet for automatic environment promotion
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: user-environments
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: dev
  - clusters:
      selector:
        matchLabels:
          environment: prod
  template:
    metadata:
      name: '{{name}}-{{values.environment}}'
    spec:
      source:
        repoURL: 'http://gitlab.homelab.local/{{values.user}}/workloads.git'
        path: 'environments/{{values.environment}}'
      destination:
        server: '{{server}}'
        namespace: '{{values.user}}-{{values.environment}}'
```

**4.2 Resource Management**
```yaml
# Per-user resource quotas
apiVersion: v1
kind: ResourceQuota
metadata:
  name: user-quota
  namespace: john-dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4" 
    limits.memory: 8Gi
    persistentvolumeclaims: "5"
    count/deployments.apps: "10"
```

## User Experience Transformation

### Before: External Git Dependency
```bash
# Complex external setup
1. Create GitHub account
2. Generate SSH keys  
3. Configure Git credentials
4. Create private repository
5. Configure ArgoCD with external repo access
6. Manage secrets for external authentication
```

### After: Self-Contained Platform
```bash
# Simple platform workflow
1. make create-user USER=john EMAIL=john@company.com
2. Visit https://gitlab.homelab.local (auto-login)
3. make create-from-template USER=john TEMPLATE=webapp-starter WORKLOAD_NAME=my-app
4. git clone git@gitlab.homelab.local:john/my-app.git
5. # Edit code, commit, push - automatic deployment via ArgoCD
```

### Developer Daily Workflow
```bash
# Completely self-contained development
git clone git@gitlab.homelab.local:john/my-dashboard.git
cd my-dashboard

# Develop locally
npm run dev

# Deploy to dev environment  
git add . && git commit -m "feat: new dashboard widget"
git push origin main
# → GitLab CI builds and pushes to local registry
# → ArgoCD deploys to john-dev namespace automatically

# Promote to production
git tag v1.0.0 && git push origin v1.0.0
# → ArgoCD deploys to john-prod namespace
```

## Consequences

### Positive Outcomes

#### For Individual Users
- **Complete Self-Sufficiency**: No external service dependencies
- **Faster Development Cycles**: Local GitOps loop eliminates network latency
- **Enhanced Privacy**: All code and data remains within personal cluster
- **Cost Reduction**: No external Git service subscriptions needed
- **Offline Development**: Full GitOps capabilities without internet access

#### For Organizations  
- **Air-Gapped Development**: Complete development platform without external connectivity
- **Simplified Compliance**: All source code and artifacts under organizational control
- **Reduced Vendor Lock-in**: No dependency on GitHub/GitLab.com service availability
- **Enhanced Security**: Closed-loop development environment with full audit trails
- **Cost Optimization**: Single cluster serves both infrastructure and development needs

#### For Educational Environments
- **Simplified Student Onboarding**: No external account creation required
- **Consistent Learning Environment**: Identical setup for all students
- **Offline Classroom Support**: No internet dependency for GitOps learning
- **Complete Platform Understanding**: Students see entire development pipeline

#### For ZTC Project
- **Unique Market Position**: Only open-source solution providing complete development platform
- **Broader Adoption**: Appeals to security-conscious and air-gapped environments
- **Community Growth**: Platform approach attracts developers, not just infrastructure engineers
- **Enterprise Viability**: Professional development platform capabilities

### Implementation Challenges

#### Technical Complexity
- **Resource Requirements**: GitLab and Harbor significantly increase cluster resource needs
- **Storage Management**: User repositories and container images require substantial persistent storage
- **Backup Strategy**: Critical user data (Git repos, images) must be protected
- **Performance Scaling**: Multiple users with CI/CD pipelines can strain cluster resources

#### Operational Overhead
- **User Management**: GitLab account provisioning and lifecycle management
- **Security Boundaries**: Proper RBAC and namespace isolation between users
- **Resource Quotas**: Preventing resource exhaustion by individual users
- **Monitoring Complexity**: Observability across multi-tenant workloads

#### Migration and Compatibility
- **Existing User Impact**: Current users with external Git workflows need migration path
- **Hybrid Scenarios**: Supporting both self-hosted and external Git repositories
- **Data Export**: Users must be able to export their repositories and artifacts

### Risk Mitigation

#### Resource Management
```yaml
# Minimum hardware requirements increase
Before: 4 cores, 8GB RAM, 100GB storage
After:  8 cores, 16GB RAM, 500GB storage

# Implement resource monitoring and quotas
- Per-user CPU/memory limits
- Storage cleanup policies  
- GitLab repository size limits
- Container registry garbage collection
```

#### High Availability Considerations
```yaml
# Critical data backup strategy
GitLab Repositories:
  - Daily automated backups to external storage
  - Git bundle exports for disaster recovery
  
Container Registry:
  - Registry replication to backup storage
  - Image export capabilities for migration

User Data:
  - Automated user workspace backups
  - Self-service backup/restore tools
```

#### Security Isolation
```yaml
# Network policies for tenant isolation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-isolation
  namespace: john-dev
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: john-dev
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
```

## Success Metrics

### Quantitative Measures
- **User Onboarding Time**: Target <10 minutes from cluster deployment to first workload deployment
- **Development Velocity**: Measure commit-to-deployment time (target <5 minutes)
- **Resource Efficiency**: Support 10+ concurrent users on 4-node cluster
- **Platform Availability**: >99.5% uptime for GitLab and ArgoCD services

### Qualitative Indicators
- **User Adoption**: Preference for self-hosted vs external Git workflows
- **Community Feedback**: Developer experience satisfaction scores
- **Enterprise Interest**: Inquiries about air-gapped deployments
- **Educational Adoption**: Use in Kubernetes training programs

## Alternatives Considered

### Alternative A: External Git Integration Only
**Description**: Improve external Git provider integration with better authentication and setup
- **Pros**: Lower resource requirements, leverages existing services
- **Cons**: Maintains external dependencies, doesn't address air-gapped scenarios
- **Verdict**: Insufficient for enterprise and educational use cases

### Alternative B: Git Server Only (No CI/CD)
**Description**: Deploy only Gitea/GitLab without integrated CI/CD and registry
- **Pros**: Simpler implementation, lower resource usage
- **Cons**: Incomplete development platform, still requires external tools
- **Verdict**: Misses opportunity for complete platform solution

### Alternative C: Lightweight Git (Gitea Only)
**Description**: Use Gitea instead of GitLab for reduced resource requirements
- **Pros**: Lower memory footprint, faster deployment
- **Cons**: Limited CI/CD capabilities, less enterprise features
- **Verdict**: Consider as alternative implementation for resource-constrained environments

### Alternative D: Hybrid Model with External Fallback
**Description**: Self-hosted by default, with option to use external Git providers
- **Pros**: Best of both worlds, gradual migration path
- **Cons**: Increased complexity, testing burden for multiple configurations
- **Verdict**: Excellent approach for Phase 2 implementation

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
**Goal**: Basic GitLab integration with manual user creation

**Deliverables**:
- GitLab CE deployment as system component
- Basic user namespace creation
- ArgoCD integration with internal GitLab
- Updated documentation for self-hosted workflow

**Acceptance Criteria**:
- GitLab accessible at gitlab.homelab.local
- Users can create repositories and push code
- ArgoCD can sync from internal GitLab repositories
- Basic RBAC isolation between user namespaces

### Phase 2: Automation (Weeks 3-4)  
**Goal**: Automated user onboarding and template system

**Deliverables**:
- Automated user creation with `make create-user`
- Template repository system with common workload patterns
- Container registry integration (Harbor or GitLab Registry)
- CI/CD pipeline templates

**Acceptance Criteria**:
- Users created in <5 minutes with single command
- Template workloads deployable immediately
- Container builds and deployments working end-to-end
- Resource quotas preventing runaway resource usage

### Phase 3: Enterprise Features (Weeks 5-6)
**Goal**: Multi-environment support and advanced platform features

**Deliverables**:
- Dev/staging/prod environment automation
- Advanced RBAC with team-based permissions
- Monitoring and observability for user workloads
- Backup and disaster recovery procedures

**Acceptance Criteria**:
- Automated promotion between environments
- Team collaboration features working
- Complete user workload observability
- Tested backup/restore procedures

### Phase 4: Production Hardening (Weeks 7-8)
**Goal**: Production-ready platform with scaling and security

**Deliverables**:
- Performance optimization and resource management
- Security hardening and compliance features
- Documentation and training materials
- Migration tools for existing users

**Acceptance Criteria**:
- Platform supports 20+ concurrent users
- Security audit and penetration testing completed
- Complete user and administrator documentation
- Smooth migration path from external Git workflows

## Future Considerations

### Advanced Platform Capabilities
- **Kubernetes Development Environment**: Built-in kubectl access and cluster debugging tools
- **Database as a Service**: Automated PostgreSQL/MySQL provisioning for user workloads
- **Secrets Management UI**: Web interface for managing SealedSecrets and application secrets
- **Resource Analytics**: Cost tracking and optimization recommendations for user workloads

### Enterprise Extensions
- **LDAP/SSO Integration**: Enterprise authentication integration
- **Multi-Cluster Management**: GitOps across multiple ZTC clusters
- **Compliance Dashboards**: SOC 2, ISO 27001 compliance reporting
- **Advanced Networking**: Service mesh and advanced traffic management

### Community Ecosystem
- **Marketplace**: Community-contributed workload templates and tools
- **Plugin Architecture**: Extensible platform with third-party integrations
- **Training Programs**: Certification and educational partnerships
- **SaaS Offering**: Hosted ZTC platform for organizations without infrastructure

## Conclusion

ADR-003 represents a fundamental evolution of Zero Touch Cluster from **infrastructure automation** to **platform engineering**. By adding self-hosted Git and CI/CD capabilities, ZTC becomes a complete development platform that eliminates external dependencies while providing enterprise-grade GitOps workflows.

This architectural decision addresses critical market needs:
- **Air-gapped environments** requiring complete self-sufficiency
- **Educational institutions** needing simplified student onboarding  
- **Security-conscious organizations** wanting full control over their development pipeline
- **Individual developers** seeking privacy and cost-effective development platforms

The implementation transforms the user experience from complex multi-service configuration to simple, single-command platform deployment. Users get a complete development environment with GitOps, CI/CD, container registry, and monitoring - all self-contained within their cluster.

Most importantly, this approach maintains ZTC's core principles:
- **Open Source**: All platform components remain OSS
- **User-Friendly**: Complexity hidden behind simple interfaces
- **Production-Ready**: Enterprise-grade security and reliability
- **Zero-Touch**: Automated deployment and management

**Next Steps**:
1. Community feedback and validation of architectural approach
2. Resource requirements analysis and hardware recommendations
3. Proof-of-concept implementation with basic GitLab integration
4. Security review and threat modeling for multi-tenant architecture
5. Performance testing and optimization strategy

This architectural decision positions Zero Touch Cluster as the leading open-source solution for self-hosted development platforms, addressing a significant gap in the current ecosystem while maintaining our commitment to simplicity and reliability.