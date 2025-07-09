#!/bin/bash

# auto-deploy-bundles.sh - Auto-deploy workload bundles based on cluster configuration
# This script reads cluster.yaml and deploys configured workload bundles automatically

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config-reader.sh"

# Colors for output
AUTO_CYAN='\033[36m'
AUTO_GREEN='\033[32m'
AUTO_YELLOW='\033[33m'
AUTO_RED='\033[31m'
AUTO_RESET='\033[0m'

# Function to deploy a single bundle
deploy_bundle() {
    local bundle_name="$1"
    
    echo -e "${AUTO_CYAN}📦 Deploying bundle: $bundle_name${AUTO_RESET}"
    
    # Check if bundle deployment target exists
    if ! make -n "deploy-bundle-$bundle_name" >/dev/null 2>&1; then
        echo -e "${AUTO_RED}❌ Bundle deployment target not found: deploy-bundle-$bundle_name${AUTO_RESET}"
        return 1
    fi
    
    # Deploy the bundle
    if make "deploy-bundle-$bundle_name"; then
        echo -e "${AUTO_GREEN}✅ Bundle deployed successfully: $bundle_name${AUTO_RESET}"
        return 0
    else
        echo -e "${AUTO_RED}❌ Failed to deploy bundle: $bundle_name${AUTO_RESET}"
        return 1
    fi
}

# Function to wait for ArgoCD to be ready
wait_for_argocd() {
    echo -e "${AUTO_CYAN}🔄 Waiting for ArgoCD to be ready...${AUTO_RESET}"
    
    local retries=0
    local max_retries=30
    
    while [[ $retries -lt $max_retries ]]; do
        if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q "Running"; then
            echo -e "${AUTO_GREEN}✅ ArgoCD is ready${AUTO_RESET}"
            return 0
        fi
        
        echo -e "${AUTO_YELLOW}⏳ Waiting for ArgoCD pods to be ready (${retries}/${max_retries})...${AUTO_RESET}"
        sleep 10
        ((retries++))
    done
    
    echo -e "${AUTO_RED}❌ Timeout waiting for ArgoCD to be ready${AUTO_RESET}"
    return 1
}

# Main auto-deployment function
auto_deploy_bundles() {
    local config_file="${1:-cluster.yaml}"
    local skip_argocd_check="${2:-false}"
    
    echo -e "${AUTO_CYAN}🚀 Starting workload bundle auto-deployment...${AUTO_RESET}"
    
    # Check if configuration file exists
    if ! get_config_file "$config_file" >/dev/null; then
        echo -e "${AUTO_RED}❌ Configuration file not found: $config_file${AUTO_RESET}"
        return 1
    fi
    
    # Check if workload auto-deployment is enabled
    local workloads_enabled
    workloads_enabled=$(config_get_default "deployment.phases.workloads" "true" "$config_file")
    
    if [[ "$workloads_enabled" != "true" ]]; then
        echo -e "${AUTO_YELLOW}⏩ Workload auto-deployment disabled in configuration${AUTO_RESET}"
        echo -e "${AUTO_YELLOW}💡 To enable: set deployment.phases.workloads=true in cluster.yaml${AUTO_RESET}"
        return 0
    fi
    
    # Get list of bundles to auto-deploy
    local bundles
    bundles=$(config_get_array "workloads.auto_deploy_bundles" "$config_file")
    
    if [[ -z "$bundles" ]]; then
        echo -e "${AUTO_YELLOW}⏩ No workload bundles configured for auto-deployment${AUTO_RESET}"
        echo -e "${AUTO_YELLOW}💡 To configure: add bundles to workloads.auto_deploy_bundles in cluster.yaml${AUTO_RESET}"
        return 0
    fi
    
    # Wait for ArgoCD to be ready (unless skipped)
    if [[ "$skip_argocd_check" != "true" ]]; then
        if ! wait_for_argocd; then
            echo -e "${AUTO_RED}❌ Cannot deploy workloads without ArgoCD${AUTO_RESET}"
            return 1
        fi
    else
        echo -e "${AUTO_YELLOW}⏩ Skipping ArgoCD readiness check${AUTO_RESET}"
    fi
    
    # Deploy each configured bundle
    local deployed_count=0
    local failed_count=0
    
    echo -e "${AUTO_CYAN}📋 Bundles to deploy:${AUTO_RESET}"
    while read -r bundle; do
        [[ -z "$bundle" ]] && continue
        echo "  - $bundle"
    done <<< "$bundles"
    
    echo ""
    
    while read -r bundle; do
        [[ -z "$bundle" ]] && continue
        
        if deploy_bundle "$bundle"; then
            ((deployed_count++))
        else
            ((failed_count++))
        fi
        
        echo ""
    done <<< "$bundles"
    
    # Summary
    echo -e "${AUTO_CYAN}📊 Auto-deployment Summary:${AUTO_RESET}"
    echo "  Deployed: $deployed_count"
    echo "  Failed: $failed_count"
    
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${AUTO_YELLOW}⚠️  Some bundles failed to deploy. Check logs above.${AUTO_RESET}"
        return 1
    else
        echo -e "${AUTO_GREEN}✅ All configured bundles deployed successfully!${AUTO_RESET}"
        return 0
    fi
}

# Command-line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-auto-deploy}" in
        "auto-deploy"|"deploy")
            auto_deploy_bundles "${2:-}" "${3:-false}"
            ;;
        "test"|"dry-run")
            echo -e "${AUTO_CYAN}🧪 Testing auto-deployment (dry run)...${AUTO_RESET}"
            auto_deploy_bundles "${2:-}" "true"
            ;;
        "help"|*)
            echo "ZTC Workload Bundle Auto-Deployment"
            echo ""
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  auto-deploy [config]    Auto-deploy bundles from configuration"
            echo "  deploy [config]         Alias for auto-deploy"
            echo "  test [config]           Test deployment (skip ArgoCD check)"
            echo "  dry-run [config]        Alias for test"
            echo "  help                    Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 auto-deploy"
            echo "  $0 deploy cluster.yaml"
            echo "  $0 test cluster.yaml"
            echo ""
            echo "Configuration:"
            echo "  Reads workloads.auto_deploy_bundles from cluster.yaml"
            echo "  Example bundles: starter, monitoring, productivity, security"
            ;;
    esac
fi