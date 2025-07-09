#!/bin/bash

# Zero Touch Cluster Workload Undeployment Script
# Cleanly removes workloads deployed via the template system

set -euo pipefail

# Color codes for output
CYAN() { echo -e "\033[36m$*\033[0m"; }
GREEN() { echo -e "\033[32m$*\033[0m"; }
YELLOW() { echo -e "\033[33m$*\033[0m"; }
RED() { echo -e "\033[31m$*\033[0m"; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
GITEA_URL="${GITEA_URL:-http://gitea.homelab.lan}"
GITEA_USER="${GITEA_USER:-ztc-admin}"
WORKLOADS_REPO="${WORKLOADS_REPO:-workloads}"
TEMP_DIR="/tmp/ztc-workload-undeploy-$$"

# Usage information
usage() {
    echo "Usage: $0 <workload-name>"
    echo ""
    echo "Cleanly undeploy a ZTC workload and remove all associated resources"
    echo ""
    echo "Arguments:"
    echo "  workload-name     Name of the workload to undeploy"
    echo ""
    echo "Available workloads:"
    kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads -o jsonpath='{range .items[*]}{.metadata.labels.ztc\.homelab/template}{"\n"}{end}' 2>/dev/null | sort -u | sed 's/^/  /' || echo "  (no workloads currently deployed)"
    echo ""
    echo "Examples:"
    echo "  $0 n8n"
    echo "  $0 uptime-kuma"
    echo ""
    echo "What this script does:"
    echo "  1. Delete ArgoCD Application (stops GitOps sync)"
    echo "  2. Delete Kubernetes namespace and all resources"
    echo "  3. Remove workload directory from Git repository"
    echo "  4. Commit and push changes to Git"
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()
    
    # Check required commands
    for cmd in kubectl git curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
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

# Check if workload exists
check_workload_exists() {
    local workload_name="$1"
    local app_name="workload-$workload_name"
    
    CYAN "Checking if workload '$workload_name' exists..."
    
    # Check ArgoCD Application
    if ! kubectl get application "$app_name" -n argocd >/dev/null 2>&1; then
        RED "❌ Workload '$workload_name' not found"
        YELLOW "Available workloads:"
        kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads -o jsonpath='{range .items[*]}{.metadata.labels.ztc\.homelab/template}{"\n"}{end}' 2>/dev/null | sort -u | sed 's/^/  /' || echo "  (none)"
        return 1
    fi
    
    GREEN "✅ Workload '$workload_name' found"
    return 0
}

# Delete ArgoCD Application
delete_argocd_application() {
    local workload_name="$1"
    local app_name="workload-$workload_name"
    
    CYAN "Deleting ArgoCD Application '$app_name'..."
    
    if kubectl delete application "$app_name" -n argocd --timeout=60s; then
        GREEN "✅ ArgoCD Application deleted"
    else
        YELLOW "⚠️  ArgoCD Application deletion may have timed out, continuing..."
    fi
}

# Delete Kubernetes namespace
delete_namespace() {
    local workload_name="$1"
    
    CYAN "Deleting Kubernetes namespace '$workload_name'..."
    
    if kubectl get namespace "$workload_name" >/dev/null 2>&1; then
        if kubectl delete namespace "$workload_name" --timeout=120s; then
            GREEN "✅ Namespace '$workload_name' deleted"
        else
            YELLOW "⚠️  Namespace deletion may have timed out, continuing..."
        fi
    else
        YELLOW "⚠️  Namespace '$workload_name' not found, skipping"
    fi
}

# Clone repository and remove workload directory
remove_from_repository() {
    local workload_name="$1"
    
    CYAN "Removing '$workload_name' from workloads repository..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # URL encode password for git clone
    local encoded_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$GITEA_PASSWORD', safe=''))")
    local repo_url="$(echo "$GITEA_URL" | sed 's|http://|http://'\"$GITEA_USER\"':'\"$encoded_password\"'@|')/$GITEA_USER/$WORKLOADS_REPO.git"
    local repo_dir="$TEMP_DIR/workloads"
    
    # Clone repository  
    CYAN "Cloning $GITEA_URL/$GITEA_USER/$WORKLOADS_REPO.git..."
    if git clone "$repo_url" >/dev/null 2>&1; then
        cd "$repo_dir"
        
        # Configure Git
        git config user.email "ztc-admin@homelab.lan"
        git config user.name "ZTC Admin"
        
        # Check if workload directory exists
        if [[ -d "apps/$workload_name" ]]; then
            # Remove workload directory
            rm -rf "apps/$workload_name"
            
            # Commit changes
            git add .
            
            # Check if there are changes to commit
            if ! git diff --cached --quiet; then
                local commit_message="Remove $workload_name workload

Undeployed via ZTC workload management system on $(date)"
                
                git commit -m "$commit_message"
                
                # Push changes
                if git push origin main; then
                    GREEN "✅ Workload removed from repository"
                else
                    RED "❌ Failed to push changes to repository"
                    return 1
                fi
            else
                YELLOW "⚠️  No changes to commit (workload may have been already removed)"
            fi
        else
            YELLOW "⚠️  Workload directory 'apps/$workload_name' not found in repository"
        fi
    else
        RED "❌ Failed to clone workloads repository"
        YELLOW "Workload resources deleted from cluster, but repository cleanup failed"
        return 1
    fi
}

# Cleanup temporary files
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Main undeployment function
undeploy_workload() {
    local workload_name="$1"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    CYAN "🗑️  Undeploying workload: $workload_name"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Check if workload exists
    if ! check_workload_exists "$workload_name"; then
        exit 1
    fi
    
    # Get Gitea credentials
    get_gitea_credentials
    
    # Delete ArgoCD Application first to stop GitOps sync
    delete_argocd_application "$workload_name"
    
    # Delete Kubernetes namespace and resources
    delete_namespace "$workload_name"
    
    # Remove from Git repository
    remove_from_repository "$workload_name"
    
    # Summary
    echo ""
    GREEN "🎉 Workload undeployment complete!"
    echo ""
    CYAN "📋 Undeployment Summary:"
    echo "  Workload: $workload_name"
    echo "  ArgoCD App: workload-$workload_name (deleted)"
    echo "  Namespace: $workload_name (deleted)"
    echo "  Repository: $GITEA_URL/$GITEA_USER/$WORKLOADS_REPO (cleaned)"
    echo ""
    CYAN "🚀 Ready to redeploy: make deploy-$workload_name"
}

# Main script execution
main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local workload_name="$1"
    
    # Validate workload name
    if [[ ! "$workload_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        RED "Error: Invalid workload name. Use lowercase letters, numbers, and hyphens only."
        exit 1
    fi
    
    # Confirmation prompt
    echo "⚠️  WARNING: This will completely remove the '$workload_name' workload!"
    echo ""
    echo "This action will:"
    echo "  • Delete the ArgoCD Application"
    echo "  • Delete the Kubernetes namespace and all resources"
    echo "  • Remove the workload from the Git repository"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        YELLOW "Undeployment cancelled"
        exit 0
    fi
    
    undeploy_workload "$workload_name"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi