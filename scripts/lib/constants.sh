#!/bin/bash
# Shared constants for Zero Touch Cluster provisioning scripts

# Ubuntu Configuration
readonly UBUNTU_VERSION="24.04.2"
readonly UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
readonly UBUNTU_RELEASE_URL="https://releases.ubuntu.com/${UBUNTU_VERSION%.*}"
readonly UBUNTU_ISO_URL="${UBUNTU_RELEASE_URL}/${UBUNTU_ISO_NAME}"

# Directory Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly DOWNLOAD_DIR="${SCRIPT_DIR}/provisioning/downloads"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/provisioning/cloud-init"

# SSH Configuration
readonly DEFAULT_SSH_KEY_ED25519="${HOME}/.ssh/id_ed25519.pub"
readonly DEFAULT_SSH_KEY_RSA="${HOME}/.ssh/id_rsa.pub"
readonly DEFAULT_PASSWORD="ubuntu"

# Network Configuration
readonly DEFAULT_SUBNET="192.168.50"