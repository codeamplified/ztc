#!/bin/bash

# validate-ha-config.sh - Validate HA cluster configuration
# This script checks cluster.yaml for proper multi-master setup

set -euo pipefail

# Source configuration reader utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-reader.sh"

# Default paths
CONFIG_FILE="cluster.yaml"

# Colors for output
VAL_CYAN='\033[36m'
VAL_GREEN='\033[32m'
VAL_YELLOW='\033[33m'
VAL_RED='\033[31m'
VAL_RESET='\033[0m'

# Function to validate HA configuration
validate_ha_config() {
    local config_file="${1:-$CONFIG_FILE}"
    local has_errors=false
    
    echo -e "${VAL_CYAN}🔍 Validating HA cluster configuration...${VAL_RESET}"
    
    # Check if configuration file exists
    if ! get_config_file "$config_file" >/dev/null; then
        echo -e "${VAL_RED}❌ Configuration file not found: $config_file${VAL_RESET}" >&2
        return 1
    fi
    
    # Count master nodes
    local master_count=0
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local role
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        if [[ "$role" == "master" ]]; then
            ((master_count++))
        fi
    done <<< "$nodes"
    
    echo -e "${VAL_CYAN}📊 Master node count: $master_count${VAL_RESET}"
    
    # Validate master count for HA
    if [[ $master_count -eq 0 ]]; then
        echo -e "${VAL_RED}❌ No master nodes found in configuration${VAL_RESET}"
        has_errors=true
    elif [[ $master_count -eq 1 ]]; then
        echo -e "${VAL_GREEN}✅ Single master configuration (no HA)${VAL_RESET}"
        return 0  # Single master is valid, no HA validation needed
    elif [[ $master_count -eq 2 ]]; then
        echo -e "${VAL_YELLOW}⚠️  Warning: 2 masters detected - no quorum advantage${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Consider using 3 masters for proper etcd quorum${VAL_RESET}"
    elif [[ $((master_count % 2)) -eq 0 ]]; then
        echo -e "${VAL_YELLOW}⚠️  Warning: Even number of masters ($master_count)${VAL_RESET}"
        echo -e "${VAL_YELLOW}   Odd number (3, 5, 7) recommended for etcd quorum${VAL_RESET}"
    else
        echo -e "${VAL_GREEN}✅ Good: Odd number of masters ($master_count) for proper quorum${VAL_RESET}"
    fi
    
    # Check HA configuration if multiple masters
    if [[ $master_count -gt 1 ]]; then
        echo -e "${VAL_CYAN}🔀 Validating HA configuration for $master_count masters...${VAL_RESET}"
        
        # Check for HA config section
        local ha_enabled virtual_ip lb_type
        ha_enabled=$(config_get_default "cluster.ha_config.enabled" "auto" "$config_file")
        virtual_ip=$(config_get_default "cluster.ha_config.virtual_ip" "" "$config_file")
        lb_type=$(config_get_default "cluster.ha_config.load_balancer.type" "kube-vip" "$config_file")
        
        # Validate virtual IP if provided
        if [[ -n "$virtual_ip" ]]; then
            if [[ ! "$virtual_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo -e "${VAL_RED}❌ Invalid virtual IP format: $virtual_ip${VAL_RESET}"
                has_errors=true
            else
                echo -e "${VAL_GREEN}✅ Virtual IP configured: $virtual_ip${VAL_RESET}"
            fi
        else
            echo -e "${VAL_YELLOW}⚠️  No virtual IP configured - workers will connect to first master${VAL_RESET}"
        fi
        
        # Validate load balancer type
        case "$lb_type" in
            "kube-vip"|"haproxy"|"nginx"|"external")
                echo -e "${VAL_GREEN}✅ Load balancer type: $lb_type${VAL_RESET}"
                ;;
            *)
                echo -e "${VAL_RED}❌ Invalid load balancer type: $lb_type${VAL_RESET}"
                echo -e "${VAL_RED}   Supported: kube-vip, haproxy, nginx, external${VAL_RESET}"
                has_errors=true
                ;;
        esac
        
        # Check network subnet for VIP conflicts
        if [[ -n "$virtual_ip" ]]; then
            local subnet
            subnet=$(config_get "network.subnet" "$config_file")
            local subnet_base="${subnet%.*}"
            local vip_base="${virtual_ip%.*}"
            
            if [[ "$subnet_base" != "$vip_base" ]]; then
                echo -e "${VAL_YELLOW}⚠️  Virtual IP ($virtual_ip) not in cluster subnet ($subnet)${VAL_RESET}"
            fi
        fi
        
        # Check for IP conflicts with existing nodes
        if [[ -n "$virtual_ip" ]]; then
            while read -r node; do
                [[ -z "$node" ]] && continue
                local node_ip
                node_ip=$(config_get "nodes.cluster_nodes.$node.ip" "$config_file")
                if [[ "$node_ip" == "$virtual_ip" ]]; then
                    echo -e "${VAL_RED}❌ Virtual IP conflicts with node $node: $virtual_ip${VAL_RESET}"
                    has_errors=true
                fi
            done <<< "$nodes"
            
            # Check storage nodes too
            if config_has "nodes.storage_node" "$config_file"; then
                local storage_nodes
                storage_nodes=$(config_get_keys "nodes.storage_node" "$config_file")
                while read -r node; do
                    [[ -z "$node" ]] && continue
                    local node_ip
                    node_ip=$(config_get "nodes.storage_node.$node.ip" "$config_file")
                    if [[ "$node_ip" == "$virtual_ip" ]]; then
                        echo -e "${VAL_RED}❌ Virtual IP conflicts with storage node $node: $virtual_ip${VAL_RESET}"
                        has_errors=true
                    fi
                done <<< "$storage_nodes"
            fi
        fi
    fi
    
    # Final validation result
    if [[ "$has_errors" == "true" ]]; then
        echo -e "${VAL_RED}❌ HA configuration validation failed${VAL_RESET}"
        return 1
    else
        echo -e "${VAL_GREEN}✅ HA configuration validation passed${VAL_RESET}"
        return 0
    fi
}

# Function to suggest HA improvements
suggest_ha_improvements() {
    local config_file="${1:-$CONFIG_FILE}"
    
    echo -e "${VAL_CYAN}💡 HA Configuration Suggestions:${VAL_RESET}"
    
    # Count masters
    local master_count=0
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local role
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        if [[ "$role" == "master" ]]; then
            ((master_count++))
        fi
    done <<< "$nodes"
    
    if [[ $master_count -gt 1 ]]; then
        local virtual_ip
        virtual_ip=$(config_get_default "cluster.ha_config.virtual_ip" "" "$config_file")
        
        if [[ -z "$virtual_ip" ]]; then
            local subnet
            subnet=$(config_get "network.subnet" "$config_file")
            local suggested_vip="${subnet%.*}.30"
            
            echo -e "  • Consider adding a virtual IP for load balancing:"
            echo -e "    ${VAL_YELLOW}cluster.ha_config.virtual_ip: \"$suggested_vip\"${VAL_RESET}"
            echo ""
        fi
        
        if [[ $master_count -eq 2 ]]; then
            echo -e "  • Consider adding a third master for true HA quorum"
            echo -e "  • With 2 masters, if one fails, remaining master cannot form quorum"
            echo ""
        fi
        
        if [[ $((master_count % 2)) -eq 0 && $master_count -gt 2 ]]; then
            echo -e "  • Consider using odd number of masters (3, 5, 7) for optimal etcd quorum"
            echo ""
        fi
    fi
    
    echo -e "  • For production HA clusters, consider:"
    echo -e "    - Separate network interfaces for cluster traffic"
    echo -e "    - External load balancer for API server access"
    echo -e "    - Backup strategy for etcd data"
    echo -e "    - Monitoring for cluster health"
}

# If script is run directly, provide command-line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-validate}" in
        "validate")
            validate_ha_config "${2:-}"
            ;;
        "suggest")
            suggest_ha_improvements "${2:-}"
            ;;
        "help"|*)
            echo "ZTC HA Configuration Validator"
            echo ""
            echo "Usage: $0 <command> [config_file]"
            echo ""
            echo "Commands:"
            echo "  validate [config]    Validate HA configuration"
            echo "  suggest [config]     Suggest HA improvements"
            echo "  help                 Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 validate"
            echo "  $0 validate cluster.yaml"
            echo "  $0 suggest"
            ;;
    esac
fi