#!/bin/bash

# deploy-bundle.sh - Deploy workload bundles for Zero Touch Cluster
# Usage: ./deploy-bundle.sh <bundle-name>

set -euo pipefail

# Colors for output
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Configuration
BUNDLE_DIR="kubernetes/workloads/bundles"
WORKLOAD_DIR="kubernetes/workloads/templates"
DEPLOY_SCRIPT="scripts/workloads/deploy-workload.sh"

# Help function
show_help() {
    cat << EOF
Usage: $0 <bundle-name>

Deploy a complete workload bundle with all configured services.

Available bundles:
  starter      - Essential homelab starter pack (homepage + uptime-kuma)
  monitoring   - Complete monitoring solution (uptime-kuma + homepage)
  productivity - Development toolkit (code-server + n8n)
  security     - Security tools (vaultwarden)

Examples:
  $0 starter      # Deploy starter bundle
  $0 monitoring   # Deploy monitoring bundle
  $0 productivity # Deploy productivity bundle
  $0 security     # Deploy security bundle

Options:
  -h, --help     Show this help message
  -l, --list     List available bundles
  -s, --status   Show status of deployed bundles
  -d, --dry-run  Show what would be deployed without deploying

EOF
}

# List available bundles
list_bundles() {
    echo -e "${CYAN}Available bundles:${RESET}"
    for bundle_file in "$BUNDLE_DIR"/*.yaml; do
        if [ -f "$bundle_file" ]; then
            bundle_name=$(basename "$bundle_file" .yaml)
            description=$(yq eval '.metadata.description' "$bundle_file")
            category=$(yq eval '.metadata.category' "$bundle_file")
            echo -e "  ${GREEN}$bundle_name${RESET} ($category) - $description"
        fi
    done
}

# Show bundle status
show_status() {
    echo -e "${CYAN}Bundle deployment status:${RESET}"
    
    for bundle_file in "$BUNDLE_DIR"/*.yaml; do
        if [ -f "$bundle_file" ]; then
            bundle_name=$(basename "$bundle_file" .yaml)
            echo -e "\n${YELLOW}Bundle: $bundle_name${RESET}"
            
            # Get workloads from bundle
            workloads=$(yq eval '.workloads[].name' "$bundle_file")
            
            for workload in $workloads; do
                # Check if ArgoCD application exists
                if kubectl get application "workload-$workload" -n argocd >/dev/null 2>&1; then
                    sync_status=$(kubectl get application "workload-$workload" -n argocd -o jsonpath='{.status.sync.status}')
                    health_status=$(kubectl get application "workload-$workload" -n argocd -o jsonpath='{.status.health.status}')
                    echo -e "  ${GREEN}✓${RESET} $workload (sync: $sync_status, health: $health_status)"
                else
                    echo -e "  ${RED}✗${RESET} $workload (not deployed)"
                fi
            done
        fi
    done
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -l|--list)
        list_bundles
        exit 0
        ;;
    -s|--status)
        show_status
        exit 0
        ;;
    -d|--dry-run)
        DRY_RUN=true
        BUNDLE_NAME="${2:-}"
        ;;
    "")
        echo -e "${RED}Error: Bundle name is required${RESET}"
        show_help
        exit 1
        ;;
    *)
        BUNDLE_NAME="$1"
        ;;
esac

# Validate bundle name
if [ -z "${BUNDLE_NAME:-}" ]; then
    echo -e "${RED}Error: Bundle name is required${RESET}"
    show_help
    exit 1
fi

BUNDLE_FILE="$BUNDLE_DIR/$BUNDLE_NAME.yaml"

if [ ! -f "$BUNDLE_FILE" ]; then
    echo -e "${RED}Error: Bundle '$BUNDLE_NAME' not found${RESET}"
    echo -e "${YELLOW}Available bundles:${RESET}"
    list_bundles
    exit 1
fi

# Check prerequisites
if ! command -v yq >/dev/null 2>&1; then
    echo -e "${RED}Error: yq is required but not installed${RESET}"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}Error: kubectl is required but not installed${RESET}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: Kubernetes cluster is not accessible${RESET}"
    exit 1
fi

# Read bundle metadata
echo -e "${CYAN}📦 Deploying bundle: $BUNDLE_NAME${RESET}"
description=$(yq eval '.metadata.description' "$BUNDLE_FILE")
category=$(yq eval '.metadata.category' "$BUNDLE_FILE")
echo -e "${YELLOW}Description: $description${RESET}"
echo -e "${YELLOW}Category: $category${RESET}"

# Show resource requirements
total_memory=$(yq eval '.resource_requirements.total_memory' "$BUNDLE_FILE")
total_cpu=$(yq eval '.resource_requirements.total_cpu' "$BUNDLE_FILE")
total_storage=$(yq eval '.resource_requirements.total_storage' "$BUNDLE_FILE")

echo -e "${YELLOW}Resource Requirements:${RESET}"
echo -e "  Memory: $total_memory"
echo -e "  CPU: $total_cpu"
echo -e "  Storage: $total_storage"

# Get workloads sorted by priority
workloads_json=$(yq eval '.workloads | sort_by(.priority) | .[] | {"name": .name, "priority": .priority, "description": .description, "overrides": .overrides}' "$BUNDLE_FILE" -o json)

# Count workloads
workload_count=$(echo "$workloads_json" | jq -s length)
echo -e "${YELLOW}Workloads to deploy: $workload_count${RESET}"

# Show deployment plan
echo -e "\n${CYAN}Deployment Plan:${RESET}"
echo "$workloads_json" | jq -r -s '.[] | "  \(.priority). \(.name) - \(.description)"'

# Confirm deployment (skip in dry-run mode)
if [ "${DRY_RUN:-false}" = "true" ]; then
    echo -e "\n${YELLOW}Dry run mode - no actual deployment will occur${RESET}"
    exit 0
fi

echo -e "\n${YELLOW}Proceed with deployment? (y/N)${RESET}"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${RESET}"
    exit 0
fi

# Deploy workloads in priority order
echo -e "\n${CYAN}🚀 Starting bundle deployment...${RESET}"

current_workload=0
echo "$workloads_json" | jq -r -s '.[]' | while read -r workload_data; do
    current_workload=$((current_workload + 1))
    
    workload_name=$(echo "$workload_data" | jq -r '.name')
    workload_desc=$(echo "$workload_data" | jq -r '.description')
    workload_overrides=$(echo "$workload_data" | jq -r '.overrides // {}')
    
    echo -e "\n${CYAN}[$current_workload/$workload_count] Deploying $workload_name...${RESET}"
    echo -e "${YELLOW}Description: $workload_desc${RESET}"
    
    # Check if workload template exists
    if [ ! -d "$WORKLOAD_DIR/$workload_name" ]; then
        echo -e "${RED}❌ Workload template '$workload_name' not found${RESET}"
        continue
    fi
    
    # Build environment variables for overrides
    export_vars=""
    if [ "$workload_overrides" != "{}" ]; then
        echo -e "${YELLOW}Applying overrides:${RESET}"
        while IFS= read -r override; do
            key=$(echo "$override" | cut -d'=' -f1)
            value=$(echo "$override" | cut -d'=' -f2-)
            echo -e "  $key=$value"
            export_vars="$export_vars OVERRIDE_$key=$value"
        done < <(echo "$workload_overrides" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi
    
    # Deploy workload with overrides
    if [ -n "$export_vars" ]; then
        eval "env $export_vars $DEPLOY_SCRIPT $workload_name"
    else
        "$DEPLOY_SCRIPT" "$workload_name"
    fi
    
    # Wait for deployment to be ready
    echo -e "${CYAN}⏳ Waiting for $workload_name to be ready...${RESET}"
    if kubectl wait --for=condition=Synced --timeout=300s application/workload-$workload_name -n argocd >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $workload_name deployed successfully${RESET}"
    else
        echo -e "${YELLOW}⚠️  $workload_name deployment may still be in progress${RESET}"
    fi
done

# Show final status
echo -e "\n${GREEN}🎉 Bundle deployment completed!${RESET}"
echo -e "${CYAN}Access URLs:${RESET}"
yq eval '.documentation.access_urls[]' "$BUNDLE_FILE" | while read -r url; do
    echo -e "  $url"
done

echo -e "\n${CYAN}Next Steps:${RESET}"
yq eval '.documentation.post_install[]' "$BUNDLE_FILE" | while read -r step; do
    echo -e "  • $step"
done

echo -e "\n${CYAN}Check deployment status:${RESET}"
echo -e "  make list-workloads"
echo -e "  $0 --status"