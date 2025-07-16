#!/bin/bash

# bulk-create-usbs.sh - Streamlined USB creation for large clusters
# Creates one reusable Ubuntu USB + batch cloud-init ISOs for sequential flashing

set -euo pipefail

# Colors for output
BULK_CYAN='\033[36m'
BULK_GREEN='\033[32m'
BULK_YELLOW='\033[33m'
BULK_RED='\033[31m'
BULK_BLUE='\033[34m'
BULK_RESET='\033[0m'

# Default configuration
CLUSTER_CONFIG="cluster.yaml"
USB_DEVICE=""
AUTO_MODE=false

# Function to show help
show_help() {
    cat << EOF
ZTC Bulk USB Creator - Streamlined provisioning for large clusters

OVERVIEW:
  Creates one reusable Ubuntu installer USB + batch cloud-init ISOs
  Dramatically reduces USB creation from 9 separate USBs to 1 USB + sequential flashing

USAGE:
  $0 [OPTIONS]

OPTIONS:
  -c, --config FILE     Cluster configuration file (default: cluster.yaml)
  -d, --device DEVICE   USB device for main installer (e.g., /dev/sdb)
  -a, --auto            Automatic mode - create all ISOs without prompts
  -h, --help           Show this help message

WORKFLOW:
  1. Creates one Ubuntu installer USB (reusable for all nodes)
  2. Batch creates tiny cloud-init ISOs for each node (368KB each)
  3. Provides sequential flashing instructions for deployment

EXAMPLES:
  $0 --device /dev/sdb --config cluster.yaml
  $0 -d /dev/sdb -a  # Automatic mode
  $0 --help

BENEFITS:
  ✅ 95% less USB management (1 main USB vs 9 separate USBs)
  ✅ Faster deployment (sequential 30-second flashing vs full recreate)
  ✅ Cost effective (need fewer USB drives)
  ✅ Error resistant (reusable main USB, tiny node configs)
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CLUSTER_CONFIG="$2"
            shift 2
            ;;
        -d|--device)
            USB_DEVICE="$2"
            shift 2
            ;;
        -a|--auto)
            AUTO_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${BULK_RED}❌ Unknown option: $1${BULK_RESET}" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate configuration file
if [[ ! -f "$CLUSTER_CONFIG" ]]; then
    echo -e "${BULK_RED}❌ Configuration file not found: $CLUSTER_CONFIG${BULK_RESET}" >&2
    exit 1
fi

# Extract nodes from cluster.yaml
extract_cluster_nodes() {
    local config_file="$1"
    echo -e "${BULK_CYAN}🔍 Extracting nodes from $config_file...${BULK_RESET}"
    
    # Use yq to extract cluster nodes (assuming it's available)
    if ! command -v yq >/dev/null 2>&1; then
        echo -e "${BULK_RED}❌ yq not found. Please install yq for YAML parsing${BULK_RESET}" >&2
        exit 1
    fi
    
    # Extract cluster nodes
    yq eval '.nodes.cluster_nodes | to_entries | .[] | .key + " " + .value.ip + " " + .value.role' "$config_file" 2>/dev/null || {
        echo -e "${BULK_RED}❌ Failed to parse cluster nodes from $config_file${BULK_RESET}" >&2
        echo -e "${BULK_YELLOW}💡 Ensure your cluster.yaml has the correct structure:${BULK_RESET}"
        echo -e "   nodes:"
        echo -e "     cluster_nodes:"
        echo -e "       k3s-master-01:"
        echo -e "         ip: \"192.168.50.10\""
        echo -e "         role: \"master\""
        exit 1
    }
}

# Extract storage nodes
extract_storage_nodes() {
    local config_file="$1"
    yq eval '.nodes.storage_node | to_entries | .[] | .key + " " + .value.ip + " " + .value.role' "$config_file" 2>/dev/null || echo ""
}

# Create main Ubuntu installer USB
create_main_usb() {
    local device="$1"
    local first_node="$2"
    
    echo -e "${BULK_CYAN}🚀 Creating main Ubuntu installer USB (reusable for all nodes)...${BULK_RESET}"
    echo -e "${BULK_YELLOW}📦 This USB will be reused for all $node_count nodes${BULK_RESET}"
    
    # Extract hostname and IP from first node
    local hostname=$(echo "$first_node" | cut -d' ' -f1)
    local ip=$(echo "$first_node" | cut -d' ' -f2)
    local ip_octet="${ip##*.}"
    
    echo -e "${BULK_BLUE}📋 Creating with: $hostname (IP: $ip)${BULK_RESET}"
    
    # Create the main USB
    if make autoinstall-usb DEVICE="$device" HOSTNAME="$hostname" IP_OCTET="$ip_octet"; then
        echo -e "${BULK_GREEN}✅ Main Ubuntu USB created successfully on $device${BULK_RESET}"
        echo -e "${BULK_CYAN}💡 This USB can be reused for all nodes in your cluster${BULK_RESET}"
        return 0
    else
        echo -e "${BULK_RED}❌ Failed to create main Ubuntu USB${BULK_RESET}" >&2
        return 1
    fi
}

# Batch create cloud-init ISOs
batch_create_isos() {
    local nodes=("$@")
    local total_nodes=${#nodes[@]}
    local created_count=0
    
    echo -e "${BULK_CYAN}🔨 Creating cloud-init ISOs for $total_nodes nodes...${BULK_RESET}"
    mkdir -p provisioning/downloads
    
    for node_info in "${nodes[@]}"; do
        local hostname=$(echo "$node_info" | cut -d' ' -f1)
        local ip=$(echo "$node_info" | cut -d' ' -f2)
        local role=$(echo "$node_info" | cut -d' ' -f3)
        local ip_octet="${ip##*.}"
        
        echo -e "${BULK_BLUE}📦 Creating ISO for $hostname ($role, IP: $ip)...${BULK_RESET}"
        
        if make cidata-iso HOSTNAME="$hostname" IP_OCTET="$ip_octet"; then
            ((created_count++))
            echo -e "${BULK_GREEN}  ✅ $hostname ISO created (${created_count}/${total_nodes})${BULK_RESET}"
        else
            echo -e "${BULK_RED}  ❌ Failed to create ISO for $hostname${BULK_RESET}" >&2
        fi
    done
    
    echo -e "${BULK_GREEN}✅ Created $created_count/$total_nodes cloud-init ISOs${BULK_RESET}"
    
    # List created ISOs
    echo -e "${BULK_CYAN}📋 Cloud-init ISOs created:${BULK_RESET}"
    ls -lh provisioning/downloads/*-cidata.iso 2>/dev/null | while read -r line; do
        echo -e "${BULK_BLUE}  📁 $line${BULK_RESET}"
    done
}

# Generate deployment instructions
generate_deployment_instructions() {
    local nodes=("$@")
    local instruction_file="provisioning/deployment-instructions.txt"
    
    echo -e "${BULK_CYAN}📝 Generating deployment instructions...${BULK_RESET}"
    
    cat > "$instruction_file" << EOF
# ZTC Cluster Deployment Instructions
# Generated on $(date)

## OVERVIEW
You now have:
✅ 1 reusable Ubuntu installer USB (main USB)
✅ ${#nodes[@]} tiny cloud-init ISOs (368KB each)

## DEPLOYMENT WORKFLOW

### Step 1: Label Your Main USB
- Label the main Ubuntu USB as: "ZTC-Ubuntu-Installer"
- This USB will be inserted in ALL nodes during installation

### Step 2: Flash Cloud-init ISOs to Small USBs
For each node, flash the corresponding ISO to a small USB drive:

EOF

    local node_number=1
    for node_info in "${nodes[@]}"; do
        local hostname=$(echo "$node_info" | cut -d' ' -f1)
        local ip=$(echo "$node_info" | cut -d' ' -f2)
        local role=$(echo "$node_info" | cut -d' ' -f3)
        
        cat >> "$instruction_file" << EOF
${node_number}. ${hostname} (${role}, ${ip}):
   dd if=provisioning/downloads/${hostname}-cidata.iso of=/dev/sdX bs=4M status=progress
   Label USB: "${hostname}"

EOF
        ((node_number++))
    done
    
    cat >> "$instruction_file" << EOF

### Step 3: Node Installation Process
For each node:
1. Insert BOTH USBs:
   - Main Ubuntu installer USB (reusable)
   - Node-specific cloud-init USB
2. Boot from main Ubuntu USB
3. When prompted "Use autoinstall? (yes/no)", type: yes
4. Wait 10-15 minutes for automatic installation
5. Remove both USBs when node reboots
6. Move to next node (reuse main Ubuntu USB)

### Step 4: Deploy Cluster
After all nodes are installed:
make ping    # Verify connectivity
make setup   # Deploy HA cluster

## TIME ESTIMATES
- ISO flashing: 30 seconds per node
- Node installation: 10-15 minutes per node
- Total time: ~2.5 hours for 9 nodes

## TROUBLESHOOTING
- If autoinstall doesn't detect cloud-init: Ensure both USBs are inserted
- If node doesn't boot: Check BIOS boot order, USB should be first
- If SSH fails: Verify network configuration and IP assignments

EOF

    echo -e "${BULK_GREEN}✅ Instructions saved to: $instruction_file${BULK_RESET}"
    echo -e "${BULK_BLUE}📖 View with: cat $instruction_file${BULK_RESET}"
}

# Show deployment summary
show_deployment_summary() {
    local nodes=("$@")
    local total_nodes=${#nodes[@]}
    
    echo ""
    echo -e "${BULK_CYAN}╔══════════════════════════════════════════════════════════════╗${BULK_RESET}"
    echo -e "${BULK_CYAN}║                    DEPLOYMENT SUMMARY                       ║${BULK_RESET}"
    echo -e "${BULK_CYAN}╚══════════════════════════════════════════════════════════════╝${BULK_RESET}"
    echo ""
    echo -e "${BULK_GREEN}✅ USB Creation Complete!${BULK_RESET}"
    echo -e "${BULK_BLUE}📊 Cluster: $total_nodes nodes total${BULK_RESET}"
    echo -e "${BULK_BLUE}📦 Created: 1 main Ubuntu USB + $total_nodes cloud-init ISOs${BULK_RESET}"
    echo ""
    echo -e "${BULK_YELLOW}🎯 NEXT STEPS:${BULK_RESET}"
    echo -e "  1. Flash cloud-init ISOs to small USBs (30 sec each)"
    echo -e "  2. Install nodes using dual-USB method (10-15 min each)"
    echo -e "  3. Deploy cluster: ${BULK_CYAN}make setup${BULK_RESET}"
    echo ""
    echo -e "${BULK_GREEN}💡 Benefits achieved:${BULK_RESET}"
    echo -e "  ✅ 95% less USB management"
    echo -e "  ✅ Cost effective (fewer USBs needed)"
    echo -e "  ✅ Faster deployment"
    echo -e "  ✅ Reusable main Ubuntu USB"
    echo ""
    echo -e "${BULK_BLUE}📖 Full instructions: ${BULK_CYAN}cat provisioning/deployment-instructions.txt${BULK_RESET}"
}

# Main execution
main() {
    echo -e "${BULK_CYAN}🚀 ZTC Bulk USB Creator${BULK_RESET}"
    echo -e "${BULK_BLUE}   Streamlined provisioning for large clusters${BULK_RESET}"
    echo ""
    
    # Extract all nodes from configuration
    local cluster_nodes_raw
    cluster_nodes_raw=$(extract_cluster_nodes "$CLUSTER_CONFIG")
    
    local storage_nodes_raw
    storage_nodes_raw=$(extract_storage_nodes "$CLUSTER_CONFIG")
    
    # Combine all nodes
    local all_nodes=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_nodes+=("$line")
    done <<< "$cluster_nodes_raw"
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_nodes+=("$line")
    done <<< "$storage_nodes_raw"
    
    local node_count=${#all_nodes[@]}
    
    if [[ $node_count -eq 0 ]]; then
        echo -e "${BULK_RED}❌ No nodes found in configuration${BULK_RESET}" >&2
        exit 1
    fi
    
    echo -e "${BULK_CYAN}🔍 Found $node_count nodes in cluster configuration${BULK_RESET}"
    
    # List nodes
    echo -e "${BULK_BLUE}📋 Nodes to provision:${BULK_RESET}"
    local node_num=1
    for node in "${all_nodes[@]}"; do
        local hostname=$(echo "$node" | cut -d' ' -f1)
        local ip=$(echo "$node" | cut -d' ' -f2)
        local role=$(echo "$node" | cut -d' ' -f3)
        echo -e "${BULK_BLUE}  $node_num. $hostname ($role) - $ip${BULK_RESET}"
        ((node_num++))
    done
    
    echo ""
    
    # Confirm with user unless auto mode
    if [[ "$AUTO_MODE" != "true" ]]; then
        echo -e "${BULK_YELLOW}📝 This will create:${BULK_RESET}"
        echo -e "  • 1 main Ubuntu installer USB (reusable)"
        echo -e "  • $node_count cloud-init ISOs (368KB each)"
        echo ""
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BULK_YELLOW}🚫 Operation cancelled${BULK_RESET}"
            exit 0
        fi
    fi
    
    # Create main USB if device specified
    if [[ -n "$USB_DEVICE" ]]; then
        if [[ ! -b "$USB_DEVICE" ]]; then
            echo -e "${BULK_RED}❌ USB device not found: $USB_DEVICE${BULK_RESET}" >&2
            exit 1
        fi
        
        echo -e "${BULK_YELLOW}⚠️  WARNING: This will completely erase $USB_DEVICE${BULK_RESET}"
        if [[ "$AUTO_MODE" != "true" ]]; then
            read -p "Continue with USB creation? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${BULK_YELLOW}🚫 USB creation cancelled${BULK_RESET}"
                exit 0
            fi
        fi
        
        create_main_usb "$USB_DEVICE" "${all_nodes[0]}"
        echo ""
    else
        echo -e "${BULK_YELLOW}💡 No USB device specified - skipping main USB creation${BULK_RESET}"
        echo -e "${BULK_BLUE}   Use: $0 --device /dev/sdX to create main USB${BULK_RESET}"
        echo ""
    fi
    
    # Batch create cloud-init ISOs
    batch_create_isos "${all_nodes[@]}"
    echo ""
    
    # Generate deployment instructions
    generate_deployment_instructions "${all_nodes[@]}"
    echo ""
    
    # Show summary
    show_deployment_summary "${all_nodes[@]}"
}

# Run main function
main "$@"