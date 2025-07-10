#!/bin/bash

# validate-schema.sh - JSON Schema validation for cluster.yaml
# Uses ajv-cli for comprehensive schema validation

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-reader.sh"

# Default paths
SCHEMA_FILE="schema/cluster-schema.json"
DEFAULT_CONFIG="cluster.yaml"

# Colors for output
VAL_CYAN='\033[36m'
VAL_GREEN='\033[32m'
VAL_YELLOW='\033[33m'
VAL_RED='\033[31m'
VAL_RESET='\033[0m'

# Check if ajv-cli is available
check_ajv() {
    if ! command -v ajv >/dev/null 2>&1; then
        echo -e "${VAL_YELLOW}⚠️  ajv-cli not found. Schema validation will use basic yq validation.${VAL_RESET}"
        echo -e "${VAL_YELLOW}💡 Install ajv-cli for comprehensive validation: npm install -g ajv-cli${VAL_RESET}"
        return 1
    fi
    return 0
}

# Validate using ajv-cli (comprehensive)
validate_with_ajv() {
    local config_file="$1"
    local schema_file="$2"
    
    echo -e "${VAL_CYAN}🔍 Validating with JSON Schema (ajv-cli)...${VAL_RESET}"
    
    # Convert YAML to JSON for ajv validation
    local temp_json="/tmp/cluster-config-$$.json"
    if ! yq eval -o=json "$config_file" > "$temp_json" 2>/dev/null; then
        echo -e "${VAL_RED}❌ Failed to convert YAML to JSON for validation${VAL_RESET}"
        rm -f "$temp_json"
        return 1
    fi
    
    # Run ajv validation
    if ajv validate -s "$schema_file" -d "$temp_json" 2>/dev/null; then
        echo -e "${VAL_GREEN}✅ Schema validation passed${VAL_RESET}"
        rm -f "$temp_json"
        return 0
    else
        echo -e "${VAL_RED}❌ Schema validation failed${VAL_RESET}"
        echo -e "${VAL_CYAN}Running detailed validation...${VAL_RESET}"
        ajv validate -s "$schema_file" -d "$temp_json" --verbose 2>&1 || true
        rm -f "$temp_json"
        return 1
    fi
}

# Validate using basic yq checks (fallback)
validate_with_yq() {
    local config_file="$1"
    
    echo -e "${VAL_CYAN}🔍 Validating with basic yq checks...${VAL_RESET}"
    
    local errors=0
    
    # Check YAML syntax
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        echo -e "${VAL_RED}❌ Invalid YAML syntax${VAL_RESET}"
        ((errors++))
    fi
    
    # Check required top-level fields
    local required_fields=("cluster" "network" "nodes" "storage" "components")
    for field in "${required_fields[@]}"; do
        if ! yq eval "has(\"$field\")" "$config_file" | grep -q "true"; then
            echo -e "${VAL_RED}❌ Missing required field: $field${VAL_RESET}"
            ((errors++))
        fi
    done
    
    # Check cluster name format
    local cluster_name
    cluster_name=$(yq eval '.cluster.name' "$config_file")
    if [[ "$cluster_name" =~ [^a-z0-9-] ]]; then
        echo -e "${VAL_RED}❌ Invalid cluster name format: $cluster_name${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Must contain only lowercase letters, numbers, and hyphens${VAL_RESET}"
        ((errors++))
    fi
    
    # Check network subnet format
    local subnet
    subnet=$(yq eval '.network.subnet' "$config_file")
    if [[ ! "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${VAL_RED}❌ Invalid subnet format: $subnet${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Must be in CIDR notation (e.g., 192.168.50.0/24)${VAL_RESET}"
        ((errors++))
    fi
    
    # Check storage strategy
    local strategy
    strategy=$(yq eval '.storage.strategy' "$config_file")
    if [[ ! "$strategy" =~ ^(local-only|hybrid|longhorn|nfs-only)$ ]]; then
        echo -e "${VAL_RED}❌ Invalid storage strategy: $strategy${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Must be one of: local-only, hybrid, longhorn, nfs-only${VAL_RESET}"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo -e "${VAL_GREEN}✅ Basic validation passed${VAL_RESET}"
        return 0
    else
        echo -e "${VAL_RED}❌ Found $errors validation errors${VAL_RESET}"
        return 1
    fi
}

# Validate configuration file
validate_config_file() {
    local config_file="${1:-$DEFAULT_CONFIG}"
    local schema_file="${2:-$SCHEMA_FILE}"
    
    # Check if files exist
    if [[ ! -f "$config_file" ]]; then
        echo -e "${VAL_RED}❌ Configuration file not found: $config_file${VAL_RESET}"
        return 1
    fi
    
    if [[ ! -f "$schema_file" ]]; then
        echo -e "${VAL_YELLOW}⚠️  Schema file not found: $schema_file${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Using basic validation only${VAL_RESET}"
        validate_with_yq "$config_file"
        return $?
    fi
    
    # Try comprehensive validation first
    if check_ajv; then
        if validate_with_ajv "$config_file" "$schema_file"; then
            return 0
        else
            echo -e "${VAL_YELLOW}💡 You can also run basic validation with: $0 basic $config_file${VAL_RESET}"
            return 1
        fi
    else
        # Fallback to basic validation
        validate_with_yq "$config_file"
        return $?
    fi
}

# Show schema information
show_schema_info() {
    local schema_file="${1:-$SCHEMA_FILE}"
    
    if [[ ! -f "$schema_file" ]]; then
        echo -e "${VAL_RED}❌ Schema file not found: $schema_file${VAL_RESET}"
        return 1
    fi
    
    echo -e "${VAL_CYAN}📋 Zero Touch Cluster Configuration Schema${VAL_RESET}"
    echo ""
    
    # Extract schema metadata
    local title description version
    title=$(jq -r '.title // "N/A"' "$schema_file")
    description=$(jq -r '.description // "N/A"' "$schema_file")
    version=$(jq -r '."$id" // "N/A"' "$schema_file")
    
    echo "Title: $title"
    echo "Description: $description"
    echo "Schema ID: $version"
    echo ""
    
    echo -e "${VAL_CYAN}📊 Required Properties:${VAL_RESET}"
    jq -r '.required[]?' "$schema_file" | sed 's/^/  - /'
    echo ""
    
    echo -e "${VAL_CYAN}🔧 Available Storage Strategies:${VAL_RESET}"
    jq -r '.properties.storage.properties.strategy.enum[]?' "$schema_file" | sed 's/^/  - /'
    echo ""
    
    echo -e "${VAL_CYAN}📦 Available Workload Bundles:${VAL_RESET}"
    jq -r '.properties.workloads.properties.auto_deploy_bundles.items.enum[]?' "$schema_file" | sed 's/^/  - /'
}

# Command-line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-validate}" in
        "validate")
            validate_config_file "${2:-}" "${3:-}"
            ;;
        "basic")
            validate_with_yq "${2:-$DEFAULT_CONFIG}"
            ;;
        "info"|"schema")
            show_schema_info "${2:-}"
            ;;
        "help"|*)
            echo "ZTC Configuration Schema Validator"
            echo ""
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  validate [config] [schema]  Validate configuration file"
            echo "  basic [config]              Basic validation without schema"
            echo "  info [schema]               Show schema information"
            echo "  schema [schema]             Alias for info"
            echo "  help                        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 validate cluster.yaml"
            echo "  $0 basic cluster.yaml"
            echo "  $0 info schema/cluster-schema.json"
            echo ""
            echo "Schema validation requires ajv-cli:"
            echo "  npm install -g ajv-cli"
            ;;
    esac
fi