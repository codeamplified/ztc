#!/bin/bash

# Zero Touch Cluster Workload Deployment Script
# End-to-end automation for deploying workload templates via GitOps

set -euo pipefail

# Color codes for output
CYAN() { echo -e "\033[36m$*\033[0m"; }
GREEN() { echo -e "\033[32m$*\033[0m"; }
YELLOW() { echo -e "\033[33m$*\033[0m"; }
RED() { echo -e "\033[31m$*\033[0m"; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_ENGINE="$SCRIPT_DIR/template-engine.sh"

# Configuration (can be overridden via environment variables)
GITEA_URL="${GITEA_URL:-http://gitea.homelab.lan}"
GITEA_USER="${GITEA_USER:-ztc-admin}"
WORKLOADS_REPO="${WORKLOADS_REPO:-workloads}"
TEMP_DIR="/tmp/ztc-workload-deploy-$$"

# Check prerequisites
check_prerequisites() {
    local missing_deps=()
    
    # Check required commands
    for cmd in kubectl git curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check template engine
    if [[ ! -x "$TEMPLATE_ENGINE" ]]; then
        missing_deps+=("template-engine.sh")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        RED "Error: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Check Kubernetes connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        RED "Error: Cannot connect to Kubernetes cluster"
        YELLOW "Ensure kubectl is configured and cluster is accessible"
        exit 1
    fi
    
    # Check if Gitea is accessible
    if ! curl -s "$GITEA_URL" >/dev/null 2>&1; then
        RED "Error: Cannot connect to Gitea at $GITEA_URL"
        YELLOW "Ensure Gitea is deployed and accessible"
        exit 1
    fi
}

# Get Gitea admin credentials
get_gitea_credentials() {
    CYAN "Retrieving Gitea admin credentials..."
    
    local password
    password=$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || {
        RED "Error: Cannot retrieve Gitea admin password"
        YELLOW "Ensure Gitea is deployed with proper SealedSecret configuration"
        exit 1
    }
    
    export GITEA_PASSWORD="$password"
    GREEN "✅ Gitea credentials retrieved"
}

# Check if repository exists in Gitea
check_repository_exists() {
    local repo_url="$GITEA_URL/api/v1/repos/$GITEA_USER/$WORKLOADS_REPO"
    
    if curl -s -u "$GITEA_USER:$GITEA_PASSWORD" "$repo_url" >/dev/null 2>&1; then
        return 0  # Repository exists
    else
        return 1  # Repository does not exist
    fi
}

# Create repository in Gitea
create_repository() {
    CYAN "Creating workloads repository in Gitea..."
    
    local create_url="$GITEA_URL/api/v1/user/repos"
    local repo_data='{
        "name": "'$WORKLOADS_REPO'",
        "description": "ZTC Private Workloads - Managed by template deployment system",
        "private": true,
        "auto_init": true,
        "default_branch": "main"
    }'
    
    if curl -s -X POST -u "$GITEA_USER:$GITEA_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "$repo_data" \
            "$create_url" >/dev/null 2>&1; then
        GREEN "✅ Repository created successfully"
    else
        RED "Error: Failed to create repository"
        exit 1
    fi
}

# Clone or update workloads repository
setup_repository() {
    # Include credentials in repo URL for private repository access
    local repo_url_base="$GITEA_URL/$GITEA_USER/$WORKLOADS_REPO.git"
    local repo_url="$(echo "$GITEA_URL" | sed 's|http://|http://'"$GITEA_USER"':'"$GITEA_PASSWORD"'@|')/$GITEA_USER/$WORKLOADS_REPO.git"
    local repo_dir="$TEMP_DIR/workloads"
    
    # Ensure repository exists
    if ! check_repository_exists; then
        create_repository
        sleep 2  # Give Gitea time to initialize the repository
    fi
    
    CYAN "Setting up local repository..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository
    if git clone "$repo_url" 2>/dev/null; then
        GREEN "✅ Repository cloned successfully"
    else
        RED "Error: Failed to clone repository"
        YELLOW "Ensure Git credentials are configured and repository is accessible"
        exit 1
    fi
    
    cd "$repo_dir"
    
    # Configure Git if needed
    if ! git config user.email >/dev/null 2>&1; then
        git config user.email "ztc-admin@homelab.lan"
        git config user.name "ZTC Admin"
    fi
    
    export REPO_DIR="$repo_dir"
}

# Generate manifests using template engine
generate_manifests() {
    local template_name="$1"
    local manifests_dir="$TEMP_DIR/manifests"
    
    CYAN "Generating Kubernetes manifests for $template_name..."
    
    # Run template engine
    if "$TEMPLATE_ENGINE" "$template_name" "$manifests_dir"; then
        GREEN "✅ Manifests generated successfully"
    else
        RED "Error: Template processing failed"
        exit 1
    fi
    
    export MANIFESTS_DIR="$manifests_dir"
}

# Organize manifests in repository
organize_manifests() {
    local template_name="$1"
    local workload_dir="$REPO_DIR/apps/$template_name"
    
    CYAN "Organizing manifests in repository structure..."
    
    # Create application directory
    mkdir -p "$workload_dir"
    
    # Copy generated manifests
    cp "$MANIFESTS_DIR"/*.yaml "$workload_dir/"
    
    # Create application README
    cat > "$workload_dir/README.md" <<EOF
# $template_name

This application was deployed using ZTC workload templates.

## Access

- **URL**: http://\$(hostname).homelab.lan
- **Namespace**: \$(namespace)

## Management

- **Update**: \`make deploy-$template_name\`
- **Status**: \`make workload-status WORKLOAD=$template_name\`
- **Logs**: \`kubectl logs -n \$(namespace) -l app=$template_name\`

## Generated Files

$(ls "$workload_dir"/*.yaml | xargs -n1 basename | sed 's/^/- /')

Generated on: $(date)
EOF
    
    GREEN "✅ Manifests organized in repository"
}

# Commit and push changes
commit_and_push() {
    local template_name="$1"
    
    CYAN "Committing and pushing changes..."
    
    cd "$REPO_DIR"
    
    # Add all changes
    git add .
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        YELLOW "⚠️  No changes to commit"
        return 0
    fi
    
    # Commit changes
    local commit_message="Deploy $template_name workload

Generated by ZTC workload template system on $(date)"
    
    git commit -m "$commit_message"
    
    # Push changes
    if git push origin main; then
        GREEN "✅ Changes pushed to repository"
    else
        RED "Error: Failed to push changes"
        exit 1
    fi
}

# Create or update ArgoCD Application
create_argocd_application() {
    local template_name="$1"
    local app_name="workload-$template_name"
    local app_file="$TEMP_DIR/$app_name.yaml"
    
    CYAN "Creating ArgoCD Application for $template_name..."
    
    # Generate ArgoCD Application manifest
    cat > "$app_file" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $app_name
  namespace: argocd
  labels:
    app.kubernetes.io/name: $app_name
    app.kubernetes.io/part-of: ztc-workloads
    ztc.homelab/template: $template_name
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    ztc.homelab/deployed-by: "workload-template-system"
    ztc.homelab/deployed-at: "$(date -Iseconds)"
spec:
  project: default
  source:
    repoURL: $GITEA_URL/$GITEA_USER/$WORKLOADS_REPO.git
    targetRevision: main
    path: apps/$template_name
  destination:
    server: https://kubernetes.default.svc
    namespace: $template_name
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 10
EOF
    
    # Apply ArgoCD Application
    if kubectl apply -f "$app_file"; then
        GREEN "✅ ArgoCD Application created"
    else
        RED "Error: Failed to create ArgoCD Application"
        exit 1
    fi
}

# Wait for deployment and check status
wait_for_deployment() {
    local template_name="$1"
    local app_name="workload-$template_name"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    CYAN "Waiting for $template_name deployment..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Check ArgoCD Application status
        local health=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        local sync=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$health" == "Healthy" && "$sync" == "Synced" ]]; then
            GREEN "✅ Deployment successful!"
            return 0
        elif [[ "$health" == "Degraded" ]]; then
            RED "❌ Deployment failed!"
            return 1
        fi
        
        echo -n "."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    YELLOW "⚠️  Deployment timeout reached"
    return 1
}

# Display deployment summary
show_deployment_summary() {
    local template_name="$1"
    local app_name="workload-$template_name"
    
    echo ""
    GREEN "🎉 Workload deployment complete!"
    echo ""
    CYAN "📋 Deployment Summary:"
    echo "  Template: $template_name"
    echo "  Namespace: $template_name"
    echo "  Repository: $GITEA_URL/$GITEA_USER/$WORKLOADS_REPO"
    echo "  ArgoCD App: $app_name"
    echo ""
    
    # Get service information
    local hostname=$(kubectl get ingress -n "$template_name" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not available")
    if [[ "$hostname" != "Not available" ]]; then
        CYAN "🌐 Access URL: http://$hostname"
    fi
    
    CYAN "📊 Status Commands:"
    echo "  kubectl get pods -n $template_name"
    echo "  make workload-status WORKLOAD=$template_name"
    echo "  kubectl get application $app_name -n argocd"
}

# Cleanup temporary files
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Main deployment function
deploy_workload() {
    local template_name="$1"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    CYAN "🚀 Deploying workload: $template_name"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Get Gitea credentials
    get_gitea_credentials
    
    # Set up repository
    setup_repository
    
    # Generate manifests
    generate_manifests "$template_name"
    
    # Organize manifests in repository
    organize_manifests "$template_name"
    
    # Commit and push
    commit_and_push "$template_name"
    
    # Create ArgoCD Application
    create_argocd_application "$template_name"
    
    # Wait for deployment
    wait_for_deployment "$template_name"
    
    # Show summary
    show_deployment_summary "$template_name"
}

# Usage information
usage() {
    echo "Usage: $0 <template-name>"
    echo ""
    echo "Deploy ZTC workload template via GitOps"
    echo ""
    echo "Arguments:"
    echo "  template-name     Name of the template to deploy"
    echo ""
    echo "Available templates:"
    local templates_dir="$ZTC_ROOT/kubernetes/workloads/templates"
    if [[ -d "$templates_dir" ]]; then
        ls -1 "$templates_dir" | grep -E '^[a-z-]+$' | sed 's/^/  /'
    else
        echo "  (templates directory not found)"
    fi
    echo ""
    echo "Examples:"
    echo "  $0 n8n"
    echo "  $0 uptime-kuma"
    echo ""
    echo "Prerequisites:"
    echo "  - kubectl configured for target cluster"
    echo "  - Gitea deployed and accessible"
    echo "  - ArgoCD deployed and configured"
}

# Main script execution
main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local template_name="$1"
    
    # Validate template name
    if [[ ! "$template_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        RED "Error: Invalid template name. Use lowercase letters, numbers, and hyphens only."
        exit 1
    fi
    
    deploy_workload "$template_name"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi