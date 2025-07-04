#!/bin/bash

# Zero Touch Cluster Template Processing Engine
# Processes workload templates with yq-based YAML parsing and variable substitution

set -euo pipefail

# Color codes for output
CYAN() { echo -e "\033[36m$*\033[0m"; }
GREEN() { echo -e "\033[32m$*\033[0m"; }
YELLOW() { echo -e "\033[33m$*\033[0m"; }
RED() { echo -e "\033[31m$*\033[0m"; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$ZTC_ROOT/kubernetes/workloads/templates"

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi
    
    if ! command -v envsubst >/dev/null 2>&1; then
        missing_deps+=("envsubst")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        RED "Error: Missing required dependencies: ${missing_deps[*]}"
        YELLOW "Install instructions:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                yq)
                    YELLOW "  yq: brew install yq  OR  sudo apt install yq  OR  go install github.com/mikefarah/yq/v4@latest"
                    ;;
                envsubst)
                    YELLOW "  envsubst: sudo apt install gettext-base  OR  brew install gettext"
                    ;;
            esac
        done
        exit 1
    fi
}

# Validate template directory
validate_template() {
    local template_name="$1"
    local template_dir="$TEMPLATES_DIR/$template_name"
    
    if [[ ! -d "$template_dir" ]]; then
        RED "Error: Template '$template_name' not found in $TEMPLATES_DIR"
        YELLOW "Available templates:"
        if [[ -d "$TEMPLATES_DIR" ]]; then
            ls -1 "$TEMPLATES_DIR" | grep -E '^[a-z-]+$' || echo "  (none found)"
        else
            echo "  (templates directory not found)"
        fi
        exit 1
    fi
    
    local template_config="$template_dir/template.yaml"
    if [[ ! -f "$template_config" ]]; then
        RED "Error: Template configuration file not found: $template_config"
        exit 1
    fi
    
    # Validate template.yaml structure using Python
    if ! python3 -c "
import yaml, sys
try:
    with open('$template_config') as f:
        config = yaml.safe_load(f)
    
    # Check required top-level keys
    required_keys = ['metadata', 'defaults']
    for key in required_keys:
        if key not in config:
            print(f'Missing required key: {key}')
            sys.exit(1)
    
    # Check required metadata keys
    required_metadata = ['name', 'description', 'namespace', 'category']
    for key in required_metadata:
        if key not in config['metadata']:
            print(f'Missing required metadata key: {key}')
            sys.exit(1)
            
    print('Template validation passed')
except Exception as e:
    print(f'Template validation failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
        RED "Error: Template configuration validation failed"
        exit 1
    fi
    
    local required_files=("deployment.yaml" "service.yaml" "ingress.yaml")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$template_dir/$file" ]]; then
            RED "Error: Required template file not found: $template_dir/$file"
            exit 1
        fi
    done
}

# Parse template configuration and export environment variables
parse_template_config() {
    local template_name="$1"
    local template_config="$TEMPLATES_DIR/$template_name/template.yaml"
    
    CYAN "Parsing template configuration for $template_name..."
    
    # Export template metadata
    export WORKLOAD_NAME
    export WORKLOAD_NAMESPACE
    export WORKLOAD_DESCRIPTION
    export WORKLOAD_CATEGORY
    
    WORKLOAD_NAME=$(yq e '.metadata.name' "$template_config")
    WORKLOAD_NAMESPACE=$(yq e '.metadata.namespace' "$template_config")
    WORKLOAD_DESCRIPTION=$(yq e '.metadata.description' "$template_config")
    WORKLOAD_CATEGORY=$(yq e '.metadata.category' "$template_config")
    
    # Export default configuration values
    export STORAGE_SIZE
    export STORAGE_CLASS
    export HOSTNAME
    export IMAGE_TAG
    export MEMORY_REQUEST
    export MEMORY_LIMIT
    export CPU_REQUEST
    export CPU_LIMIT
    
    STORAGE_SIZE=$(yq e '.defaults.storage_size' "$template_config")
    STORAGE_CLASS=$(yq e '.defaults.storage_class' "$template_config")
    HOSTNAME=$(yq e '.defaults.hostname' "$template_config")
    IMAGE_TAG=$(yq e '.defaults.image_tag' "$template_config")
    MEMORY_REQUEST=$(yq e '.defaults.resources.requests.memory' "$template_config")
    MEMORY_LIMIT=$(yq e '.defaults.resources.limits.memory' "$template_config")
    CPU_REQUEST=$(yq e '.defaults.resources.requests.cpu' "$template_config")
    CPU_LIMIT=$(yq e '.defaults.resources.limits.cpu' "$template_config")
    
    # Parse optional configuration
    export ADMIN_TOKEN=""
    export PASSWORD=""
    
    if yq e '.defaults | has("admin_token")' "$template_config" | grep -q true; then
        ADMIN_TOKEN=$(yq e '.defaults.admin_token' "$template_config")
    fi
    
    if yq e '.defaults | has("password")' "$template_config" | grep -q true; then
        PASSWORD=$(yq e '.defaults.password' "$template_config")
    fi
    
    # Generate auto-generated secrets if needed
    if [[ "$ADMIN_TOKEN" == "auto-generated" ]]; then
        ADMIN_TOKEN=$(openssl rand -base64 32)
        YELLOW "Generated admin token: $ADMIN_TOKEN"
    fi
    
    if [[ "$PASSWORD" == "auto-generated" ]]; then
        PASSWORD=$(openssl rand -base64 16)
        YELLOW "Generated password: $PASSWORD"
    fi
    
    export ADMIN_TOKEN
    export PASSWORD
    
    # Validate required values
    local required_vars=("WORKLOAD_NAME" "WORKLOAD_NAMESPACE" "STORAGE_SIZE" "STORAGE_CLASS" "HOSTNAME" "IMAGE_TAG")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" || "${!var}" == "null" ]]; then
            RED "Error: Required template value '$var' is empty or null"
            exit 1
        fi
    done
    
    GREEN "✅ Template configuration parsed successfully"
}

# Apply user overrides from environment variables
apply_user_overrides() {
    local template_name="$1"
    
    # Allow user to override any template value via environment variables
    # Priority: User environment > Template defaults
    
    # Storage overrides
    if [[ -n "${OVERRIDE_STORAGE_SIZE:-}" ]]; then
        STORAGE_SIZE="$OVERRIDE_STORAGE_SIZE"
        YELLOW "Override: STORAGE_SIZE = $STORAGE_SIZE"
    fi
    
    if [[ -n "${OVERRIDE_STORAGE_CLASS:-}" ]]; then
        STORAGE_CLASS="$OVERRIDE_STORAGE_CLASS"
        YELLOW "Override: STORAGE_CLASS = $STORAGE_CLASS"
    fi
    
    # Network overrides
    if [[ -n "${OVERRIDE_HOSTNAME:-}" ]]; then
        HOSTNAME="$OVERRIDE_HOSTNAME"
        YELLOW "Override: HOSTNAME = $HOSTNAME"
    fi
    
    # Image overrides
    if [[ -n "${OVERRIDE_IMAGE_TAG:-}" ]]; then
        IMAGE_TAG="$OVERRIDE_IMAGE_TAG"
        YELLOW "Override: IMAGE_TAG = $IMAGE_TAG"
    fi
    
    # Resource overrides
    if [[ -n "${OVERRIDE_MEMORY_REQUEST:-}" ]]; then
        MEMORY_REQUEST="$OVERRIDE_MEMORY_REQUEST"
        YELLOW "Override: MEMORY_REQUEST = $MEMORY_REQUEST"
    fi
    
    if [[ -n "${OVERRIDE_MEMORY_LIMIT:-}" ]]; then
        MEMORY_LIMIT="$OVERRIDE_MEMORY_LIMIT"
        YELLOW "Override: MEMORY_LIMIT = $MEMORY_LIMIT"
    fi
    
    if [[ -n "${OVERRIDE_CPU_REQUEST:-}" ]]; then
        CPU_REQUEST="$OVERRIDE_CPU_REQUEST"
        YELLOW "Override: CPU_REQUEST = $CPU_REQUEST"
    fi
    
    if [[ -n "${OVERRIDE_CPU_LIMIT:-}" ]]; then
        CPU_LIMIT="$OVERRIDE_CPU_LIMIT"
        YELLOW "Override: CPU_LIMIT = $CPU_LIMIT"
    fi
    
    # Security overrides
    if [[ -n "${OVERRIDE_ADMIN_TOKEN:-}" ]]; then
        ADMIN_TOKEN="$OVERRIDE_ADMIN_TOKEN"
        YELLOW "Override: ADMIN_TOKEN = [REDACTED]"
    fi
    
    if [[ -n "${OVERRIDE_PASSWORD:-}" ]]; then
        PASSWORD="$OVERRIDE_PASSWORD"
        YELLOW "Override: PASSWORD = [REDACTED]"
    fi
}

# Process template files and generate Kubernetes manifests
process_template_files() {
    local template_name="$1"
    local output_dir="$2"
    local template_dir="$TEMPLATES_DIR/$template_name"
    
    CYAN "Processing template files for $template_name..."
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Process each YAML file (except template.yaml)
    for file in "$template_dir"/*.yaml; do
        local filename=$(basename "$file")
        
        # Skip template configuration file
        if [[ "$filename" == "template.yaml" ]]; then
            continue
        fi
        
        local output_file="$output_dir/$filename"
        
        CYAN "  Processing $filename..."
        
        # Apply variable substitution (explicit variable list for security)
        local variables='$WORKLOAD_NAME $WORKLOAD_NAMESPACE $WORKLOAD_DESCRIPTION $WORKLOAD_CATEGORY $STORAGE_SIZE $STORAGE_CLASS $HOSTNAME $IMAGE_TAG $MEMORY_REQUEST $MEMORY_LIMIT $CPU_REQUEST $CPU_LIMIT $ADMIN_TOKEN $PASSWORD'
        envsubst "$variables" < "$file" > "$output_file"
        
        # Validate generated YAML (basic check)
        if ! python3 -c "import yaml; yaml.safe_load(open('$output_file'))" >/dev/null 2>&1; then
            YELLOW "Warning: Generated YAML may have syntax issues: $output_file"
            # Don't exit, just warn for now
        fi
    done
    
    GREEN "✅ Template files processed successfully"
}

# Main template processing function
process_template() {
    local template_name="$1"
    local output_dir="${2:-/tmp/workload-$template_name}"
    
    CYAN "🔄 Processing workload template: $template_name"
    
    # Check dependencies
    check_dependencies
    
    # Validate template
    validate_template "$template_name"
    
    # Parse template configuration
    parse_template_config "$template_name"
    
    # Apply user overrides
    apply_user_overrides "$template_name"
    
    # Process template files
    process_template_files "$template_name" "$output_dir"
    
    GREEN "✅ Template processing complete!"
    CYAN "Generated manifests: $output_dir"
    
    return 0
}

# Usage information
usage() {
    echo "Usage: $0 <template-name> [output-directory]"
    echo ""
    echo "Process ZTC workload template and generate Kubernetes manifests"
    echo ""
    echo "Arguments:"
    echo "  template-name     Name of the template to process"
    echo "  output-directory  Directory to write generated manifests (default: /tmp/workload-<template-name>)"
    echo ""
    echo "Available templates:"
    if [[ -d "$TEMPLATES_DIR" ]]; then
        ls -1 "$TEMPLATES_DIR" | grep -E '^[a-z-]+$' | sed 's/^/  /'
    else
        echo "  (templates directory not found)"
    fi
    echo ""
    echo "Environment variable overrides:"
    echo "  OVERRIDE_STORAGE_SIZE     Override storage size (e.g., '10Gi')"
    echo "  OVERRIDE_STORAGE_CLASS    Override storage class (e.g., 'nfs-client')"
    echo "  OVERRIDE_HOSTNAME         Override hostname (e.g., 'my-app.homelab.lan')"
    echo "  OVERRIDE_MEMORY_REQUEST   Override memory request (e.g., '512Mi')"
    echo "  OVERRIDE_MEMORY_LIMIT     Override memory limit (e.g., '1Gi')"
    echo "  OVERRIDE_CPU_REQUEST      Override CPU request (e.g., '200m')"
    echo "  OVERRIDE_CPU_LIMIT        Override CPU limit (e.g., '500m')"
    echo "  OVERRIDE_ADMIN_TOKEN      Override admin token"
    echo "  OVERRIDE_PASSWORD         Override password"
    echo ""
    echo "Examples:"
    echo "  $0 n8n"
    echo "  $0 n8n /home/user/workloads"
    echo "  OVERRIDE_STORAGE_SIZE=10Gi $0 n8n"
}

# Main script execution
main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi
    
    local template_name="$1"
    local output_dir="${2:-/tmp/workload-$template_name}"
    
    process_template "$template_name" "$output_dir"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi