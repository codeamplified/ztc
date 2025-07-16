#!/bin/bash
# TUI Wizard wrapper script
# Handles the transition between TUI and make commands

set -euo pipefail

# Fix file permissions for mounted workspace
if [[ -n "${HOST_USER_ID:-}" && -n "${HOST_GROUP_ID:-}" ]]; then
    # Ensure ztc user can write to workspace
    sudo chown -R ztc:ztc /workspace 2>/dev/null || true
    
    # Create a function to fix permissions after file operations
    fix_permissions() {
        if [[ -n "${HOST_USER_ID:-}" && -n "${HOST_GROUP_ID:-}" ]]; then
            sudo chown -R "${HOST_USER_ID}:${HOST_GROUP_ID}" /workspace 2>/dev/null || true
        fi
    }
    
    # Set trap to fix permissions on exit
    trap fix_permissions EXIT
fi

# Function to execute make commands with proper output handling
execute_make() {
    local command="$1"
    echo "Executing: make $command"
    
    # Execute the make command and capture output
    if make "$command" 2>&1; then
        echo "✓ Command completed successfully"
        return 0
    else
        echo "✗ Command failed"
        return 1
    fi
}

# Main logic
case "${1:-tui-wizard}" in
    "tui-wizard")
        # Check if running in guided mode
        if [[ "${ZTC_GUIDED_MODE:-}" == "true" ]]; then
            # Run the TUI wizard
            /usr/local/bin/tui-wizard
        else
            # Not in guided mode, just run make help
            execute_make "help"
        fi
        ;;
    "prepare-auto")
        # Non-interactive preparation
        execute_make "prepare-auto"
        ;;
    "setup")
        # Full cluster setup
        execute_make "setup"
        ;;
    "status")
        # Check cluster status
        execute_make "status"
        ;;
    *)
        # Pass through to make
        execute_make "$1"
        ;;
esac