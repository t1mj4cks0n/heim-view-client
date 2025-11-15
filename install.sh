#!/bin/bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Install Client ---
echo -e "${GREEN}Installing Heim-View Client...${NC}"

# Create directories
sudo mkdir -p /opt/heim-view/logs
sudo mkdir -p /opt/heim-view/cache

# Install files
sudo cp heim-view.py /opt/heim-view/
sudo cp update_heim_view.sh /usr/local/bin/
sudo chmod +x /opt/heim-view/heim-view.py
sudo chmod 755 /usr/local/bin/update_heim_view.sh
sudo cp heim-view.service /usr/lib/systemd/system/

# Install dependencies
sudo apt update
sudo apt install -y python3 python3-pip git curl
sudo pip3 install requests

# Interactive config
read -p "Heim-View Server URL (e.g., http://localhost:5000/api/log): " server_url
read -p "Enable auto-updates? (y/n): " auto_update
auto_update=${auto_update,,}

sudo tee /opt/heim-view/config.json > /dev/null <<EOF
{
    "server_url": "$server_url",
    "interval_seconds": 30,
    "auto_update": $([[ $auto_update == "y" ]] && echo "true" || echo "false"),
    "github_repo": "https://raw.githubusercontent.com/t1mj4cks0n/heim-view-client/main",
    "version": "1.0"
}
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable heim-view
sudo systemctl start heim-view

echo -e "${GREEN}Heim-View Client installed successfully.${NC}"
echo "Logs: /opt/heim-view/logs/client.log"
echo "Update logs: /opt/heim-view/logs/update.log"
