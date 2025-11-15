#!/bin/bash
set -euo pipefail

# Create directories
sudo mkdir -p /opt/monitor_client/logs
sudo mkdir -p /opt/monitor_client/cache

# Install script and update tool
sudo cp monitor_client.py /opt/monitor_client/
sudo cp update_monitor_client.sh /usr/local/bin/
sudo chmod +x /opt/monitor_client/monitor_client.py
sudo chmod 755 /usr/local/bin/update_monitor_client.sh

# Install dependencies
sudo apt update
sudo apt install -y python3 python3-pip git curl
sudo pip3 install requests

# Interactive config setup
echo "Setting up monitor_client..."
read -p "Enter server URL (e.g., http://host:5000/log): " server_url
read -p "Enable auto-updates? (y/n): " auto_update
auto_update=${auto_update,,}  # to lowercase

# Create config
sudo tee /opt/monitor_client/config.json > /dev/null <<EOF
{
    "server_url": "$server_url",
    "interval_seconds": 30,
    "auto_update": $([[ $auto_update == "y" ]] && echo "true" || echo "false"),
    "github_repo": "https://raw.githubusercontent.com/t1mj4cks0n/main/monitor_client",
    "version": "1.0"
}
EOF

# Install systemd service
sudo cp monitor_client.service /usr/lib/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable monitor_client
sudo systemctl start monitor_client

echo "Installation complete."
echo "Logs: /opt/monitor_client/logs/monitor_client.log"
echo "Update logs: /opt/monitor_client/logs/update.log"
