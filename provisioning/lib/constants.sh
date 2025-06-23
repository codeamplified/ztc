#!/bin/bash
# Shared constants for homelab provisioning scripts

# Ubuntu Configuration
readonly UBUNTU_VERSION="24.04.2"
readonly UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
readonly UBUNTU_ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION%.*}/${UBUNTU_ISO_NAME}"

# Directory Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/cloud-init"

# SSH Configuration
readonly DEFAULT_SSH_KEY_ED25519="${HOME}/.ssh/id_ed25519.pub"
readonly DEFAULT_SSH_KEY_RSA="${HOME}/.ssh/id_rsa.pub"
readonly DEFAULT_PASSWORD="ubuntu"

# Network Configuration
readonly DEFAULT_SUBNET="192.168.50"