#!/bin/bash
set -euo pipefail
INSTALL_DIR="/opt/heim-view"
SCRIPT_NAME="heim-view.py"
CONFIG_FILE="$INSTALL_DIR/config.json"
LOG_FILE="$INSTALL_DIR/logs/update.log"
GITHUB_REPO="${1:-https://raw.githubusercontent.com/t1mj4cks0n/heim-view-client/main}"

exec >> "$LOG_FILE" 2>&1
echo "=== Update started at $(date) ==="

curl -s -o "/tmp/$SCRIPT_NAME" "$GITHUB_REPO/$SCRIPT_NAME" || exit 1
systemctl stop heim-view || exit 1
cp "$CONFIG_FILE" "/tmp/config.json.backup"
mv "/tmp/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
mv "/tmp/config.json.backup" "$CONFIG_FILE"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
systemctl start heim-view
echo "Update completed at $(date)"
