#!/bin/bash
set -euo pipefail

# Check if running as root (via sudo)
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges for service installation."
    echo "Please run with sudo: sudo $0"
    exit 1
fi

# get current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for main Python script
PYTHON_SCRIPT=""
if [ -f "heim_view.py" ]; then
    PYTHON_SCRIPT="heim-view.py"
else
    # Try to find any Python file that might be the main script
    PY_FILES=(*.py)
    if [ ${#PY_FILES[@]} -eq 1 ]; then
        PYTHON_SCRIPT="${PY_FILES[0]}"
    elif [ ${#PY_FILES[@]} -gt 1 ]; then
        echo "Multiple Python files found:"
        select file in "${PY_FILES[@]}"; do
            if [ -n "$file" ]; then
                PYTHON_SCRIPT="$file"
                break
            fi
        done
    fi
fi

# If we still don't have a script, exit with error
if [ -z "$PYTHON_SCRIPT" ]; then
    echo "ERROR: No Python script found in $SCRIPT_DIR"
    echo "Please ensure heim-view.py or heim_view.py exists"
    exit 1
fi

# build file structure
mkdir -p data/logs
mkdir -p data/cache

# edit config file using user input
CONFIG_FILE="data/config.json"

# Function to extract values from config using grep/sed
extract_config_value() {
    local key_pattern="$1"
    local default="$2"
    local file="$CONFIG_FILE"

    if [ ! -f "$file" ]; then
        echo "$default"
        return
    fi

    # Try to extract the value
    local value
    value=$(grep -oP "$key_pattern" "$file" 2>/dev/null | head -1)

    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

if [ -f "$CONFIG_FILE" ]; then
    echo "Existing config.json found. Creating backup..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

    # Load existing values as defaults using grep patterns
    SERVER_IP=$(extract_config_value '"server_url":\s*"http://\K[^:]+' "127.0.0.1")
    SERVER_PORT=$(extract_config_value '"server_url":\s*"http://[^:]+:\K[^/]+' "5000")
    INTERVAL_SECONDS=$(extract_config_value '"interval_seconds":\s*\K[^,}]+' "60")
    AUTO_UPDATE=$(extract_config_value '"auto_update":\s*\K[^,}]+' "false")
    PUBLIC_IP_INTERVAL=$(extract_config_value '"public_ip_update_check_interval":\s*\K[^,}]+' "3600")

    read -p "Overwrite existing config? (y/N): " CONFIRM
    if [[ "$CONFIRM" != [yY] ]]; then
        echo "Keeping existing configuration."
        exit 0
    fi
else
    # Defaults for new config
    SERVER_IP="127.0.0.1"
    SERVER_PORT="5000"
    INTERVAL_SECONDS="60"
    AUTO_UPDATE="false"
    PUBLIC_IP_INTERVAL="3600"
fi

echo "Configuring settings..."
read -p "Enter the server IP address [$SERVER_IP]: " NEW_IP
read -p "Enter the server port [$SERVER_PORT]: " NEW_PORT
read -p "Enter log frequency in seconds [$INTERVAL_SECONDS]: " NEW_INTERVAL
read -p "Enable auto-update? (true/false) [$AUTO_UPDATE]: " NEW_AUTO_UPDATE
read -p "Public IP update check interval in seconds [$PUBLIC_IP_INTERVAL]: " NEW_PUBLIC_IP_INTERVAL

# Use new values or fall back to existing/defaults
SERVER_IP=${NEW_IP:-$SERVER_IP}
SERVER_PORT=${NEW_PORT:-$SERVER_PORT}
INTERVAL_SECONDS=${NEW_INTERVAL:-$INTERVAL_SECONDS}
AUTO_UPDATE=${NEW_AUTO_UPDATE:-$AUTO_UPDATE}
PUBLIC_IP_INTERVAL=${NEW_PUBLIC_IP_INTERVAL:-$PUBLIC_IP_INTERVAL}

# Convert to lowercase for boolean
AUTO_UPDATE=$(echo "$AUTO_UPDATE" | tr '[:upper:]' '[:lower:]')

cat > "$CONFIG_FILE" <<EOL
{
    "server_url": "http://${SERVER_IP}:${SERVER_PORT}/log",
    "interval_seconds": $INTERVAL_SECONDS,
    "auto_update": $AUTO_UPDATE,
    "github_repo": "https://raw.githubusercontent.com/t1mj4cks0n/heim-view-client/main",
    "version": "1.0",
    "public_ip_update_check_interval": $PUBLIC_IP_INTERVAL
}
EOL

echo "Configuration file updated at $CONFIG_FILE"

echo "Making heim-view.py executable..."
chmod +770 heim-view.py

# Service installation
echo "Installing systemd service..."
SERVICE_FILE="/etc/systemd/system/heim-view.service"
USERNAME=$(whoami)

# Create logs directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/data/logs"

# Create service file with logging
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Heim View Client Service
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/heim_view.py
Restart=always
RestartSec=5s

# Logging configuration
StandardOutput=append:$SCRIPT_DIR/data/logs/service.log
StandardError=append:$SCRIPT_DIR/data/logs/service-error.log
SyslogIdentifier=heim-view

[Install]
WantedBy=multi-user.target
EOL

# Create log files and set permissions
touch "$SCRIPT_DIR/data/logs/service.log"
touch "$SCRIPT_DIR/data/logs/service-error.log"
chmod 664 "$SCRIPT_DIR/data/logs/service.log"
chmod 664 "$SCRIPT_DIR/data/logs/service-error.log"

# Enable and start service
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "Enabling heim-view service..."
sudo systemctl enable heim-view.service
echo "Starting heim-view service..."
sudo systemctl start heim-view.service

echo "Installation complete!"
echo "Service status: $(systemctl is-active heim-view.service 2>/dev/null || echo 'unknown')"
echo "Application logs: $SCRIPT_DIR/data/logs/client.log and $SCRIPT_DIR/data/logs/update.log"
echo "Service logs: $SCRIPT_DIR/data/logs/service.log and $SCRIPT_DIR/data/logs/service-error.log"
echo "You can also check system logs with: journalctl -u heim-view.service -f"