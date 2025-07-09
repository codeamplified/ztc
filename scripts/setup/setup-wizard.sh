#!/bin/bash

# Zero Touch Cluster Setup Wizard - Pre-cluster Phase Only

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

# --- Main Script ---

GREEN "=== Zero Touch Cluster Pre-cluster Setup ==="
CYAN "This creates basic infrastructure secrets needed for cluster deployment."
CYAN "Application secrets will be generated automatically after cluster deployment."
echo

# 1. Check dependencies
GREEN "--- Checking Dependencies ---"
check_command ansible-vault
check_command kubeseal
check_command kubectl
GREEN "✅ All dependencies checked."

# 2. Ansible Vault Password
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

# 3. Generate Infrastructure Secrets Only
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

# 4. Setup Complete
GREEN "\n--- Pre-cluster Setup Complete! ---"
GREEN "Infrastructure secrets created successfully."
echo
YELLOW "Next steps:"
YELLOW "1. Create autoinstall USB drives: 'make autoinstall-usb DEVICE=/dev/sdX HOSTNAME=k3s-master IP_OCTET=10'"
YELLOW "2. Boot your nodes from USB drives (10-15 minutes each)"
YELLOW "3. Run 'make infra' to deploy complete infrastructure (cluster + applications)"
YELLOW "4. Run 'make backup-secrets' after deployment to create a recovery file"
echo
CYAN "Note: Application secrets (Grafana, Gitea, ArgoCD) will be created automatically during 'make infra'"