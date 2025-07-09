#!/bin/bash

# Ubuntu ISO Download Script
# Downloads and verifies Ubuntu Server 24.04 LTS for USB creation

set -euo pipefail

# Import shared libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logging.sh"

main() {
    log_info "Downloading Ubuntu Server ${UBUNTU_VERSION} ISO..."
    
    mkdir -p "${DOWNLOAD_DIR}"
    local iso_path="${DOWNLOAD_DIR}/${UBUNTU_ISO_NAME}"
    local checksum_url="${UBUNTU_RELEASE_URL}/SHA256SUMS"
    local checksum_path="${DOWNLOAD_DIR}/SHA256SUMS"

    # ... (existing file check logic remains the same) ...
    
    log_info "Downloading from: ${UBUNTU_ISO_URL}"
    # Download to a temporary file first for atomicity
    curl -L --progress-bar -o "${iso_path}.tmp" "${UBUNTU_ISO_URL}"
    
    # After download, move the temp file to its final name
    mv "${iso_path}.tmp" "${iso_path}"
    
    # --- START: Checksum Verification ---
    log_info "Downloading checksums from: ${checksum_url}"
    curl -L -s -o "${checksum_path}" "${checksum_url}"
    
    log_info "Verifying ISO integrity..."
    # Change directory to check, as SHA256SUMS file expects files in the current dir
    (cd "${DOWNLOAD_DIR}" && sha256sum -c --ignore-missing SHA256SUMS)
    if [[ $? -ne 0 ]]; then
        log_error "Checksum verification FAILED. The ISO file may be corrupt or tampered with."
        rm "${iso_path}" "${checksum_path}" # Clean up bad files
        exit 1
    fi
    # --- END: Checksum Verification ---

    local file_size=$(du -h "${iso_path}" | cut -f1)
    log_success "Successfully downloaded and verified Ubuntu ISO (${file_size}): ${iso_path}"
    rm "${checksum_path}" # Clean up checksum file
}

main "$@"