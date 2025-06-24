#!/bin/bash

# Create Parameterized Autoinstall USB Drive
# Creates unattended Ubuntu installation USB with runtime configuration

set -euo pipefail

# Import shared libraries
source "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/logging.sh"

# Configuration
SSH_KEY_FILE="${DEFAULT_SSH_KEY_ED25519}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <usb_device> [hostname] [ip_octet]

Create an autoinstall USB drive for unattended Ubuntu installation.

Arguments:
    usb_device    USB device path (e.g., /dev/sdb, /dev/disk2)
    hostname      Node hostname (optional - will prompt if not provided)
    ip_octet      Last octet of IP (10-13, 20) (optional - will prompt if not provided)

Options:
    -h, --help           Show this help message
    -l, --list-devices   List available USB devices
    -f, --force          Skip confirmation prompts
    -i, --interactive    Force interactive mode even if args provided
    -k, --ssh-key FILE   SSH public key file (default: ~/.ssh/id_ed25519.pub)
    -p, --password PASS  Emergency password (default: ubuntu)
    --cidata-only        Create only cloud-init ISO (skip main USB creation)
    --cidata-usb DEVICE  Create cidata ISO and write directly to USB device
    --keep-mount         Keep USB mounted after creation

Common Node Configurations:
    Hostname          IP Octet    Full IP          Role
    k3s-master        10          ${DEFAULT_SUBNET}.10    Kubernetes control plane
    k3s-worker-01     11          ${DEFAULT_SUBNET}.11    Kubernetes worker
    k3s-worker-02     12          ${DEFAULT_SUBNET}.12    Kubernetes worker  
    k3s-worker-03     13          ${DEFAULT_SUBNET}.13    Kubernetes worker
    nas-server        20          ${DEFAULT_SUBNET}.20    NFS storage server

Examples:
    $0 /dev/sdb                                    # Interactive mode
    $0 /dev/sdb k3s-master 10                     # Direct arguments
    $0 -i /dev/sdb                                # Force interactive
    $0 -f /dev/disk2 k3s-worker-01 11             # Force creation without prompts
    $0 --cidata-only k3s-worker-01 11             # Create only cloud-init ISO (no USB)
    $0 --cidata-usb /dev/sdc k3s-worker-01 11    # Create ISO and write to USB in one step
    $0 -l                                         # List available USB devices

⚠️  WARNING: This will completely erase the USB device!

Installation Process:
1. Insert USB into target node
2. Boot from USB (F12/F8/Delete for boot menu)  
3. Wait 10-15 minutes for automatic installation
4. Node will reboot and be ready for SSH access
5. Run Ansible playbooks for cluster configuration

EOF
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check platform-specific tools
    if [[ "$OSTYPE" == "darwin"* ]]; then
        command -v diskutil >/dev/null 2>&1 || missing_deps+=("diskutil")
        command -v hdiutil >/dev/null 2>&1 || missing_deps+=("hdiutil")
    else
        command -v lsblk >/dev/null 2>&1 || missing_deps+=("lsblk")
        command -v partprobe >/dev/null 2>&1 || missing_deps+=("partprobe (parted package)")
    fi
    
    # Common tools
    command -v dd >/dev/null 2>&1 || missing_deps+=("dd")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v genisoimage >/dev/null 2>&1 || missing_deps+=("genisoimage")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Check SSH key file
    if [[ ! -f "${SSH_KEY_FILE}" ]]; then
        log_warning "SSH key not found: ${SSH_KEY_FILE}"
        if [[ -f "${DEFAULT_SSH_KEY_RSA}" ]]; then
            SSH_KEY_FILE="${DEFAULT_SSH_KEY_RSA}"
            log_info "Using RSA key: ${SSH_KEY_FILE}"
        else
            log_error "No SSH public key found. Generate one with:"
            echo "  ssh-keygen -t ed25519 -C 'ztc-admin'"
            exit 1
        fi
    fi
    
    # Check template files
    if [[ ! -f "${TEMPLATE_DIR}/user-data.template" ]]; then
        log_error "Template not found: ${TEMPLATE_DIR}/user-data.template"
        exit 1
    fi
    
    if [[ ! -f "${TEMPLATE_DIR}/meta-data.template" ]]; then
        log_error "Template not found: ${TEMPLATE_DIR}/meta-data.template"
        exit 1
    fi
    
    log_success "All dependencies satisfied"
}

list_usb_devices() {
    log_info "Available USB devices:"
    echo
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        diskutil list | grep -E "(external|USB)" -A 5 -B 5
    else
        # Linux
        lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep -E "(NAME|usb)"
    fi
    
    echo
    log_warning "⚠️  Ensure you select the correct device to avoid data loss!"
}

validate_usb_device() {
    local usb_device="$1"
    
    if [[ ! -b "${usb_device}" ]]; then
        log_error "USB device not found: ${usb_device}"
        log_info "Use -l to list available devices"
        exit 1
    fi
    
    # Get device info for confirmation
    local device_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        device_info=$(diskutil info "${usb_device}" | grep "Device / Media Name" | cut -d: -f2- | xargs)
    else
        device_info=$(lsblk -d -n -o SIZE,MODEL "${usb_device}" 2>/dev/null | xargs)
    fi
    
    log_info "Target device: ${usb_device} (${device_info})"
}

prompt_for_parameters() {
    local hostname_var="$1"
    local ip_octet_var="$2"
    
    echo
    echo "${CYAN}🔧 Node Configuration${NC}"
    echo "================================"
    
    # Prompt for hostname if not provided
    if [[ -z "${!hostname_var}" ]]; then
        echo "Common hostnames: k3s-master, k3s-worker-01, k3s-worker-02, k3s-worker-03, nas-server"
        while true; do
            read -p "Enter hostname: " hostname_input
            if [[ -n "${hostname_input}" ]]; then
                eval "${hostname_var}='${hostname_input}'"
                break
            else
                echo "Hostname cannot be empty. Please try again."
            fi
        done
    fi
    
    # Prompt for IP octet if not provided
    if [[ -z "${!ip_octet_var}" ]]; then
        echo "Common IP octets: 10 (master), 11-13 (workers), 20 (nas-server)"
        while true; do
            read -p "Enter IP last octet (e.g., 10 for ${DEFAULT_SUBNET}.10): " ip_input
            if [[ "${ip_input}" =~ ^[0-9]+$ ]] && [[ "${ip_input}" -ge 1 ]] && [[ "${ip_input}" -le 254 ]]; then
                eval "${ip_octet_var}='${ip_input}'"
                break
            else
                echo "IP octet must be a number between 1 and 254. Please try again."
            fi
        done
    fi
    
    echo
    echo "Configuration:"
    echo "  Hostname: ${!hostname_var}"
    echo "  IP: ${DEFAULT_SUBNET}.${!ip_octet_var}"
    echo "  SSH Key: ${SSH_KEY_FILE}"
    echo
}

validate_parameters() {
    local hostname="$1"
    local ip_octet="$2"
    
    # Validate hostname
    if [[ ! "${hostname}" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Invalid hostname: ${hostname}"
        log_info "Hostname must contain only letters, numbers, and hyphens"
        exit 1
    fi
    
    # Validate IP octet
    if [[ ! "${ip_octet}" =~ ^[0-9]+$ ]] || [[ "${ip_octet}" -lt 1 ]] || [[ "${ip_octet}" -gt 254 ]]; then
        log_error "Invalid IP octet: ${ip_octet}"
        log_info "IP octet must be a number between 1 and 254"
        exit 1
    fi
    
    log_success "Parameters validated"
}

generate_cloud_init_config() {
    local hostname="$1"
    local ip_octet="$2"
    local temp_dir="$3"
    local password="${4:-${DEFAULT_PASSWORD}}"
    
    log_info "Generating cloud-init configuration for ${hostname}"
    
    # Read SSH public key
    local ssh_public_key
    ssh_public_key=$(cat "${SSH_KEY_FILE}")
    
    # Generate password hash
    local password_hash
    password_hash=$(echo "${password}" | openssl passwd -6 -stdin)
    
    # Generate unique instance ID
    local instance_id="${hostname}-$(date +%Y%m%d-%H%M%S)"
    
    # Process user-data template
    sed \
        -e "s|__HOSTNAME__|${hostname}|g" \
        -e "s|__IP_OCTET__|${ip_octet}|g" \
        -e "s|__SSH_PUBLIC_KEY__|${ssh_public_key}|g" \
        -e "s|__USER_PASSWORD_HASH__|${password_hash}|g" \
        "${TEMPLATE_DIR}/user-data.template" > "${temp_dir}/user-data"
    
    # Process meta-data template
    sed \
        -e "s|__HOSTNAME__|${hostname}|g" \
        -e "s|__TIMESTAMP__|$(date +%Y%m%d-%H%M%S)|g" \
        "${TEMPLATE_DIR}/meta-data.template" > "${temp_dir}/meta-data"
    
    # Set proper permissions
    chmod 644 "${temp_dir}/user-data" "${temp_dir}/meta-data"
    
    # Validate generated config
    if grep -q "__.*__" "${temp_dir}/user-data" "${temp_dir}/meta-data"; then
        log_error "Template variables not fully replaced:"
        grep "__.*__" "${temp_dir}/user-data" "${temp_dir}/meta-data" || true
        exit 1
    fi
    
    log_success "Cloud-init configuration generated"
}

create_cloud_init_iso() {
    local hostname="$1"
    local ip_octet="$2"
    local password="${3:-${DEFAULT_PASSWORD}}"
    
    local temp_dir=$(mktemp -d)
    local cidata_iso="${DOWNLOAD_DIR}/${hostname}-cidata.iso"
    
    log_info "Creating cloud-init ISO for ${hostname} (${DEFAULT_SUBNET}.${ip_octet})..."
    
    # Generate cloud-init configuration
    generate_cloud_init_config "${hostname}" "${ip_octet}" "${temp_dir}" "${password}"
    
    # Create cloud-init ISO using genisoimage
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "${cidata_iso}" -volid cidata -joliet -rock \
            "${temp_dir}/user-data" "${temp_dir}/meta-data"
        
        if [[ -f "${cidata_iso}" ]]; then
            log_success "Created cloud-init ISO: ${cidata_iso}"
            log_info "File size: $(du -h "${cidata_iso}" | cut -f1)"
            echo
            echo "${CYAN}🎉 Cloud-init ISO Creation Complete!${NC}"
            echo
            echo "${CYAN}📁 File created:${NC}"
            echo "   - Cloud-init ISO: ${cidata_iso}"
            echo
            echo "${CYAN}📋 Usage Instructions:${NC}"
            echo "   1. ${YELLOW}Insert main Ubuntu USB${NC} into target node: ${hostname}"
            echo "   2. ${YELLOW}Insert this cloud-init ISO${NC} as second USB/CD"
            echo "   3. ${YELLOW}Boot from main USB${NC} (F12/F8/Delete for boot menu)"
            echo "   4. ${YELLOW}Ubuntu prompts: 'Use autoinstall? (yes/no)'${NC}"
            echo "   5. ${YELLOW}Type 'yes'${NC} - installation proceeds hands-off"
            echo "   6. ${YELLOW}Wait 10-15 minutes${NC} for installation"
            echo "   7. ${YELLOW}Node reboots automatically${NC} when finished"
            echo
            echo "${CYAN}🔑 After Installation:${NC}"
            echo "   - SSH access: ${GREEN}ssh ubuntu@${DEFAULT_SUBNET}.${ip_octet}${NC}"
            echo "   - Test connectivity: ${GREEN}ansible all -m ping${NC}"
            echo "   - Deploy infrastructure: ${GREEN}make infra${NC}"
            echo
        else
            log_error "Failed to create cloud-init ISO"
            exit 1
        fi
    else
        log_error "genisoimage not available - cannot create cloud-init ISO"
        exit 1
    fi
    
    # Cleanup temp directory
    rm -rf "${temp_dir}"
}

write_cidata_to_usb() {
    local hostname="$1"
    local ip_octet="$2"
    local usb_device="$3"
    local password="${4:-${DEFAULT_PASSWORD}}"
    local force_flag="${5:-false}"
    
    local cidata_iso="${DOWNLOAD_DIR}/${hostname}-cidata.iso"
    
    log_info "Creating and writing cidata ISO to USB for ${hostname} (${DEFAULT_SUBNET}.${ip_octet})..."
    
    # First create the ISO
    create_cloud_init_iso "${hostname}" "${ip_octet}" "${password}"
    
    # Confirmation unless force flag is set
    if [[ "${force_flag}" != true ]]; then
        echo
        log_warning "This will COMPLETELY ERASE the USB device: ${usb_device}"
        validate_usb_device "${usb_device}"
        log_warning "All data on the device will be lost!"
        echo "Configuration: ${hostname} → ${DEFAULT_SUBNET}.${ip_octet}"
        echo
        if ! confirm_action; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Unmount any mounted partitions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        diskutil unmountDisk "${usb_device}" 2>/dev/null || true
    else
        umount "${usb_device}"* 2>/dev/null || true
    fi
    
    # Write cidata ISO to USB
    log_info "Writing cidata ISO to USB (${cidata_iso})..."
    dd if="${cidata_iso}" of="${usb_device}" bs=4M status=progress oflag=sync
    sync
    
    # Unmount device after writing
    log_info "Unmounting USB device..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        diskutil unmountDisk "${usb_device}" 2>/dev/null || true
    else
        umount "${usb_device}"* 2>/dev/null || true
    fi
    
    log_success "Cidata USB created successfully!"
    echo
    echo "${CYAN}🎉 Cidata USB Creation Complete!${NC}"
    echo
    echo "${CYAN}📁 Files created:${NC}"
    echo "   - Cidata ISO: ${cidata_iso}"
    echo "   - USB Device: ${usb_device}"
    echo
    echo "${CYAN}📋 Usage Instructions:${NC}"
    echo "   1. ${YELLOW}Insert main Ubuntu USB${NC} into target node: ${hostname}"
    echo "   2. ${YELLOW}Insert this cidata USB${NC} as second device"
    echo "   3. ${YELLOW}Boot from main USB${NC} (F12/F8/Delete for boot menu)"
    echo "   4. ${YELLOW}Ubuntu prompts: 'Use autoinstall? (yes/no)'${NC}"
    echo "   5. ${YELLOW}Type 'yes'${NC} - installation proceeds hands-off"
    echo "   6. ${YELLOW}Wait 10-15 minutes${NC} for installation"
    echo "   7. ${YELLOW}Node reboots automatically${NC} when finished"
    echo
    echo "${CYAN}🔑 After Installation:${NC}"
    echo "   - SSH access: ${GREEN}ssh ubuntu@${DEFAULT_SUBNET}.${ip_octet}${NC}"
    echo "   - Test connectivity: ${GREEN}ansible all -m ping${NC}"
    echo "   - Deploy infrastructure: ${GREEN}make infra${NC}"
    echo
}

download_ubuntu_iso() {
    local iso_path="${DOWNLOAD_DIR}/${UBUNTU_ISO_NAME}"
    
    if [[ -f "${iso_path}" ]]; then
        log_info "Ubuntu ISO already exists: ${iso_path}"
        return 0
    fi
    
    log_info "Downloading Ubuntu Server ${UBUNTU_VERSION} ISO..."
    mkdir -p "${DOWNLOAD_DIR}"
    
    local iso_url="${UBUNTU_ISO_URL}"
    curl -L --progress-bar -o "${iso_path}" "${iso_url}"
    
    if [[ ! -f "${iso_path}" ]] || [[ ! -s "${iso_path}" ]]; then
        log_error "Failed to download Ubuntu ISO"
        exit 1
    fi
    
    local file_size=$(du -h "${iso_path}" | cut -f1)
    log_success "Downloaded Ubuntu ISO (${file_size})"
}

create_bootable_usb() {
    local usb_device="$1"
    local hostname="$2"
    local ip_octet="$3"
    local password="$4"
    local force_flag="$5"
    local keep_mount="$6"
    
    local iso_path="${DOWNLOAD_DIR}/${UBUNTU_ISO_NAME}"
    local temp_dir=$(mktemp -d)
    
    # Generate cloud-init config
    generate_cloud_init_config "${hostname}" "${ip_octet}" "${temp_dir}" "${password}"
    
    # Confirmation unless force flag is set
    if [[ "${force_flag}" != true ]]; then
        echo
        log_warning "This will COMPLETELY ERASE the USB device: ${usb_device}"
        validate_usb_device "${usb_device}"
        log_warning "All data on the device will be lost!"
        echo "Configuration: ${hostname} → ${DEFAULT_SUBNET}.${ip_octet}"
        echo
        if ! confirm_action; then
            log_info "Operation cancelled"
            rm -rf "${temp_dir}"
            exit 0
        fi
    fi
    
    log_info "Creating autoinstall USB for ${hostname} (${DEFAULT_SUBNET}.${ip_octet})..."
    
    # Unmount any mounted partitions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        diskutil unmountDisk "${usb_device}" 2>/dev/null || true
    else
        umount "${usb_device}"* 2>/dev/null || true
    fi
    
    # Write Ubuntu ISO to USB
    log_info "Writing Ubuntu ISO to USB (this takes 3-5 minutes)..."
    dd if="${iso_path}" of="${usb_device}" bs=4M status=progress oflag=sync
    sync
    
    # Wait for device to be ready
    sleep 2
    
    # Mount USB and copy autoinstall.yaml directly (Ubuntu recommended for physical hardware)
    log_info "Mounting USB to copy autoinstall configuration..."
    
    # Wait for device to be ready and try mounting
    sleep 3
    local mount_point
    local mounted=false
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS approach
        diskutil mount "${usb_device}s1" >/dev/null 2>&1 || diskutil mount "${usb_device}1" >/dev/null 2>&1 || true
        mount_point=$(ls -d /Volumes/Ubuntu* 2>/dev/null | head -1)
        [[ -n "${mount_point}" ]] && [[ -d "${mount_point}" ]] && mounted=true
    else
        # Linux approach - try multiple partition schemes
        mount_point="/tmp/autoinstall-usb-$$"
        mkdir -p "${mount_point}"
        
        # Try different partition naming schemes
        for partition in "${usb_device}1" "${usb_device}p1" "${usb_device}"; do
            if mount "${partition}" "${mount_point}" 2>/dev/null; then
                mounted=true
                log_info "Successfully mounted ${partition}"
                break
            fi
        done
    fi
    
    # Ubuntu live USB is ISO9660 (read-only) - create separate cloud-init ISO
    log_info "Creating separate cloud-init ISO (Ubuntu live USB is read-only)..."
    
    if command -v genisoimage >/dev/null 2>&1; then
        # Create cloud-init ISO using genisoimage (canonical method)
        local cidata_iso="${DOWNLOAD_DIR}/${hostname}-cidata.iso"
        
        genisoimage -output "${cidata_iso}" -volid cidata -joliet -rock \
            "${temp_dir}/user-data" "${temp_dir}/meta-data"
        
        if [[ -f "${cidata_iso}" ]]; then
            log_success "Created cloud-init ISO: ${cidata_iso}"
            log_info "File size: $(du -h "${cidata_iso}" | cut -f1)"
        else
            log_error "Failed to create cloud-init ISO"
        fi
    else
        log_warning "Could not mount USB partition - trying alternative approach"
        
        # Fallback: Create separate cloud-init ISO for dual-USB approach
        log_info "Creating separate cloud-init ISO as fallback..."
        local cidata_iso="${temp_dir}/cidata.iso"
        
        if command -v cloud-localds >/dev/null 2>&1; then
            cloud-localds "${cidata_iso}" "${temp_dir}/user-data" "${temp_dir}/meta-data"
            # Copy to permanent location
            local permanent_cidata="${DOWNLOAD_DIR}/${hostname}-cidata.iso"
            cp "${cidata_iso}" "${permanent_cidata}"
            log_warning "Created fallback cloud-init ISO: ${permanent_cidata}"
            echo "${permanent_cidata}" > "${temp_dir}/cidata_path"
        else
            log_error "Could not mount USB and cloud-localds not available"
            log_error "Manual intervention required"
        fi
    fi
    
    # Cleanup temp directory
    rm -rf "${temp_dir}"
    
    log_success "Autoinstall USB created successfully!"
}

show_completion_info() {
    local hostname="$1"
    local ip_octet="$2"
    local usb_device="$3"
    
    # Check if we created a fallback cloud-init ISO
    local cidata_path=""
    if [[ -f "${DOWNLOAD_DIR}/${hostname}-cidata.iso" ]]; then
        cidata_path="${DOWNLOAD_DIR}/${hostname}-cidata.iso"
    fi
    
    echo
    echo "${CYAN}🎉 Autoinstall USB Creation Complete!${NC}"
    echo
    
    if [[ -n "${cidata_path}" ]]; then
        echo "${CYAN}⚠️  Fallback Mode - Dual-ISO Installation:${NC}"
        echo "   ${YELLOW}Note: Could not mount USB - created separate cloud-init ISO${NC}"
        echo
        echo "   1. ${YELLOW}Insert both USBs${NC} into target node"
        echo "   2. ${YELLOW}Boot from primary USB${NC} (Ubuntu installer)"
        echo "   3. ${YELLOW}Ubuntu prompts: 'Use autoinstall? (yes/no)'${NC}"
        echo "   4. ${YELLOW}Type 'yes'${NC} - installation proceeds hands-off"
        echo "   5. ${YELLOW}Wait 10-15 minutes${NC} for installation"
        echo
        echo "${CYAN}📁 Files created:${NC}"
        echo "   - Primary: ${usb_device} (Ubuntu installer)"
        echo "   - Secondary: ${cidata_path}"
    else
        echo "${CYAN}📋 Dual ISO Installation:${NC}"
        echo "   ${GREEN}✅ Main Ubuntu installer + separate cloud-init ISO${NC}"
        echo
        echo "   1. ${YELLOW}Insert main USB${NC} into target node: ${hostname}"
        echo "   2. ${YELLOW}Insert cloud-init ISO${NC} as second USB/CD"
        echo "   3. ${YELLOW}Boot from main USB${NC} (F12/F8/Delete for boot menu)"
        echo "   4. ${YELLOW}Ubuntu prompts: 'Use autoinstall? (yes/no)'${NC}"
        echo "   5. ${YELLOW}Type 'yes'${NC} - installation proceeds hands-off"
        echo "   6. ${YELLOW}Wait 10-15 minutes${NC} for installation"
        echo "   7. ${YELLOW}Node reboots automatically${NC} when finished"
    fi
    
    echo
    echo "${CYAN}🔑 After Installation:${NC}"
    echo "   - SSH access: ${GREEN}ssh ubuntu@${DEFAULT_SUBNET}.${ip_octet}${NC}"
    echo "   - Test connectivity: ${GREEN}ansible all -m ping${NC}"
    echo "   - Deploy infrastructure: ${GREEN}make infra${NC}"
    echo
    echo "${CYAN}⚠️  Installation Features:${NC}"
    echo "   - ${GREEN}✅${NC} Unattended installation (no user interaction)"
    echo "   - ${GREEN}✅${NC} Static IP: 192.168.50.${ip_octet}"
    echo "   - ${GREEN}✅${NC} SSH key authentication only"
    echo "   - ${GREEN}✅${NC} Kubernetes prerequisites installed"
    echo "   - ${GREEN}✅${NC} System optimized for cluster workloads"
    echo
}

main() {
    local usb_device=""
    local hostname=""
    local ip_octet=""
    local password="${DEFAULT_PASSWORD}"
    local force_flag=false
    local list_devices_flag=false
    local interactive_flag=false
    local keep_mount_flag=false
    local cidata_only_flag=false
    local cidata_usb_flag=false
    local cidata_usb_device=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--list-devices)
                list_devices_flag=true
                shift
                ;;
            -f|--force)
                force_flag=true
                shift
                ;;
            -i|--interactive)
                interactive_flag=true
                shift
                ;;
            -k|--ssh-key)
                SSH_KEY_FILE="$2"
                shift 2
                ;;
            -p|--password)
                password="$2"
                shift 2
                ;;
            --cidata-only)
                cidata_only_flag=true
                shift
                ;;
            --cidata-usb)
                cidata_usb_flag=true
                cidata_usb_device="$2"
                shift 2
                ;;
            --keep-mount)
                keep_mount_flag=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ "${cidata_only_flag}" == true ]] || [[ "${cidata_usb_flag}" == true ]]; then
                    # In cidata-only or cidata-usb mode, arguments are hostname and ip_octet
                    if [[ -z "${hostname}" ]]; then
                        hostname="$1"
                    elif [[ -z "${ip_octet}" ]]; then
                        ip_octet="$1"
                    else
                        log_error "Too many arguments for --cidata-only/--cidata-usb mode"
                        usage
                        exit 1
                    fi
                else
                    # Normal mode: usb_device, hostname, ip_octet
                    if [[ -z "${usb_device}" ]]; then
                        usb_device="$1"
                    elif [[ -z "${hostname}" ]]; then
                        hostname="$1"
                    elif [[ -z "${ip_octet}" ]]; then
                        ip_octet="$1"
                    else
                        log_error "Too many arguments"
                        usage
                        exit 1
                    fi
                fi
                shift
                ;;
        esac
    done
    
    # Handle list devices flag
    if [[ "${list_devices_flag}" == true ]]; then
        list_usb_devices
        exit 0
    fi
    
    # Validate required USB device argument (unless cidata-only mode)
    if [[ -z "${usb_device}" ]] && [[ "${cidata_only_flag}" != true ]] && [[ "${cidata_usb_flag}" != true ]]; then
        log_error "Missing USB device argument"
        usage
        exit 1
    fi
    
    # Validate cidata-usb device argument
    if [[ "${cidata_usb_flag}" == true ]] && [[ -z "${cidata_usb_device}" ]]; then
        log_error "Missing USB device for --cidata-usb option"
        usage
        exit 1
    fi
    
    check_dependencies
    
    # Only validate USB device if not in cidata-only mode
    if [[ "${cidata_only_flag}" != true ]]; then
        if [[ "${cidata_usb_flag}" == true ]]; then
            validate_usb_device "${cidata_usb_device}"
        elif [[ -n "${usb_device}" ]]; then
            validate_usb_device "${usb_device}"
        fi
    fi
    
    # Get parameters via prompts if not provided or if interactive mode
    if [[ "${interactive_flag}" == true ]] || [[ -z "${hostname}" ]] || [[ -z "${ip_octet}" ]]; then
        prompt_for_parameters hostname ip_octet
    fi
    
    validate_parameters "${hostname}" "${ip_octet}"
    
    if [[ "${cidata_only_flag}" == true ]]; then
        # Create only cloud-init ISO
        create_cloud_init_iso "${hostname}" "${ip_octet}" "${password}"
    elif [[ "${cidata_usb_flag}" == true ]]; then
        # Create cidata ISO and write to USB
        write_cidata_to_usb "${hostname}" "${ip_octet}" "${cidata_usb_device}" "${password}" "${force_flag}"
    else
        # Full USB creation process
        download_ubuntu_iso
        create_bootable_usb "${usb_device}" "${hostname}" "${ip_octet}" "${password}" "${force_flag}" "${keep_mount_flag}"
        show_completion_info "${hostname}" "${ip_octet}" "${usb_device}"
    fi
}

main "$@"