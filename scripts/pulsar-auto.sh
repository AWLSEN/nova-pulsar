#!/bin/bash
# pulsar-auto.sh - Execute a plan in background mode using Claude CLI
#
# Part of Starry Night plugin
#
# Usage: ./pulsar-auto.sh <project-name> <plan-id>
# Example: ./pulsar-auto.sh spoq-tui plan-20260105-1530
#
# This script:
# 1. Reads the plan to get the project path
# 2. Changes to the project directory
# 3. Runs Claude in non-interactive mode to execute the plan
#
# Output is logged to ~/comms/plans/{project}/logs/

set -e

PROJECT_NAME="$1"
PLAN_ID="$2"
COMMS_BASE="$HOME/comms/plans"
PROJECT_COMMS="$COMMS_BASE/$PROJECT_NAME"
LOGS_DIR="$PROJECT_COMMS/logs"
LOG_FILE="$LOGS_DIR/${PLAN_ID}.log"

# Validate input
if [ -z "$PROJECT_NAME" ] || [ -z "$PLAN_ID" ]; then
    echo "Error: Project name and Plan ID required"
    echo "Usage: $0 <project-name> <plan-id>"
    exit 1
fi

# Check if project namespace exists
if [ ! -d "$PROJECT_COMMS" ]; then
    echo "Error: Project namespace '$PROJECT_NAME' not found at $PROJECT_COMMS"
    exit 1
fi

# Check if plan exists
PLAN_FILE=""
if [ -f "$PROJECT_COMMS/queued/background/$PLAN_ID.md" ]; then
    PLAN_FILE="$PROJECT_COMMS/queued/background/$PLAN_ID.md"
elif [ -f "$PROJECT_COMMS/queued/interactive/$PLAN_ID.md" ]; then
    echo "Error: Plan $PLAN_ID is in interactive queue, not background"
    exit 1
else
    echo "Error: Plan $PLAN_ID not found in $PROJECT_COMMS/queued/background/"
    exit 1
fi

# Extract project path from plan metadata
# Look for "Project Path:" or "projectPath:" in the plan file
PROJECT_PATH=$(grep -E '^\s*[-*]\s*\*?\*?Project Path\*?\*?:' "$PLAN_FILE" | head -1 | sed 's/.*:\s*//' | xargs)

if [ -z "$PROJECT_PATH" ]; then
    # Try JSON format in case it's in frontmatter or metadata block
    PROJECT_PATH=$(grep -oP '"projectPath"\s*:\s*"\K[^"]+' "$PLAN_FILE" | head -1)
fi

if [ -z "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH" ]; then
    echo "Warning: Could not find valid project path in plan, using HOME"
    PROJECT_PATH="$HOME"
fi

# Create logs directory
mkdir -p "$LOGS_DIR"

echo "$(date -Iseconds) - Starting background execution" | tee "$LOG_FILE"
echo "  Project: $PROJECT_NAME" | tee -a "$LOG_FILE"
echo "  Plan: $PLAN_ID" | tee -a "$LOG_FILE"
echo "  Project Path: $PROJECT_PATH" | tee -a "$LOG_FILE"
echo "  Plan File: $PLAN_FILE" | tee -a "$LOG_FILE"

# Change to project directory and run Claude
cd "$PROJECT_PATH"

# Run Claude in non-interactive mode with Pulsar
# Using --allowedTools to auto-approve necessary tools
nohup claude -p "Execute plan $PLAN_ID using /pulsar $PLAN_ID. The plan is located at $PLAN_FILE. Execute all phases, run tests, and mark as completed when done." \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TaskOutput,TodoWrite" \
    --output-format text \
    >> "$LOG_FILE" 2>&1 &

CLAUDE_PID=$!
echo "$(date -Iseconds) - Claude process started with PID: $CLAUDE_PID" | tee -a "$LOG_FILE"
echo "$CLAUDE_PID" > "$LOGS_DIR/${PLAN_ID}.pid"

echo ""
echo "Background execution started"
echo "  Project: $PROJECT_NAME"
echo "  Plan: $PLAN_ID"
echo "  Working Dir: $PROJECT_PATH"
echo "  PID: $CLAUDE_PID"
echo "  Log: $LOG_FILE"
echo ""
echo "Monitor with: tail -f $LOG_FILE"
echo "Check status: ps -p $CLAUDE_PID"
