#!/bin/bash
# setup.sh - Set up Starry Night folder structure and optional systemd service
#
# Usage: ./setup.sh [project-name] [--with-systemd]
#   project-name: Name for the project namespace (default: current directory name)
#   --with-systemd: Also install the systemd user service for background execution
#
# Directory structure (namespaced by project):
#   ~/comms/plans/
#   ├── {project-name}/
#   │   ├── queued/background/
#   │   ├── queued/interactive/
#   │   ├── active/
#   │   ├── review/
#   │   ├── archived/
#   │   └── logs/
#   └── daemon.log

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

COMMS_BASE="$HOME/comms/plans"
INSTALL_SYSTEMD=false
PROJECT_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-systemd)
            INSTALL_SYSTEMD=true
            shift
            ;;
        -*)
            # Unknown flag, skip
            shift
            ;;
        *)
            # Positional argument = project name
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            fi
            shift
            ;;
    esac
done

# Default project name to current directory name
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(basename "$PWD")
fi

PROJECT_DIR="$COMMS_BASE/$PROJECT_NAME"

echo -e "${GREEN}Starry Night Setup${NC}"
echo "==================="
echo ""
echo -e "${BLUE}Project: $PROJECT_NAME${NC}"
echo -e "${BLUE}Path: $PWD${NC}"
echo ""

# Step 1: Create base comms directory
mkdir -p "$COMMS_BASE"

# Step 2: Create project namespace folder structure
echo -e "${YELLOW}Creating project namespace...${NC}"

mkdir -p "$PROJECT_DIR/queued/background"
mkdir -p "$PROJECT_DIR/queued/interactive"
mkdir -p "$PROJECT_DIR/active"
mkdir -p "$PROJECT_DIR/review"
mkdir -p "$PROJECT_DIR/archived"
mkdir -p "$PROJECT_DIR/logs"

# Create project config if it doesn't exist
if [ ! -f "$PROJECT_DIR/config.json" ]; then
    cat > "$PROJECT_DIR/config.json" << EOF
{
  "projectName": "$PROJECT_NAME",
  "projectPath": "$PWD",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    echo "  Created: $PROJECT_DIR/config.json"
else
    echo "  Exists: $PROJECT_DIR/config.json"
fi

echo ""
echo "  Created: $COMMS_BASE/"
echo "    └── $PROJECT_NAME/"
echo "        ├── queued/background/"
echo "        ├── queued/interactive/"
echo "        ├── active/"
echo "        ├── review/"
echo "        ├── archived/"
echo "        ├── logs/"
echo "        └── config.json"
echo ""

# Step 3: Make scripts executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/starry-daemon.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/pulsar-auto.sh" 2>/dev/null || true
echo -e "${YELLOW}Made scripts executable${NC}"
echo ""

# Step 4: Install systemd service (optional)
if [ "$INSTALL_SYSTEMD" = true ]; then
    echo -e "${YELLOW}Installing systemd user service...${NC}"

    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    PLUGIN_SCRIPTS_DIR="$SCRIPT_DIR"

    cat > "$SYSTEMD_DIR/starry-daemon.service" << EOF
[Unit]
Description=Starry Night Daemon - Background plan execution
After=default.target

[Service]
Type=simple
ExecStart=$PLUGIN_SCRIPTS_DIR/starry-daemon.sh
Restart=on-failure
RestartSec=30
Environment=HOME=$HOME
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

    echo "  Created: $SYSTEMD_DIR/starry-daemon.service"

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable starry-daemon

    echo ""
    echo -e "${GREEN}Systemd service installed!${NC}"
    echo ""
    echo "Commands:"
    echo "  Start:   systemctl --user start starry-daemon"
    echo "  Stop:    systemctl --user stop starry-daemon"
    echo "  Status:  systemctl --user status starry-daemon"
    echo "  Logs:    journalctl --user -u starry-daemon -f"
    echo ""
else
    echo "Tip: Run with --with-systemd to install background execution service"
    echo ""
fi

# Done
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Install the plugin:  /plugin install starry-night@awlsen-plugins --scope user"
echo "  2. Create a plan:       /nova <task description>"
echo "  3. Execute a plan:      /pulsar [plan-id]"
echo ""
echo "Your plans will be stored in: $PROJECT_DIR/"
echo ""
