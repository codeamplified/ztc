#!/bin/bash

# Ubuntu ISO Download Script
# Downloads Ubuntu Server 24.04.2 LTS for USB creation

set -euo pipefail

# Import shared libraries
source "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/logging.sh"

main() {
    log_info "Downloading Ubuntu Server ${UBUNTU_VERSION} ISO..."
    
    mkdir -p "${DOWNLOAD_DIR}"
    local iso_path="${DOWNLOAD_DIR}/${UBUNTU_ISO_NAME}"
    
    if [[ -f "${iso_path}" ]]; then
        local file_size=$(du -h "${iso_path}" | cut -f1)
        log_warning "ISO already exists (${file_size}): ${iso_path}"
        if ! confirm_action "Redownload?"; then
            log_info "Using existing ISO"
            exit 0
        fi
    fi
    
    log_info "Downloading from: ${UBUNTU_ISO_URL}"
    curl -L --progress-bar -o "${iso_path}" "${UBUNTU_ISO_URL}"
    
    if [[ ! -f "${iso_path}" ]] || [[ ! -s "${iso_path}" ]]; then
        log_error "Failed to download Ubuntu ISO"
        exit 1
    fi
    
    local file_size=$(du -h "${iso_path}" | cut -f1)
    log_success "Downloaded Ubuntu ISO (${file_size}): ${iso_path}"
}

main "$@"