#!/bin/bash
# pulsar-auto.sh - Auto-execute a plan in the background using Claude CLI
#
# Usage: ./pulsar-auto.sh <plan-id>
# Example: ./pulsar-auto.sh plan-20260105-1530
#
# This script runs Claude in non-interactive mode to execute a plan.
# Output is logged to ./comms/plans/logs/ (project-relative)

set -e

PLAN_ID="$1"
# Project-relative paths (must run from project root)
PLANS_DIR="./comms/plans"
LOGS_DIR="$PLANS_DIR/logs"
LOG_FILE="$LOGS_DIR/${PLAN_ID}.log"

# Validate input
if [ -z "$PLAN_ID" ]; then
    echo "Error: Plan ID required"
    echo "Usage: $0 <plan-id>"
    exit 1
fi

# Check if plan exists
PLAN_FILE=""
if [ -f "$PLANS_DIR/queued/auto/$PLAN_ID.md" ]; then
    PLAN_FILE="$PLANS_DIR/queued/auto/$PLAN_ID.md"
elif [ -f "$PLANS_DIR/queued/manual/$PLAN_ID.md" ]; then
    echo "Error: Plan $PLAN_ID is in manual queue, not auto"
    exit 1
else
    echo "Error: Plan $PLAN_ID not found in queued/auto/"
    exit 1
fi

# Create logs directory
mkdir -p "$LOGS_DIR"

echo "$(date -Iseconds) - Starting auto-execution of $PLAN_ID" | tee "$LOG_FILE"

# Run Claude in non-interactive mode with Pulsar
# Using --allowedTools to auto-approve necessary tools
nohup claude -p "Execute plan $PLAN_ID using /pulsar. The plan is located at $PLAN_FILE. Execute all phases, run tests, and move to review when complete." \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TaskOutput,TodoWrite" \
    --output-format text \
    >> "$LOG_FILE" 2>&1 &

CLAUDE_PID=$!
echo "$(date -Iseconds) - Claude process started with PID: $CLAUDE_PID" | tee -a "$LOG_FILE"
echo "$CLAUDE_PID" > "$LOGS_DIR/${PLAN_ID}.pid"

echo ""
echo "Auto-execution started in background"
echo "  Plan: $PLAN_ID"
echo "  PID: $CLAUDE_PID"
echo "  Log: $LOG_FILE"
echo ""
echo "Monitor with: tail -f $LOG_FILE"
echo "Check status: ps -p $CLAUDE_PID"
