#!/bin/bash
# Shared logging utilities for homelab provisioning scripts

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Confirmation prompt with custom message
confirm_action() {
    local message="${1:-Are you sure you want to continue?}"
    local default="${2:-N}"
    
    read -p "${message} (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}