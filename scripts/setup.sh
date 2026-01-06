#!/bin/bash
# setup.sh - Set up Nova-Pulsar folder structure and optional systemd service
#
# Usage: ./setup.sh [--with-systemd]
#   --with-systemd: Also install the systemd user service for auto-execution

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PLANS_DIR="$HOME/comms/plans"
INSTALL_SYSTEMD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-systemd)
            INSTALL_SYSTEMD=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${GREEN}Nova-Pulsar Setup${NC}"
echo "=================="
echo ""

# Step 1: Create folder structure
echo -e "${YELLOW}Creating folder structure...${NC}"

mkdir -p "$PLANS_DIR/queued/auto"
mkdir -p "$PLANS_DIR/queued/manual"
mkdir -p "$PLANS_DIR/active"
mkdir -p "$PLANS_DIR/review"
mkdir -p "$PLANS_DIR/archived"
mkdir -p "$PLANS_DIR/logs"

# Create board.json if it doesn't exist
if [ ! -f "$PLANS_DIR/board.json" ]; then
    echo '[]' > "$PLANS_DIR/board.json"
    echo "  Created: $PLANS_DIR/board.json"
else
    echo "  Exists: $PLANS_DIR/board.json"
fi

echo "  Created: $PLANS_DIR/"
echo "    ├── queued/auto/"
echo "    ├── queued/manual/"
echo "    ├── active/"
echo "    ├── review/"
echo "    ├── archived/"
echo "    └── logs/"
echo ""

# Step 2: Make scripts executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/pulsar-watcher.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/pulsar-auto.sh" 2>/dev/null || true
echo -e "${YELLOW}Made scripts executable${NC}"
echo ""

# Step 3: Install systemd service (optional)
if [ "$INSTALL_SYSTEMD" = true ]; then
    echo -e "${YELLOW}Installing systemd user service...${NC}"

    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    # Determine the plugin path (where this script is located)
    PLUGIN_SCRIPTS_DIR="$SCRIPT_DIR"

    cat > "$SYSTEMD_DIR/pulsar-watcher.service" << EOF
[Unit]
Description=Pulsar Plan Watcher - Auto-executes queued plans
After=default.target

[Service]
Type=simple
ExecStart=$PLUGIN_SCRIPTS_DIR/pulsar-watcher.sh
Restart=on-failure
RestartSec=30
Environment=HOME=$HOME
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

    echo "  Created: $SYSTEMD_DIR/pulsar-watcher.service"

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable pulsar-watcher

    echo ""
    echo -e "${GREEN}Systemd service installed!${NC}"
    echo ""
    echo "Commands:"
    echo "  Start:   systemctl --user start pulsar-watcher"
    echo "  Stop:    systemctl --user stop pulsar-watcher"
    echo "  Status:  systemctl --user status pulsar-watcher"
    echo "  Logs:    journalctl --user -u pulsar-watcher -f"
    echo ""
else
    echo "Tip: Run with --with-systemd to install auto-execution service"
    echo ""
fi

# Done
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Install the plugin:  /plugin install AWLSEN/nova-pulsar"
echo "  2. Create a plan:       /nova"
echo "  3. Execute a plan:      /pulsar [plan-id]"
echo ""
