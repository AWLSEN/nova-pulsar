#!/bin/bash
# setup.sh - Set up Starry Night folder structure and daemon management
#
# Usage: ./setup.sh [project-name] [--daemon start|stop|status]
#   project-name: Name for the project namespace (default: current directory name)
#   --daemon: Manage the background daemon (cross-platform, works on macOS/Linux)
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
RED='\033[0;31m'
NC='\033[0m' # No Color

COMMS_BASE="$HOME/comms/plans"
DAEMON_ACTION=""
PROJECT_NAME=""
PID_FILE="$COMMS_BASE/.starry-daemon.pid"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --daemon)
            DAEMON_ACTION="$2"
            shift 2
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

# Daemon management functions
daemon_start() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}Daemon already running (PID: $pid)${NC}"
            return 0
        fi
        # Stale PID file
        rm -f "$PID_FILE"
    fi

    echo -e "${YELLOW}Starting Starry Night daemon...${NC}"
    nohup "$SCRIPT_DIR/starry-daemon.sh" >> "$COMMS_BASE/daemon.log" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    sleep 1

    if ps -p "$new_pid" > /dev/null 2>&1; then
        echo -e "${GREEN}Daemon started (PID: $new_pid)${NC}"
        echo "Logs: tail -f $COMMS_BASE/daemon.log"
    else
        echo -e "${RED}Failed to start daemon${NC}"
        rm -f "$PID_FILE"
        return 1
    fi
}

daemon_stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Daemon not running (no PID file)${NC}"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${YELLOW}Stopping daemon (PID: $pid)...${NC}"
        kill "$pid" 2>/dev/null || true
        sleep 1
        # Force kill if still running
        if ps -p "$pid" > /dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        echo -e "${GREEN}Daemon stopped${NC}"
    else
        echo -e "${YELLOW}Daemon not running (stale PID file)${NC}"
    fi
    rm -f "$PID_FILE"
}

daemon_status() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Daemon: not running${NC}"
        return 1
    fi

    local pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${GREEN}Daemon: running (PID: $pid)${NC}"
        echo "Logs: $COMMS_BASE/daemon.log"
        # Show recent log
        if [ -f "$COMMS_BASE/daemon.log" ]; then
            echo ""
            echo "Recent activity:"
            tail -5 "$COMMS_BASE/daemon.log" 2>/dev/null || true
        fi
        return 0
    else
        echo -e "${YELLOW}Daemon: not running (stale PID file)${NC}"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Handle daemon commands
if [ -n "$DAEMON_ACTION" ]; then
    mkdir -p "$COMMS_BASE"
    case "$DAEMON_ACTION" in
        start)
            daemon_start
            ;;
        stop)
            daemon_stop
            ;;
        status)
            daemon_status
            ;;
        restart)
            daemon_stop
            sleep 1
            daemon_start
            ;;
        *)
            echo -e "${RED}Unknown daemon action: $DAEMON_ACTION${NC}"
            echo "Usage: ./setup.sh --daemon [start|stop|status|restart]"
            exit 1
            ;;
    esac
    exit 0
fi

# Done
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Install the plugin:  /plugin install starry-night@awlsen-plugins"
echo "  2. Create a plan:       /nova <task description>"
echo "  3. Execute a plan:      /pulsar [plan-id]"
echo ""
echo "Daemon management (cross-platform):"
echo "  Start:   ./setup.sh --daemon start"
echo "  Stop:    ./setup.sh --daemon stop"
echo "  Status:  ./setup.sh --daemon status"
echo "  Restart: ./setup.sh --daemon restart"
echo ""
echo "Your plans will be stored in: $PROJECT_DIR/"
echo ""
