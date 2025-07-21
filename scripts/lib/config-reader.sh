#!/bin/bash

# config-reader.sh - Zero Touch Cluster Configuration Reader
# Utility functions for reading and validating cluster.yaml configuration

set -euo pipefail

# Configuration file paths
readonly DEFAULT_CONFIG_FILE="cluster.yaml"
readonly TEMPLATE_DIR="templates"

# Colors for output
readonly CYAN='\033[36m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly RESET='\033[0m'

# Get configuration file path
get_config_file() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ Configuration file not found: $config_file${RESET}" >&2
        echo -e "${YELLOW}💡 Run 'make prepare' to generate cluster.yaml${RESET}" >&2
        exit 1
    fi
    
    echo "$config_file"
}

# Check if yq is available
check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        echo -e "${RED}❌ yq is required for configuration parsing${RESET}" >&2
        echo -e "${YELLOW}💡 Install yq: https://mikefarah.gitbook.io/yq/${RESET}" >&2
        exit 1
    fi
}

# Read configuration value
# Usage: config_get "path.to.value" [config_file]
config_get() {
    local path="$1"
    local config_file="${2:-$DEFAULT_CONFIG_FILE}"
    
    check_yq
    config_file=$(get_config_file "$config_file")
    
    local result
    result=$(yq eval ".$path" "$config_file" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$result" && "$result" != "null" ]]; then
        echo "$result"
    else
        echo "null"
    fi
}

# Read configuration value with default
# Usage: config_get_default "path.to.value" "default_value" [config_file]
config_get_default() {
    local path="$1"
    local default="$2"
    local config_file="${3:-$DEFAULT_CONFIG_FILE}"
    
    local value
    value=$(config_get "$path" "$config_file")
    
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Check if configuration value exists and is not null
# Usage: config_has "path.to.value" [config_file]
config_has() {
    local path="$1"
    local config_file="${2:-$DEFAULT_CONFIG_FILE}"
    
    local value
    value=$(config_get "$path" "$config_file")
    
    [[ "$value" != "null" && -n "$value" ]]
}

# Get array of values
# Usage: config_get_array "path.to.array" [config_file]
config_get_array() {
    local path="$1"
    local config_file="${2:-$DEFAULT_CONFIG_FILE}"
    
    check_yq
    config_file=$(get_config_file "$config_file")
    
    yq eval ".$path[]" "$config_file" 2>/dev/null || true
}

# Get object keys
# Usage: config_get_keys "path.to.object" [config_file]
config_get_keys() {
    local path="$1"
    local config_file="${2:-$DEFAULT_CONFIG_FILE}"
    
    check_yq
    config_file=$(get_config_file "$config_file")
    
    yq eval ".$path | keys | .[]" "$config_file" 2>/dev/null || true
}

# Validate configuration file
validate_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    echo -e "${CYAN}🔍 Validating configuration file: $config_file${RESET}"
    
    check_yq
    config_file=$(get_config_file "$config_file")
    
    local errors=0
    
    # Check required fields
    local required_fields=(
        "cluster.name"
        "network.subnet"
        "network.gateway"
        "network.pod_cidr"
        "network.service_cidr"
        "nodes.ssh.public_key_path"
        "nodes.ssh.private_key_path"
        "nodes.cluster_nodes"
        "storage.default_storage_class"
        "components"
    )
    
    for field in "${required_fields[@]}"; do
        if ! config_has "$field" "$config_file"; then
            echo -e "${RED}❌ Missing required field: $field${RESET}" >&2
            ((errors++))
        fi
    done
    
    # Validate default storage class
    local default_storage_class
    default_storage_class=$(config_get "storage.default_storage_class" "$config_file")
    if [[ -z "$default_storage_class" || "$default_storage_class" == "null" ]]; then
        echo -e "${RED}❌ Default storage class not specified${RESET}" >&2
        ((errors++))
    else
        echo -e "${GREEN}✅ Default storage class: $default_storage_class${RESET}"
    fi
    
    # Validate network subnet
    local subnet pod_cidr service_cidr
    subnet=$(config_get "network.subnet" "$config_file")
    pod_cidr=$(config_get "network.pod_cidr" "$config_file")
    service_cidr=$(config_get "network.service_cidr" "$config_file")
    
    if [[ ! "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}❌ Invalid network subnet format: $subnet${RESET}" >&2
        echo -e "${YELLOW}   Expected format: 192.168.50.0/24${RESET}" >&2
        ((errors++))
    else
        echo -e "${GREEN}✅ Valid network subnet: $subnet${RESET}"
    fi
    
    if [[ ! "$pod_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}❌ Invalid pod CIDR format: $pod_cidr${RESET}" >&2
        echo -e "${YELLOW}   Expected format: 10.42.0.0/16${RESET}" >&2
        ((errors++))
    else
        echo -e "${GREEN}✅ Valid pod CIDR: $pod_cidr${RESET}"
    fi
    
    if [[ ! "$service_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}❌ Invalid service CIDR format: $service_cidr${RESET}" >&2
        echo -e "${YELLOW}   Expected format: 10.43.0.0/16${RESET}" >&2
        ((errors++))
    else
        echo -e "${GREEN}✅ Valid service CIDR: $service_cidr${RESET}"
    fi
    
    # Validate node IPs are within subnet
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local node_ip
        node_ip=$(config_get "nodes.cluster_nodes.$node.ip" "$config_file")
        if [[ -n "$node_ip" && "$node_ip" != "null" ]]; then
            echo -e "${GREEN}✅ Node $node IP: $node_ip${RESET}"
        else
            echo -e "${RED}❌ Missing IP for node: $node${RESET}" >&2
            ((errors++))
        fi
    done <<< "$nodes"
    
    # Check storage configuration consistency
    if [[ "$default_storage_class" == "longhorn" ]]; then
        if ! config_has "storage.longhorn.enabled" "$config_file" || \
           [[ "$(config_get "storage.longhorn.enabled" "$config_file")" != "true" ]]; then
            echo -e "${YELLOW}⚠️  Default storage class is 'longhorn' but Longhorn is not enabled${RESET}" >&2
        fi
    elif [[ "$default_storage_class" == "nfs-csi" ]]; then
        if ! config_has "storage.nfs.enabled" "$config_file" || \
           [[ "$(config_get "storage.nfs.enabled" "$config_file")" != "true" ]]; then
            echo -e "${YELLOW}⚠️  Default storage class is 'nfs-csi' but NFS is not enabled${RESET}" >&2
        fi
    fi
    
    if (( errors > 0 )); then
        echo -e "${RED}❌ Configuration validation failed with $errors errors${RESET}" >&2
        return 1
    else
        echo -e "${GREEN}✅ Configuration validation passed${RESET}"
        return 0
    fi
}

# Show configuration summary
show_config_summary() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    echo -e "${CYAN}📋 Configuration Summary${RESET}"
    echo -e "${CYAN}========================${RESET}"
    
    config_file=$(get_config_file "$config_file")
    
    echo -e "${GREEN}Cluster:${RESET}"
    echo "  Name: $(config_get "cluster.name" "$config_file")"
    echo "  Description: $(config_get "cluster.description" "$config_file")"
    echo ""
    
    echo -e "${GREEN}Network:${RESET}"
    echo "  Subnet: $(config_get "network.subnet" "$config_file")"
    echo "  Gateway: $(config_get "network.gateway" "$config_file")"
    echo "  Pod CIDR: $(config_get "network.pod_cidr" "$config_file")"
    echo "  Service CIDR: $(config_get "network.service_cidr" "$config_file")"
    echo "  DNS Domain: $(config_get "network.dns.domain" "$config_file")"
    echo ""
    
    echo -e "${GREEN}Storage:${RESET}"
    echo "  Default Storage Class: $(config_get "storage.default_storage_class" "$config_file")"
    echo "  Local Path: $(config_get "storage.local_path.enabled" "$config_file")"
    echo "  NFS: $(config_get "storage.nfs.enabled" "$config_file")"
    echo "  Longhorn: $(config_get "storage.longhorn.enabled" "$config_file")"
    echo ""
    
    echo -e "${GREEN}Nodes:${RESET}"
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local node_ip role
        node_ip=$(config_get "nodes.cluster_nodes.$node.ip" "$config_file")
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        echo "  $node: $node_ip ($role)"
    done <<< "$nodes"
    echo ""
    
    echo -e "${GREEN}Components:${RESET}"
    echo "  Monitoring: $(config_get "components.monitoring.enabled" "$config_file")"
    echo "  Gitea: $(config_get "components.gitea.enabled" "$config_file")"
    echo "  MinIO: $(config_get "components.minio.enabled" "$config_file")"
    echo "  Homepage: $(config_get "components.homepage.enabled" "$config_file")"
    echo "  ArgoCD: $(config_get "components.argocd.enabled" "$config_file")"
    echo ""
    
    local bundles
    bundles=$(config_get_array "workloads.auto_deploy_bundles" "$config_file")
    if [[ -n "$bundles" ]]; then
        echo -e "${GREEN}Auto-deploy Bundles:${RESET}"
        while read -r bundle; do
            [[ -z "$bundle" ]] && continue
            echo "  - $bundle"
        done <<< "$bundles"
    else
        echo -e "${GREEN}Auto-deploy Bundles:${RESET} None"
    fi
}

# List available configuration templates
list_templates() {
    echo -e "${CYAN}📋 Available Configuration Templates${RESET}"
    echo -e "${CYAN}====================================${RESET}"
    
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        echo -e "${YELLOW}⚠️  No templates directory found${RESET}"
        return
    fi
    
    find "$TEMPLATE_DIR" -name "cluster-*.yaml" -type f | while read -r template; do
        local template_name
        template_name=$(basename "$template" .yaml)
        template_name=${template_name#cluster-}
        
        local description
        description=$(config_get "cluster.description" "$template" 2>/dev/null || echo "No description")
        
        echo -e "${GREEN}$template_name${RESET}: $description"
        
        # Show key characteristics
        local default_storage_class nodes_count
        default_storage_class=$(config_get "storage.default_storage_class" "$template" 2>/dev/null || echo "unknown")
        nodes_count=$(config_get_keys "nodes.cluster_nodes" "$template" 2>/dev/null | wc -l || echo "unknown")
        
        echo "  Default Storage: $default_storage_class, Nodes: $nodes_count"
        echo ""
    done
}

# Copy template to cluster.yaml
use_template() {
    local template_name="$1"
    local template_file="$TEMPLATE_DIR/cluster-$template_name.yaml"
    
    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}❌ Template not found: $template_name${RESET}" >&2
        echo -e "${YELLOW}💡 Run 'config_list_templates' to see available templates${RESET}" >&2
        return 1
    fi
    
    if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
        echo -e "${YELLOW}⚠️  Existing configuration file will be backed up${RESET}"
        cp "$DEFAULT_CONFIG_FILE" "${DEFAULT_CONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    cp "$template_file" "$DEFAULT_CONFIG_FILE"
    echo -e "${GREEN}✅ Template '$template_name' copied to $DEFAULT_CONFIG_FILE${RESET}"
    
    show_config_summary
}

# Helper functions for common configuration patterns

# Get all node IPs
get_all_node_ips() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    # Get cluster node IPs
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        config_get "nodes.cluster_nodes.$node.ip" "$config_file"
    done <<< "$nodes"
    
}

# Get master node IP
get_master_ip() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local role
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        if [[ "$role" == "master" ]]; then
            config_get "nodes.cluster_nodes.$node.ip" "$config_file"
            return
        fi
    done <<< "$nodes"
}

# If script is run directly, provide command-line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        "validate")
            validate_config "${2:-}"
            ;;
        "summary")
            show_config_summary "${2:-}"
            ;;
        "templates")
            list_templates
            ;;
        "use-template")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}❌ Usage: $0 use-template <template-name>${RESET}" >&2
                exit 1
            fi
            use_template "$2"
            ;;
        "get")
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}❌ Usage: $0 get <config.path>${RESET}" >&2
                exit 1
            fi
            config_get "$2" "${3:-}"
            ;;
        "help"|*)
            echo "ZTC Configuration Reader"
            echo ""
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  validate [file]       Validate configuration file"
            echo "  summary [file]        Show configuration summary"
            echo "  templates             List available templates"
            echo "  use-template <name>   Copy template to cluster.yaml"
            echo "  get <path> [file]     Get configuration value"
            echo "  help                  Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 validate"
            echo "  $0 summary"
            echo "  $0 use-template homelab"
            echo "  $0 get storage.default_storage_class"
            ;;
    esac
fi