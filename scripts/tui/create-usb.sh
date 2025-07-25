#!/bin/bash

# TUI USB Creation Script
# This script is called by the TUI to create bootable USB drives.

set -euo pipefail

# Import shared libraries
source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logging.sh"

# Arguments from TUI
USB_DEVICE="$1"
HOSTNAME="$2"
IP_OCTET="$3"

# Main execution
log_info "Starting TUI USB creation for device: ${USB_DEVICE}"
log_info "Hostname: ${HOSTNAME}, IP Octet: ${IP_OCTET}"

# Call the main USB creation script
"$(dirname "${BASH_SOURCE[0]}")/../provisioning/create-autoinstall-usb.sh" -f "${USB_DEVICE}" "${HOSTNAME}" "${IP_OCTET}"

log_success "TUI USB creation script finished for device: ${USB_DEVICE}"