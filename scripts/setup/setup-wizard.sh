#!/bin/bash

# Zero Touch Cluster Setup Wizard - Enhanced Configuration Generator

set -euo pipefail

# Source configuration reader utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config-reader.sh"

# Color codes
CYAN() { echo -e "\033[36m$*\033[0m"; }
GREEN() { echo -e "\033[32m$*\033[0m"; }
YELLOW() { echo -e "\033[33m$*\033[0m"; }
RED() { echo -e "\033[31m$*\033[0m"; }

# Function to check for a command
check_command() {
    if ! command -v "$1" &> /dev/null; then
        RED "Error: '$1' command not found."
        YELLOW "Please install it and re-run 'make setup'."
        exit 1
    fi
}

# Function to prompt for a secret
prompt_secret() {
    local prompt_text="$1"
    local user_input

    printf "$(CYAN "${prompt_text}"): "
    read user_input
    echo "$user_input"
}

# Function to prompt for user input with default
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    # Check if running in interactive terminal
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        printf "$(CYAN "${prompt_text}") [$(YELLOW "${default_value}")]: "
        read user_input
        echo "${user_input:-$default_value}"
    else
        # Non-interactive mode - return default
        echo "$default_value"
    fi
}

# Function to prompt for yes/no with default
prompt_yes_no() {
    local prompt_text="$1"
    local default_value="${2:-y}"
    local user_input

    # Check if running in interactive terminal
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        printf "$(CYAN "${prompt_text}") [$(YELLOW "${default_value}")]: "
        read user_input
        user_input="${user_input:-$default_value}"
    else
        # Non-interactive mode - return default
        user_input="$default_value"
    fi
    
    case "$user_input" in
        [Yy]|[Yy][Ee][Ss]) echo "true" ;;
        [Nn]|[Nn][Oo]) echo "false" ;;
        *) echo "$default_value" ;;
    esac
}

# Function to select from multiple options
prompt_select() {
    local prompt_text="$1"
    shift
    local options=("$@")
    local default_option="${options[0]}"
    
    # Check if running in interactive terminal
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        echo
        CYAN "$prompt_text"
        for i in "${!options[@]}"; do
            if [[ "$i" -eq 0 ]]; then
                YELLOW "  $((i+1)). ${options[$i]} (default)"
            else
                echo "  $((i+1)). ${options[$i]}"
            fi
        done
        
        printf "$(CYAN "Select option") [$(YELLOW "1")]: "
        local user_input
        read user_input
        user_input="${user_input:-1}"
        
        if [[ "$user_input" =~ ^[0-9]+$ ]] && [[ "$user_input" -ge 1 ]] && [[ "$user_input" -le "${#options[@]}" ]]; then
            echo "${options[$((user_input-1))]}"
        else
            echo "$default_option"
        fi
    else
        # Non-interactive mode - return default
        echo "$default_option"
    fi
}

# Function to generate cluster configuration
generate_cluster_config() {
    local config_file="${1:-cluster.yaml}"
    
    # Check if running in non-interactive mode
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        GREEN "\n--- Non-Interactive Configuration Generation ---"
        CYAN "Generating cluster.yaml using homelab template with default settings"
        
        # Use homelab template directly in non-interactive mode
        local template_file="templates/cluster-homelab.yaml"
        if [[ -f "$template_file" ]]; then
            if [[ -f "$config_file" ]]; then
                cp "$config_file" "${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
                YELLOW "📦 Backup created: ${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
            fi
            cp "$template_file" "$config_file"
            GREEN "✅ Configuration generated from homelab template"
            return 0
        else
            RED "❌ Template not found, generating minimal configuration"
            generate_minimal_config "$config_file"
            return 0
        fi
    fi
    
    GREEN "\n--- Interactive Cluster Configuration Generator ---"
    CYAN "This will create a customized cluster.yaml configuration file."
    echo
    
    # Check if config already exists
    if [[ -f "$config_file" ]]; then
        YELLOW "⚠️  Configuration file already exists: $config_file"
        local overwrite
        overwrite=$(prompt_yes_no "Do you want to overwrite it?" "n")
        if [[ "$overwrite" != "true" ]]; then
            # Create backup
            cp "$config_file" "${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
            YELLOW "📦 Backup created: ${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
        fi
    fi
    
    # Configuration template selection
    CYAN "\n🎯 Step 1: Choose Configuration Template"
    local template
    template=$(prompt_select "Select a configuration template:" \
        "homelab" \
        "small" \
        "production" \
        "custom")
    
    if [[ "$template" != "custom" ]]; then
        # Use template as base
        local template_file="templates/cluster-$template.yaml"
        if [[ -f "$template_file" ]]; then
            cp "$template_file" "$config_file"
            GREEN "✅ Using template: $template"
        else
            YELLOW "⚠️  Template not found, using custom configuration"
            template="custom"
        fi
    fi
    
    if [[ "$template" == "custom" ]]; then
        # Generate custom configuration
        CYAN "\n🌐 Step 2: Network Configuration"
        local subnet domain
        subnet=$(prompt_with_default "Cluster subnet (CIDR)" "192.168.50.0/24")
        domain=$(prompt_with_default "DNS domain" "homelab.lan")
        
        CYAN "\n🏗️  Step 3: Storage Configuration"
        local default_storage_class enable_longhorn enable_nfs
        default_storage_class=$(prompt_select "Default storage class:" \
            "local-path" \
            "longhorn" \
            "nfs-csi")
        
        enable_longhorn="false"
        enable_nfs="false"
        if [[ "$default_storage_class" == "longhorn" ]]; then
            enable_longhorn="true"
        elif [[ "$default_storage_class" == "nfs-csi" ]]; then
            enable_nfs="true"
            enable_longhorn="true"  # NFS server needs backend storage
        fi
        
        CYAN "\n🖥️  Step 4: Node Configuration"
        local cluster_name
        cluster_name=$(prompt_with_default "Cluster name" "ztc-homelab")
        
        CYAN "\n📦 Step 5: Components Configuration"
        local enable_monitoring enable_gitea enable_homepage
        enable_monitoring=$(prompt_yes_no "Enable monitoring stack (Prometheus, Grafana)?" "y")
        enable_gitea=$(prompt_yes_no "Enable Gitea Git server?" "y")
        enable_homepage=$(prompt_yes_no "Enable Homepage dashboard?" "y")
        
        CYAN "\n🚀 Step 6: Workload Bundles"
        local auto_bundles
        auto_bundles=$(prompt_select "Auto-deploy workload bundles:" \
            "none" \
            "starter" \
            "monitoring" \
            "productivity" \
            "security")
        
        # Generate configuration from scratch
        generate_custom_config "$config_file" "$cluster_name" "$subnet" "$domain" \
            "$default_storage_class" "$enable_longhorn" "$enable_nfs" "$enable_monitoring" "$enable_gitea" "$enable_homepage" "$auto_bundles"
    else
        # Customize template
        CYAN "\n✏️  Step 2: Customize Template"
        local customize
        customize=$(prompt_yes_no "Do you want to customize the template?" "n")
        
        if [[ "$customize" == "true" ]]; then
            customize_template_config "$config_file"
        fi
    fi
    
    # Validate configuration
    CYAN "\n🔍 Step 3: Configuration Validation"
    if validate_config "$config_file"; then
        GREEN "✅ Configuration validation passed"
    else
        RED "❌ Configuration validation failed"
        local fix_config
        fix_config=$(prompt_yes_no "Do you want to edit the configuration manually?" "y")
        if [[ "$fix_config" == "true" ]]; then
            ${EDITOR:-nano} "$config_file"
            validate_config "$config_file"
        fi
    fi
    
    # Show summary
    CYAN "\n📋 Final Configuration Summary"
    show_config_summary "$config_file"
    
    GREEN "\n✅ Cluster configuration generated: $config_file"
}

# Function to generate custom configuration from scratch
generate_custom_config() {
    local config_file="$1"
    local cluster_name="$2"
    local subnet="$3"
    local domain="$4"
    local default_storage_class="$5"
    local enable_longhorn="$6"
    local enable_nfs="$7"
    local enable_monitoring="$8"
    local enable_gitea="$9"
    local enable_homepage="${10}"
    local auto_bundles="${11}"
    
    # Extract network base from subnet
    local network_base
    network_base=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
    
    # Generate bundle array
    local bundles_yaml=""
    if [[ "$auto_bundles" != "none" ]]; then
        bundles_yaml="  auto_deploy_bundles:\n    - \"$auto_bundles\""
    else
        bundles_yaml="  auto_deploy_bundles: []"
    fi
    
    # Storage configuration based on enabled features
    local storage_config="  local_path:\n    enabled: true"
    
    # Note: Default storage class is set via storage.default_storage_class field only
    
    # NFS configuration
    storage_config+="\n  nfs:\n    enabled: $enable_nfs"
    if [[ "$enable_nfs" == "true" ]]; then
        storage_config+="\n    namespace: \"nfs-server\""
        storage_config+="\n    backend_storage_class: \"longhorn\""
        storage_config+="\n    storage_size: \"250Gi\""
        storage_config+="\n    storage_class:"
        storage_config+="\n      name: \"nfs-csi\""
    fi
    
    # Longhorn configuration
    storage_config+="\n  longhorn:\n    enabled: $enable_longhorn"
    if [[ "$enable_longhorn" == "true" ]]; then
        storage_config+="\n    replica_count: 3"
        storage_config+="\n    storage_class:"
        storage_config+="\n      name: \"longhorn\""
    fi
    
    # Generate configuration file
    cat > "$config_file" << EOF
# yaml-language-server: \$schema=./schema/cluster-schema.json
# Zero Touch Cluster Configuration
# Generated by setup wizard on $(date)

cluster:
  name: "$cluster_name"
  description: "Zero Touch Cluster - Generated configuration"
  version: "1.0.0"

network:
  subnet: "$subnet"
  gateway: "$network_base.1"
  pod_cidr: "10.42.0.0/16"
  service_cidr: "10.43.0.0/16"
  dns:
    enabled: true
    server_ip: "$network_base.20"
    domain: "$domain"

nodes:
  ssh:
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
    username: "ubuntu"
    
  cluster_nodes:
    k3s-master:
      ip: "$network_base.10"
      role: "master"
    k3s-worker-01:
      ip: "$network_base.11"
      role: "worker"
    k3s-worker-02:
      ip: "$network_base.12"
      role: "worker"
    k3s-worker-03:
      ip: "$network_base.13"
      role: "worker"
  
  storage_node:
    k8s-storage:
      ip: "$network_base.20"
      role: "storage"

storage:
  default_storage_class: "$default_storage_class"
$storage_config

components:
  sealed_secrets:
    enabled: true
  argocd:
    enabled: true
  monitoring:
    enabled: $enable_monitoring
  gitea:
    enabled: $enable_gitea
  homepage:
    enabled: $enable_homepage
  minio:
    enabled: false

workloads:
$bundles_yaml

deployment:
  phases:
    infrastructure: true
    secrets: true
    networking: true
    storage: true
    system_components: true
    gitops: true
    workloads: true

advanced:
  security:
    auto_generate_passwords: true
    password_length: 32
EOF
}

# Function to generate minimal configuration for non-interactive mode
generate_minimal_config() {
    local config_file="$1"
    
    cat > "$config_file" << 'EOF'
# yaml-language-server: $schema=./schema/cluster-schema.json
# Zero Touch Cluster Configuration - Generated (Non-Interactive)

cluster:
  name: "ztc-homelab"
  description: "Zero Touch Cluster - Auto-generated configuration"
  version: "1.0.0"

network:
  subnet: "192.168.50.0/24"
  gateway: "192.168.50.1"
  pod_cidr: "10.42.0.0/16"
  service_cidr: "10.43.0.0/16"
  dns:
    enabled: true
    server_ip: "192.168.50.20"
    domain: "homelab.lan"

nodes:
  ssh:
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
    username: "ubuntu"
    
  cluster_nodes:
    k3s-master:
      ip: "192.168.50.10"
      role: "master"
    k3s-worker-01:
      ip: "192.168.50.11"
      role: "worker"
    k3s-worker-02:
      ip: "192.168.50.12"
      role: "worker"
    k3s-worker-03:
      ip: "192.168.50.13"
      role: "worker"
  
  storage_node:
    k8s-storage:
      ip: "192.168.50.20"
      role: "storage"

storage:
  default_storage_class: "local-path"
  local_path:
    enabled: true
    is_default: true
  nfs:
    enabled: false
  longhorn:
    enabled: false

components:
  sealed_secrets:
    enabled: true
  argocd:
    enabled: true
  monitoring:
    enabled: true
  gitea:
    enabled: true
  homepage:
    enabled: true
  minio:
    enabled: false

workloads:
  auto_deploy_bundles: []

deployment:
  phases:
    infrastructure: true
    secrets: true
    networking: true
    storage: true
    system_components: true
    gitops: true
    workloads: true

advanced:
  security:
    auto_generate_passwords: true
    password_length: 32
EOF
    
    GREEN "✅ Minimal configuration generated"
}

# Function to customize template configuration
customize_template_config() {
    local config_file="$1"
    
    CYAN "Customizing template configuration..."
    echo
    
    # Get current values
    local current_name current_subnet current_domain
    current_name=$(config_get "cluster.name" "$config_file")
    current_subnet=$(config_get "network.subnet" "$config_file")
    current_domain=$(config_get "network.dns.domain" "$config_file")
    
    # Prompt for customizations
    local new_name new_subnet new_domain
    new_name=$(prompt_with_default "Cluster name" "$current_name")
    new_subnet=$(prompt_with_default "Network subnet" "$current_subnet")
    new_domain=$(prompt_with_default "DNS domain" "$current_domain")
    
    # Update configuration
    check_yq
    yq eval ".cluster.name = \"$new_name\"" -i "$config_file"
    yq eval ".network.subnet = \"$new_subnet\"" -i "$config_file"
    yq eval ".network.dns.domain = \"$new_domain\"" -i "$config_file"
    
    # Update node IPs based on new subnet
    if [[ "$new_subnet" != "$current_subnet" ]]; then
        local network_base
        network_base=$(echo "$new_subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
        
        yq eval ".network.dns.server_ip = \"$network_base.20\"" -i "$config_file"
        yq eval ".nodes.cluster_nodes.\"k3s-master\".ip = \"$network_base.10\"" -i "$config_file"
        yq eval ".nodes.cluster_nodes.\"k3s-worker-01\".ip = \"$network_base.11\"" -i "$config_file"
        yq eval ".nodes.cluster_nodes.\"k3s-worker-02\".ip = \"$network_base.12\"" -i "$config_file"
        yq eval ".nodes.cluster_nodes.\"k3s-worker-03\".ip = \"$network_base.13\"" -i "$config_file"
        
        if config_has "nodes.storage_node" "$config_file"; then
            yq eval ".nodes.storage_node.\"k8s-storage\".ip = \"$network_base.20\"" -i "$config_file"
        fi
        
        if config_has "storage.nfs.server.ip" "$config_file"; then
            yq eval ".storage.nfs.server.ip = \"$network_base.20\"" -i "$config_file"
        fi
    fi
    
    GREEN "✅ Template customized successfully"
}

# --- Main Script ---

GREEN "=== Zero Touch Cluster Setup Wizard ==="
CYAN "This wizard will guide you through:"
CYAN "1. Cluster configuration generation (cluster.yaml)"
CYAN "2. Infrastructure secrets creation (Ansible vault)"
CYAN "Application secrets will be generated automatically after cluster deployment."
echo

# 1. Check dependencies
GREEN "--- Checking Dependencies ---"
check_command ansible-vault
check_command kubeseal
check_command kubectl
check_command yq
GREEN "✅ All dependencies checked."

# 2. Generate cluster configuration
generate_cluster_config "cluster.yaml"

# 3. Ansible Vault Password
GREEN "\n--- Ansible Vault Setup ---"
if [ -f .ansible-vault-password ]; then
    YELLOW "Ansible Vault password file already exists. Skipping creation."
else
    CYAN "Ansible Vault is used to encrypt infrastructure secrets."
    CYAN "Auto-generating secure Ansible Vault password..."
    
    # Auto-generate a secure vault password
    VAULT_PASSWORD=$(openssl rand -base64 32)
    echo "$VAULT_PASSWORD" > .ansible-vault-password
    chmod 600 .ansible-vault-password
    GREEN "✅ Ansible Vault password file created."
fi

# 4. Generate Infrastructure Secrets Only
GREEN "\n--- Generating Infrastructure Secrets ---"

# Generate k3s cluster token
K3S_TOKEN=$(openssl rand -hex 32)

# Ansible Secrets
cat <<EOF > ansible/inventory/secrets.yml
ansible_user: ubuntu
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
k3s_token: $K3S_TOKEN
EOF

ansible-vault encrypt ansible/inventory/secrets.yml --vault-password-file .ansible-vault-password
GREEN "✅ Encrypted ansible/inventory/secrets.yml created."

# 5. Setup Complete
GREEN "\n--- Setup Complete! ---"
GREEN "Infrastructure secrets created successfully."
echo
YELLOW "Next steps:"
YELLOW "1. Review your cluster configuration: 'cat cluster.yaml'"
YELLOW "2. Create autoinstall USB drives for your nodes (use IP addresses from cluster.yaml)"
YELLOW "3. Boot your nodes from USB drives (10-15 minutes each)"
YELLOW "4. Run 'make setup' to deploy complete infrastructure based on your configuration"
YELLOW "5. Run 'make backup-secrets' after deployment to create a recovery file"
echo
CYAN "💡 Configuration-driven deployment:"
CYAN "   - Your cluster.yaml defines network, storage, and component settings"
CYAN "   - 'make setup' will use this configuration for automated deployment"
CYAN "   - Application secrets will be created automatically during deployment"
echo
CYAN "📋 Quick reference:"
CYAN "   - Show configuration summary: './scripts/lib/config-reader.sh summary'"
CYAN "   - Validate configuration: './scripts/lib/config-reader.sh validate'"
CYAN "   - List templates: './scripts/lib/config-reader.sh templates'"