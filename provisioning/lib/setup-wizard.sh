#!/bin/bash

# Zero Touch Cluster Setup Wizard

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

# Function to prompt for a value with a default
prompt() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -p "$(CYAN "${prompt_text}") [${default_value}]: " user_input
    echo "${user_input:-$default_value}"
}

# Function to prompt for a secret
prompt_secret() {
    local prompt_text="$1"
    local user_input

    read -sp "$(CYAN "${prompt_text}"): " user_input
    echo
    echo "$user_input"
}

# --- Main Script ---

# 1. Check dependencies
GREEN "--- Checking Dependencies ---"
check_command ansible-vault
check_command kubeseal
check_command kubectl

# Check and offer to install pre-commit
if ! command -v pre-commit &> /dev/null; then
    YELLOW "⚠️  pre-commit not found. This provides security guardrails to prevent secret commits."
    CYAN "Would you like to install pre-commit? (y/n)"
    read -p "" INSTALL_PRECOMMIT
    if [ "$INSTALL_PRECOMMIT" = "y" ] || [ "$INSTALL_PRECOMMIT" = "Y" ]; then
        CYAN "Installing pre-commit..."
        if command -v pip3 &> /dev/null; then
            pip3 install pre-commit
        elif command -v pip &> /dev/null; then
            pip install pre-commit
        elif command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y pre-commit
        elif command -v yum &> /dev/null; then
            sudo yum install -y pre-commit
        elif command -v brew &> /dev/null; then
            brew install pre-commit
        else
            YELLOW "⚠️  Could not install pre-commit automatically."
            YELLOW "   Please install manually: pip install pre-commit"
            YELLOW "   Then run: pre-commit install"
        fi
        
        if command -v pre-commit &> /dev/null; then
            GREEN "✅ pre-commit installed successfully."
            CYAN "Installing pre-commit hooks..."
            pre-commit install
            GREEN "✅ Pre-commit hooks installed - your commits are now protected!"
        fi
    else
        YELLOW "⚠️  Skipping pre-commit installation."
        YELLOW "   SECURITY WARNING: No automated protection against secret commits."
        YELLOW "   Install later with: pip install pre-commit && pre-commit install"
    fi
else
    GREEN "✅ pre-commit found."
    if [ ! -f .git/hooks/pre-commit ] || ! grep -q "pre-commit" .git/hooks/pre-commit 2>/dev/null; then
        CYAN "Installing pre-commit hooks..."
        pre-commit install
        GREEN "✅ Pre-commit hooks installed."
    else
        GREEN "✅ Pre-commit hooks already installed."
    fi
fi

GREEN "✅ All dependencies checked."

# 2. Ansible Vault Password
GREEN "\n--- Ansible Vault Setup ---"
if [ -f .ansible-vault-password ]; then
    YELLOW "Ansible Vault password file already exists. Skipping creation."
else
    CYAN "Ansible Vault is used to encrypt infrastructure secrets."
    CYAN "Please create a password for your Ansible Vault."
    VAULT_PASS1=$(prompt_secret "Enter Ansible Vault password")
    VAULT_PASS2=$(prompt_secret "Confirm Ansible Vault password")

    if [ "$VAULT_PASS1" != "$VAULT_PASS2" ]; then
        RED "Passwords do not match. Aborting."
        exit 1
    fi

    echo "$VAULT_PASS1" > .ansible-vault-password
    chmod 600 .ansible-vault-password
    GREEN "✅ Ansible Vault password file created."
fi

# 3. Gather Secrets
GREEN "\n--- Secrets Configuration ---"

# Grafana
GRAFANA_PASSWORD=$(prompt_secret "Enter Grafana admin password (or press Enter to auto-generate)")
if [ -z "$GRAFANA_PASSWORD" ]; then
    GRAFANA_PASSWORD=$(openssl rand -base64 16)
    YELLOW "Generated Grafana password: $GRAFANA_PASSWORD"
fi

# ArgoCD Git Repo
GIT_REPO_URL=$(prompt "Enter the URL for your private Git repository for ArgoCD" "https://github.com/your-username/your-repo")
GIT_REPO_USER=$(prompt "Enter the username for the Git repository" "git")
GIT_REPO_TOKEN=$(prompt_secret "Enter the personal access token for the Git repository")

# 4. Generate Secret Files
GREEN "\n--- Generating Encrypted Secrets ---"

# Ansible Secrets
cat <<EOF > ansible/inventory/secrets.yml
ansible_user: ubuntu
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
EOF
ansible-vault encrypt ansible/inventory/secrets.yml --vault-password-file .ansible-vault-password
GREEN "✅ Encrypted ansible/inventory/secrets.yml created."

# Grafana Secret
kubectl create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=$GRAFANA_PASSWORD \
  --dry-run=client -o yaml > grafana-secret.yaml

kubeseal --format=yaml < grafana-secret.yaml > kubernetes/system/monitoring/values-secret.yaml
rm grafana-secret.yaml
GREEN "✅ Encrypted kubernetes/system/monitoring/values-secret.yaml created."

# ArgoCD Repository Secret
kubectl create secret generic private-repo-credentials \
  --from-literal=url=$GIT_REPO_URL \
  --from-literal=username=$GIT_REPO_USER \
  --from-literal=password=$GIT_REPO_TOKEN \
  --dry-run=client -o yaml > argocd-repo-secret.yaml

kubeseal --format=yaml < argocd-repo-secret.yaml > kubernetes/system/argocd/config/repository-credentials.yaml
rm argocd-repo-secret.yaml
GREEN "✅ Encrypted kubernetes/system/argocd/config/repository-credentials.yaml created."

# 4. Gitea Admin Credentials
GREEN "\n--- Gitea Admin Configuration ---"
CYAN "Creating admin credentials for Gitea Git server..."

# Generate secure password for Gitea admin
GITEA_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Check if kubeseal is available
if command -v kubeseal >/dev/null 2>&1; then
    # Create SealedSecret for Gitea admin
    kubectl create secret generic gitea-admin-secret \
      --from-literal=password="$GITEA_ADMIN_PASSWORD" \
      --namespace=gitea \
      --dry-run=client -o yaml > gitea-admin-secret.yaml

    kubeseal --format=yaml < gitea-admin-secret.yaml > kubernetes/system/gitea/values-secret.yaml
    rm gitea-admin-secret.yaml
    GREEN "✅ Encrypted kubernetes/system/gitea/values-secret.yaml created."
else
    YELLOW "⚠️  kubeseal not found. Creating template file instead."
    YELLOW "   You can deploy Gitea with default credentials, then run setup again."
    # Just copy the template
    cp kubernetes/system/gitea/values-secret.yaml.template kubernetes/system/gitea/values-secret.yaml
fi

YELLOW "Gitea admin username: ztc-admin"
YELLOW "Gitea admin password: $GITEA_ADMIN_PASSWORD"
YELLOW "Access Gitea at: http://gitea.homelab.local (after deployment)"
YELLOW "IMPORTANT: Save this password - it will be needed for first login!"

# 5. Trust SSH Host Keys
GREEN "\n--- SSH Host Configuration ---"
CYAN "Do you want to automatically trust SSH host keys for your nodes? (y/n)"
read -p "" TRUST_HOSTS
if [ "$TRUST_HOSTS" = "y" ] || [ "$TRUST_HOSTS" = "Y" ]; then
    CYAN "Scanning and trusting SSH host keys..."
    if ansible-inventory -i ansible/inventory/hosts.ini --list >/dev/null 2>&1; then
        ansible-inventory -i ansible/inventory/hosts.ini --list | \
            grep -oE '"ansible_host": "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})"' | \
            cut -d '"' -f 4 | \
            xargs -I {} ssh-keyscan -H {} >> ~/.ssh/known_hosts 2>/dev/null
        GREEN "✅ SSH host keys trusted."
    else
        YELLOW "⚠️  Could not read inventory. Run 'make trust-hosts' manually after nodes are up."
    fi
else
    YELLOW "⚠️  Remember to run 'make trust-hosts' after your nodes are up."
fi

GREEN "\n--- Setup Complete! ---"
YELLOW "Next steps:"
YELLOW "1. Create autoinstall USB drives: 'make autoinstall-usb DEVICE=/dev/sdX HOSTNAME=k3s-master IP_OCTET=10'"
YELLOW "2. Boot your nodes from USB drives (10-15 minutes each)"
YELLOW "3. Run 'make infra' to deploy the cluster with example workloads"
YELLOW "4. IMPORTANT: Run 'make backup-secrets' to create a recovery file"
