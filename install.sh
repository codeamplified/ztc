#!/bin/bash

# Zero Touch Cluster - One-Command Installer
# Installs ZTC with minimal dependencies (Docker-first approach)

set -euo pipefail

# Colors for output
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Configuration
ZTC_REPO_URL="https://github.com/zero-touch-cluster/ztc.git"
ZTC_INSTALL_DIR="$HOME/ztc"
DOCKER_INSTALL_URL="https://get.docker.com"

# Banner
show_banner() {
    cat << EOF
$(echo -e "${CYAN}")
╔══════════════════════════════════════════════════════════════╗
║                    Zero Touch Cluster                        ║
║                     Quick Installer                         ║
╚══════════════════════════════════════════════════════════════╝
$(echo -e "${RESET}")

$(echo -e "${YELLOW}")Kubernetes homelab automation with zero dependencies$(echo -e "${RESET}")

This installer will:
  🐳 Install Docker (if needed)
  📥 Clone ZTC repository
  🏗️  Build ZTC container image
  ✅ Verify installation

EOF
}

# Check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}❌ Don't run this installer as root${RESET}"
        echo -e "${YELLOW}💡 Run as your regular user. Docker installation will use sudo when needed.${RESET}"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt >/dev/null 2>&1; then
            echo "ubuntu"
        elif command -v yum >/dev/null 2>&1; then
            echo "centos"
        elif command -v pacman >/dev/null 2>&1; then
            echo "arch"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Check if Docker is available
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker ps >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Docker is available and working${RESET}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Docker installed but not accessible (permission issue?)${RESET}"
            return 1
        fi
    elif command -v podman >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Podman is available${RESET}"
        return 0
    else
        return 1
    fi
}

# Install Docker
install_docker() {
    local os="$1"
    
    echo -e "${CYAN}🐳 Installing Docker...${RESET}"
    
    case "$os" in
        "ubuntu"|"linux")
            echo -e "${YELLOW}Installing Docker using official installation script...${RESET}"
            curl -fsSL "$DOCKER_INSTALL_URL" | sh
            
            # Add user to docker group
            echo -e "${CYAN}Adding user to docker group...${RESET}"
            sudo usermod -aG docker "$USER"
            
            echo -e "${YELLOW}⚠️  You may need to log out and back in for docker group to take effect${RESET}"
            echo -e "${YELLOW}Or run: newgrp docker${RESET}"
            ;;
        "macos")
            echo -e "${YELLOW}On macOS, please install Docker Desktop:${RESET}"
            echo -e "${CYAN}1. Visit: https://www.docker.com/products/docker-desktop${RESET}"
            echo -e "${CYAN}2. Download and install Docker Desktop${RESET}"
            echo -e "${CYAN}3. Start Docker Desktop${RESET}"
            echo -e "${CYAN}4. Re-run this installer${RESET}"
            exit 1
            ;;
        "windows")
            echo -e "${YELLOW}On Windows, please install Docker Desktop:${RESET}"
            echo -e "${CYAN}1. Visit: https://www.docker.com/products/docker-desktop${RESET}"
            echo -e "${CYAN}2. Download and install Docker Desktop${RESET}"
            echo -e "${CYAN}3. Enable WSL 2 integration${RESET}"
            echo -e "${CYAN}4. Re-run this installer in WSL${RESET}"
            exit 1
            ;;
        *)
            echo -e "${RED}❌ Unsupported OS for automatic Docker installation${RESET}"
            echo -e "${YELLOW}Please install Docker manually: https://docs.docker.com/get-docker/${RESET}"
            exit 1
            ;;
    esac
}

# Clone ZTC repository
clone_ztc() {
    echo -e "${CYAN}📥 Cloning ZTC repository...${RESET}"
    
    if [[ -d "$ZTC_INSTALL_DIR" ]]; then
        echo -e "${YELLOW}⚠️  ZTC directory already exists: $ZTC_INSTALL_DIR${RESET}"
        read -p "Remove and re-clone? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$ZTC_INSTALL_DIR"
        else
            echo -e "${YELLOW}Using existing installation${RESET}"
            return 0
        fi
    fi
    
    if command -v git >/dev/null 2>&1; then
        git clone "$ZTC_REPO_URL" "$ZTC_INSTALL_DIR"
    else
        echo -e "${YELLOW}⚠️  Git not found, downloading archive...${RESET}"
        mkdir -p "$ZTC_INSTALL_DIR"
        curl -L "${ZTC_REPO_URL}/archive/main.tar.gz" | tar -xz --strip-components=1 -C "$ZTC_INSTALL_DIR"
    fi
    
    echo -e "${GREEN}✅ ZTC repository cloned to $ZTC_INSTALL_DIR${RESET}"
}

# Build ZTC Docker image
build_ztc_image() {
    echo -e "${CYAN}🏗️  Building ZTC Docker image...${RESET}"
    echo -e "${YELLOW}This may take a few minutes...${RESET}"
    
    cd "$ZTC_INSTALL_DIR"
    
    if docker build -t ztc:latest .; then
        echo -e "${GREEN}✅ ZTC Docker image built successfully${RESET}"
    else
        echo -e "${RED}❌ Failed to build ZTC Docker image${RESET}"
        return 1
    fi
}

# Test ZTC installation
test_installation() {
    echo -e "${CYAN}🧪 Testing ZTC installation...${RESET}"
    
    cd "$ZTC_INSTALL_DIR"
    chmod +x ztc
    
    echo -e "${CYAN}Testing: ./ztc --docker-status${RESET}"
    if ./ztc --docker-status; then
        echo -e "${GREEN}✅ ZTC installation test passed${RESET}"
    else
        echo -e "${RED}❌ ZTC installation test failed${RESET}"
        return 1
    fi
}

# Show next steps
show_next_steps() {
    cat << EOF

$(echo -e "${GREEN}")
🎉 Zero Touch Cluster installed successfully!
$(echo -e "${RESET}")

$(echo -e "${CYAN}")📍 Installation location:$(echo -e "${RESET}") $ZTC_INSTALL_DIR

$(echo -e "${CYAN}")🚀 Next steps:$(echo -e "${RESET}")

1. Navigate to ZTC directory:
   $(echo -e "${YELLOW}")cd $ZTC_INSTALL_DIR$(echo -e "${RESET}")

2. Generate cluster configuration:
   $(echo -e "${YELLOW}")./ztc prepare$(echo -e "${RESET}")

3. Deploy your cluster:
   $(echo -e "${YELLOW}")./ztc setup$(echo -e "${RESET}")

4. Check cluster status:
   $(echo -e "${YELLOW}")./ztc status$(echo -e "${RESET}")

$(echo -e "${CYAN}")💡 Available commands:$(echo -e "${RESET}")
   $(echo -e "${YELLOW}")./ztc help$(echo -e "${RESET}")              # Show all available commands
   $(echo -e "${YELLOW}")./ztc validate-config$(echo -e "${RESET}")    # Validate cluster configuration
   $(echo -e "${YELLOW}")./ztc deploy-bundle-starter$(echo -e "${RESET}") # Deploy starter workloads

$(echo -e "${CYAN}")📚 Documentation:$(echo -e "${RESET}")
   - Configuration guide: docs/configuration-system.md
   - Docker setup: docs/docker-setup.md
   - Troubleshooting: docs/troubleshooting.md

$(echo -e "${CYAN}")🐳 Docker wrapper benefits:$(echo -e "${RESET}")
   ✅ Zero local dependencies (only Docker needed)
   ✅ Consistent tool versions across platforms
   ✅ Isolated environment with no conflicts
   ✅ All ZTC commands work identically

EOF
}

# Add to shell profile for easy access
add_to_path() {
    local shell_rc
    
    if [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    else
        echo -e "${YELLOW}⚠️  Could not detect shell profile${RESET}"
        return 0
    fi
    
    local ztc_alias="alias ztc='$ZTC_INSTALL_DIR/ztc'"
    
    if ! grep -q "alias ztc=" "$shell_rc" 2>/dev/null; then
        echo -e "${CYAN}Adding ZTC alias to $shell_rc...${RESET}"
        echo "" >> "$shell_rc"
        echo "# Zero Touch Cluster alias" >> "$shell_rc"
        echo "$ztc_alias" >> "$shell_rc"
        echo -e "${GREEN}✅ Added 'ztc' command alias${RESET}"
        echo -e "${YELLOW}💡 Run 'source $shell_rc' or restart your terminal to use 'ztc' globally${RESET}"
    fi
}

# Main installation flow
main() {
    show_banner
    
    # Checks
    check_not_root
    
    # Detect OS
    local os
    os=$(detect_os)
    echo -e "${CYAN}🖥️  Detected OS: $os${RESET}"
    
    # Check/install Docker
    if ! check_docker; then
        echo -e "${YELLOW}🐳 Docker not found or not accessible${RESET}"
        read -p "Install Docker automatically? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_docker "$os"
            
            # Re-check after installation
            if ! check_docker; then
                echo -e "${RED}❌ Docker installation verification failed${RESET}"
                echo -e "${YELLOW}Please ensure Docker is running and try again${RESET}"
                exit 1
            fi
        else
            echo -e "${RED}❌ Docker is required for ZTC zero-dependency operation${RESET}"
            echo -e "${YELLOW}Install Docker manually: https://docs.docker.com/get-docker/${RESET}"
            exit 1
        fi
    fi
    
    # Clone repository
    clone_ztc
    
    # Build image
    build_ztc_image
    
    # Test installation
    test_installation
    
    # Add to PATH
    add_to_path
    
    # Show next steps
    show_next_steps
}

# Handle interrupts gracefully
trap 'echo -e "\n${RED}❌ Installation interrupted${RESET}"; exit 1' INT TERM

# Run main installation
main "$@"