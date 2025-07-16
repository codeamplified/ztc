#!/bin/bash

# generate-inventory.sh - Generate Ansible inventory from cluster.yaml configuration
# This script converts cluster.yaml node definitions to Ansible inventory format

set -euo pipefail

# Source configuration reader utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-reader.sh"

# Default paths
INVENTORY_CONFIG_FILE="cluster.yaml"
INVENTORY_FILE="ansible/inventory/hosts.ini"

# Colors for output
GEN_CYAN='\033[36m'
GEN_GREEN='\033[32m'
GEN_YELLOW='\033[33m'
GEN_RED='\033[31m'
GEN_RESET='\033[0m'

# Function to generate inventory from configuration
generate_inventory() {
    local config_file="${1:-$INVENTORY_CONFIG_FILE}"
    local inventory_file="${2:-$INVENTORY_FILE}"
    
    echo -e "${GEN_CYAN}🔄 Generating Ansible inventory from configuration...${GEN_RESET}"
    
    # Validate configuration exists
    if ! get_config_file "$config_file" >/dev/null; then
        echo -e "${GEN_RED}❌ Configuration file not found: $config_file${GEN_RESET}" >&2
        return 1
    fi
    
    # Get SSH configuration
    local ssh_user ssh_key_path
    ssh_user=$(config_get_default "nodes.ssh.username" "ubuntu" "$config_file")
    ssh_key_path=$(config_get_default "nodes.ssh.key_path" "~/.ssh/id_ed25519" "$config_file")
    
    # Create inventory directory if it doesn't exist
    mkdir -p "$(dirname "$inventory_file")"
    
    # Generate inventory header
    cat > "$inventory_file" << EOF
# Homelab Ansible Inventory
# Generated from cluster.yaml configuration on $(date)
# DO NOT EDIT MANUALLY - Regenerate with: scripts/lib/generate-inventory.sh

[control]
# This is your workstation/control node - not part of the cluster
localhost ansible_connection=local

EOF
    
    # Collect master nodes first to determine HA setup
    local master_nodes=()
    local nodes
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local role ip
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        ip=$(config_get "nodes.cluster_nodes.$node.ip" "$config_file")
        
        if [[ "$role" == "master" ]]; then
            master_nodes+=("$node:$ip")
        fi
    done <<< "$nodes"
    
    local master_count=${#master_nodes[@]}
    local is_ha_cluster=false
    
    if [[ $master_count -eq 0 ]]; then
        echo -e "${GEN_YELLOW}⚠️  No master node found in configuration${GEN_RESET}" >&2
    elif [[ $master_count -gt 1 ]]; then
        is_ha_cluster=true
        echo -e "${GEN_CYAN}🔀 Detected HA cluster with $master_count masters${GEN_RESET}"
    fi
    
    if [[ "$is_ha_cluster" == "true" ]]; then
        # Generate HA master sections
        echo "[k3s_master_first]" >> "$inventory_file"
        echo "# k3s first master node (cluster initialization)" >> "$inventory_file"
        local first_master="${master_nodes[0]}"
        local node_name="${first_master%%:*}"
        local node_ip="${first_master##*:}"
        echo "$node_name ansible_host=$node_ip ansible_user=$ssh_user k3s_node_role=master_first" >> "$inventory_file"
        echo "" >> "$inventory_file"
        
        echo "[k3s_master_additional]" >> "$inventory_file"
        echo "# k3s additional master nodes (join existing cluster)" >> "$inventory_file"
        for ((i=1; i<master_count; i++)); do
            local master_node="${master_nodes[$i]}"
            local node_name="${master_node%%:*}"
            local node_ip="${master_node##*:}"
            echo "$node_name ansible_host=$node_ip ansible_user=$ssh_user k3s_node_role=master_additional" >> "$inventory_file"
        done
        echo "" >> "$inventory_file"
        
        echo "[k3s_master:children]" >> "$inventory_file"
        echo "# All k3s master nodes" >> "$inventory_file"
        echo "k3s_master_first" >> "$inventory_file"
        echo "k3s_master_additional" >> "$inventory_file"
        echo "" >> "$inventory_file"
    else
        # Generate single master section
        echo "[k3s_master]" >> "$inventory_file"
        echo "# k3s control plane node" >> "$inventory_file"
        
        if [[ $master_count -eq 1 ]]; then
            local master_node="${master_nodes[0]}"
            local node_name="${master_node%%:*}"
            local node_ip="${master_node##*:}"
            echo "$node_name ansible_host=$node_ip ansible_user=$ssh_user k3s_node_role=master_single" >> "$inventory_file"
        fi
        echo "" >> "$inventory_file"
    fi
    
    # Generate k3s workers section
    echo "[k3s_workers]" >> "$inventory_file"
    echo "# k3s worker nodes" >> "$inventory_file"
    
    nodes=$(config_get_keys "nodes.cluster_nodes" "$config_file")
    while read -r node; do
        [[ -z "$node" ]] && continue
        local role ip
        role=$(config_get "nodes.cluster_nodes.$node.role" "$config_file")
        ip=$(config_get "nodes.cluster_nodes.$node.ip" "$config_file")
        
        if [[ "$role" == "worker" ]]; then
            echo "$node ansible_host=$ip ansible_user=$ssh_user" >> "$inventory_file"
        fi
    done <<< "$nodes"
    
    echo "" >> "$inventory_file"
    
    # Generate combined groups
    cat >> "$inventory_file" << EOF
[k3s_cluster:children]
k3s_master
k3s_workers

[all_nodes:children]
k3s_cluster

[all_nodes:vars]
ansible_ssh_private_key_file=$ssh_key_path
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3
EOF
    
    # Add HA-specific variables if multi-master cluster
    if [[ "$is_ha_cluster" == "true" ]]; then
        echo "" >> "$inventory_file"
        echo "[k3s_cluster:vars]" >> "$inventory_file"
        echo "# High Availability configuration" >> "$inventory_file"
        echo "k3s_ha_cluster=true" >> "$inventory_file"
        echo "k3s_master_count=$master_count" >> "$inventory_file"
        
        # Check for HA configuration in cluster.yaml
        local ha_enabled virtual_ip lb_type lb_port
        ha_enabled=$(config_get_default "cluster.ha_config.enabled" "true" "$config_file")
        virtual_ip=$(config_get_default "cluster.ha_config.virtual_ip" "" "$config_file")
        lb_type=$(config_get_default "cluster.ha_config.load_balancer.type" "kube-vip" "$config_file")
        lb_port=$(config_get_default "cluster.ha_config.load_balancer.port" "6443" "$config_file")
        
        echo "k3s_ha_enabled=$ha_enabled" >> "$inventory_file"
        [[ -n "$virtual_ip" ]] && echo "k3s_virtual_ip=$virtual_ip" >> "$inventory_file"
        echo "k3s_load_balancer_type=$lb_type" >> "$inventory_file"
        echo "k3s_load_balancer_port=$lb_port" >> "$inventory_file"
        
        # Add first master IP for join operations
        local first_master_ip="${master_nodes[0]##*:}"
        echo "k3s_first_master_ip=$first_master_ip" >> "$inventory_file"
        
        # Recommend odd number of masters for proper quorum
        if [[ $((master_count % 2)) -eq 0 ]]; then
            echo -e "${GEN_YELLOW}⚠️  Warning: Even number of masters ($master_count) detected${GEN_RESET}"
            echo -e "${GEN_YELLOW}   Consider using odd number (3, 5, 7) for proper etcd quorum${GEN_RESET}"
        fi
    else
        echo "" >> "$inventory_file"
        echo "[k3s_cluster:vars]" >> "$inventory_file"
        echo "# Single master configuration" >> "$inventory_file"
        echo "k3s_ha_cluster=false" >> "$inventory_file"
        echo "k3s_master_count=1" >> "$inventory_file"
    fi
    
    echo -e "${GEN_GREEN}✅ Inventory generated: $inventory_file${GEN_RESET}"
    
    # Show summary
    echo -e "${GEN_CYAN}📋 Generated inventory summary:${GEN_RESET}"
    local master_count worker_count
    master_count=$(grep -c "ansible_host=" "$inventory_file" | grep -A 10 "\[k3s_master\]" | grep -c "ansible_host=" || echo "0")
    worker_count=$(grep -A 20 "\[k3s_workers\]" "$inventory_file" | grep -c "ansible_host=" || echo "0")
    
    echo "  Master nodes: $master_count"
    echo "  Worker nodes: $worker_count"
    echo "  SSH user: $ssh_user"
    echo "  SSH key: $ssh_key_path"
}

# Function to validate generated inventory
validate_inventory() {
    local inventory_file="${1:-$INVENTORY_FILE}"
    
    echo -e "${GEN_CYAN}🔍 Validating generated inventory...${GEN_RESET}"
    
    if [[ ! -f "$inventory_file" ]]; then
        echo -e "${GEN_RED}❌ Inventory file not found: $inventory_file${GEN_RESET}" >&2
        return 1
    fi
    
    # Check for required sections
    local required_sections=("k3s_master" "k3s_workers")
    for section in "${required_sections[@]}"; do
        if ! grep -q "\\[$section\\]" "$inventory_file"; then
            echo -e "${GEN_RED}❌ Missing section: $section${GEN_RESET}" >&2
            return 1
        fi
    done
    
    # Check for at least one master node
    if ! grep -A 5 "\\[k3s_master\\]" "$inventory_file" | grep -q "ansible_host="; then
        echo -e "${GEN_RED}❌ No master node defined${GEN_RESET}" >&2
        return 1
    fi
    
    echo -e "${GEN_GREEN}✅ Inventory validation passed${GEN_RESET}"
    return 0
}

# Function to show inventory diff
show_inventory_diff() {
    local new_inventory_file="${1:-$INVENTORY_FILE}"
    local backup_file="${new_inventory_file}.backup"
    
    if [[ -f "$backup_file" ]]; then
        echo -e "${GEN_CYAN}📋 Inventory changes:${GEN_RESET}"
        if command -v diff >/dev/null 2>&1; then
            diff -u "$backup_file" "$new_inventory_file" || true
        else
            echo -e "${GEN_YELLOW}⚠️  diff command not available${GEN_RESET}"
        fi
    else
        echo -e "${GEN_YELLOW}⚠️  No backup file found for comparison${GEN_RESET}"
    fi
}

# Function to backup existing inventory
backup_inventory() {
    local inventory_file="${1:-$INVENTORY_FILE}"
    
    if [[ -f "$inventory_file" ]]; then
        local backup_file="${inventory_file}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$inventory_file" "$backup_file"
        echo -e "${GEN_YELLOW}📦 Backup created: $backup_file${GEN_RESET}"
        
        # Also create a simple .backup for diff
        cp "$inventory_file" "${inventory_file}.backup"
    fi
}

# Function to update inventory with configuration changes
update_inventory() {
    local config_file="${1:-$INVENTORY_CONFIG_FILE}"
    local inventory_file="${2:-$INVENTORY_FILE}"
    
    echo -e "${GEN_CYAN}🔄 Updating inventory from configuration...${GEN_RESET}"
    
    # Backup existing inventory
    backup_inventory "$inventory_file"
    
    # Generate new inventory
    generate_inventory "$config_file" "$inventory_file"
    
    # Validate the result
    if validate_inventory "$inventory_file"; then
        echo -e "${GEN_GREEN}✅ Inventory updated successfully${GEN_RESET}"
        show_inventory_diff "$inventory_file"
    else
        echo -e "${GEN_RED}❌ Generated inventory is invalid${GEN_RESET}" >&2
        return 1
    fi
}

# If script is run directly, provide command-line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        "generate")
            generate_inventory "${2:-}" "${3:-}"
            ;;
        "validate")
            validate_inventory "${2:-}"
            ;;
        "update")
            update_inventory "${2:-}" "${3:-}"
            ;;
        "diff")
            show_inventory_diff "${2:-}"
            ;;
        "backup")
            backup_inventory "${2:-}"
            ;;
        "help"|*)
            echo "ZTC Inventory Generator"
            echo ""
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  generate [config] [inventory]  Generate inventory from configuration"
            echo "  validate [inventory]           Validate inventory file"
            echo "  update [config] [inventory]    Update inventory with backup"
            echo "  diff [inventory]               Show changes from backup"
            echo "  backup [inventory]             Create backup of inventory"
            echo "  help                           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 generate"
            echo "  $0 update"
            echo "  $0 validate"
            echo "  $0 diff"
            ;;
    esac
fi