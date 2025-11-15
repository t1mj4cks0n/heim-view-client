#!/bin/bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Functions ---
install_client() {
    echo -e "${GREEN}Installing Heim-View Client...${NC}"

    # Create directories
    sudo mkdir -p /opt/heim-view/logs
    sudo mkdir -p /opt/heim-view/cache

    # Install files
    sudo cp client/heim-view.py /opt/heim-view/
    sudo cp client/update_heim_view.sh /usr/local/bin/
    sudo chmod +x /opt/heim-view/heim-view.py
    sudo chmod 755 /usr/local/bin/update_heim_view.sh
    sudo cp client/heim-view.service /usr/lib/systemd/system/

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
    "github_repo": "https://raw.githubusercontent.com/t1mj4cks0n/heim-view/main/client",
    "version": "1.0"
}
EOF

    # Start service
    sudo systemctl daemon-reload
    sudo systemctl enable heim-view
    sudo systemctl start heim-view

    echo -e "${GREEN}Heim-View Client installed.${NC}"
    echo "Logs: /opt/heim-view/logs/client.log"
    echo "Update logs: /opt/heim-view/logs/update.log"
}

install_server() {
    echo -e "${GREEN}Installing Heim-View Server...${NC}"

    # Create directories
    sudo mkdir -p /var/lib/heim-view
    sudo mkdir -p /var/log/heim-view
    sudo mkdir -p /opt/heim-view-server/static
    sudo mkdir -p /opt/heim-view-server/templates

    # Install dependencies
    sudo apt update
    sudo apt install -y python3 python3-pip python3-flask sqlite3
    sudo pip3 install flask

    # Install files
    sudo cp server/app.py /opt/heim-view-server/
    sudo cp -r server/static /opt/heim-view-server/
    sudo cp -r server/templates /opt/heim-view-server/
    sudo cp server/heim-view-server.service /usr/lib/systemd/system/
    sudo chmod +x /opt/heim-view-server/app.py

    # Start service
    sudo systemctl daemon-reload
    sudo systemctl enable heim-view-server
    sudo systemctl start heim-view-server

    echo -e "${GREEN}Heim-View Server installed.${NC}"
    echo "Access dashboard at http://$(hostname -I | awk '{print $1}'):5000/dashboard"
}

# --- Main Script ---
echo -e "${YELLOW}Heim-View Unified Installer${NC}"
echo "Choose what to install:"
echo "1. Client only"
echo "2. Server only"
echo "3. Both Client and Server"
echo "4. Exit"
read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        install_client
        ;;
    2)
        install_server
        ;;
    3)
        install_client
        install_server
        ;;
    4)
        echo -e "${YELLOW}Exiting.${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Installation complete!${NC}"
