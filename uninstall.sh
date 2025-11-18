#!/bin/bash
set -euo pipefail

# get current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to confirm action
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    while true; do
        read -p "$prompt [y/N]: " yn
        case $yn in
            [Yy]* ) return 0 ;;
            [Nn]* | "" ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

echo "Starting Heim-View Client uninstallation..."
echo "-------------------------------------------"

# 1. Stop and remove systemd service
if systemctl list-unit-files | grep -q heim-view.service; then
    echo "Found heim-view service. Stopping..."
    sudo systemctl stop heim-view.service

    echo "Disabling service..."
    sudo systemctl disable heim-view.service

    echo "Removing service file..."
    sudo rm -f /etc/systemd/system/heim-view.service

    echo "Reloading systemd..."
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
else
    echo "No heim-view service found (already removed or never installed)."
fi

# 2. Ask about removing files
echo ""
echo "Found installation files in: $SCRIPT_DIR"
echo "You can choose to:"
echo "1. Remove ALL files (complete uninstall)"
echo "2. Keep configuration and logs (partial uninstall)"
echo "3. Cancel uninstall"

if confirm_action "Do you want to COMPLETELY remove ALL files?"; then
    echo "Removing all files..."
    rm -rf "$SCRIPT_DIR"
    echo "All files removed."
elif confirm_action "Do you want to keep config/logs but remove other files?"; then
    echo "Keeping config and logs, removing other files..."
    # Keep data directory but remove everything else
    if [ -d "$SCRIPT_DIR/data" ]; then
        find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name 'data' -exec rm -rf {} +
        echo "Kept data directory with configs and logs."
    else
        rm -rf "$SCRIPT_DIR"
        echo "No data directory found, removed everything."
    fi
else
    echo "Uninstall cancelled. Service was removed but files remain."
    exit 0
fi

echo ""
echo "Uninstallation complete!"
echo "If you kept any files, you can find them in:"
echo "$SCRIPT_DIR"