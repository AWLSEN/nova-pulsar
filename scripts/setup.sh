#!/bin/bash
# setup.sh - Set up Nova-Pulsar folder structure for a project
#
# Usage: ./setup.sh [project-path]
#   project-path: Optional path to project directory (defaults to current directory)
#
# Run this from your project root or specify the project path.
# Creates ./comms/plans/ structure for the project.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Use provided path or current directory
PROJECT_DIR="${1:-.}"
PLANS_DIR="$PROJECT_DIR/comms/plans"
STATUS_DIR="$PROJECT_DIR/comms/status"

echo -e "${GREEN}Nova-Pulsar Setup${NC}"
echo "=================="
echo ""
echo "Project: $(cd "$PROJECT_DIR" && pwd)"
echo ""

# Step 1: Create folder structure
echo -e "${YELLOW}Creating folder structure...${NC}"

mkdir -p "$PLANS_DIR/queued/auto"
mkdir -p "$PLANS_DIR/queued/manual"
mkdir -p "$PLANS_DIR/active"
mkdir -p "$PLANS_DIR/review"
mkdir -p "$PLANS_DIR/archived"
mkdir -p "$PLANS_DIR/logs"
mkdir -p "$STATUS_DIR"

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
echo "  Created: $STATUS_DIR/"
echo ""

# Step 2: Make scripts executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/pulsar-watcher.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/pulsar-auto.sh" 2>/dev/null || true
echo -e "${YELLOW}Made scripts executable${NC}"
echo ""

# Done
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Create a plan:       /nova"
echo "  2. Execute a plan:      /pulsar [plan-id]"
echo ""
echo "Note: Run this script in each project where you want to use Nova-Pulsar."
echo ""
