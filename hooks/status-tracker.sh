#!/bin/bash
# status-tracker.sh - PostToolUse hook for Pulsar sub-agent status tracking
#
# Part of Starry Night plugin
#
# Tracks sub-agent progress by updating status files on each tool use.
# Uses atomic writes to prevent partial reads by orchestrator.
#
# Supported contexts:
#   1. CLI agents: PULSAR_TASK_ID env var set
#   2. Native Task agents: Marker file at ~/comms/plans/*/active/*/markers/$PPID
#
# Required env vars (for CLI agents):
#   PULSAR_TASK_ID: format "phase-N-plan-YYYYMMDD-HHMM"
#   PULSAR_PROJECT: project namespace name

set -euo pipefail

# Read hook input from stdin first (must be consumed)
HOOK_INPUT=$(cat)

TASK_ID=""
PROJECT_NAME=""
PLAN_ID=""
PHASE_NUM=""

# 1. Check env var first (CLI agents / backward compat)
if [[ -n "${PULSAR_TASK_ID:-}" ]]; then
    TASK_ID="$PULSAR_TASK_ID"
    PROJECT_NAME="${PULSAR_PROJECT:-$(basename "$PWD")}"
    PLAN_ID=$(echo "$TASK_ID" | sed 's/^phase-[0-9]*-//')
    PHASE_NUM=$(echo "$TASK_ID" | grep -oE 'phase-[0-9]+' | grep -oE '[0-9]+')
fi

# 2. Check for session marker (native Task agents)
if [[ -z "$TASK_ID" ]]; then
    MARKER_FILE=$(find "$HOME/comms/plans"/*/active/*/markers/"$PPID" -type f 2>/dev/null | head -1)
    if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
        TASK_ID=$(jq -r '.session_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PROJECT_NAME=$(jq -r '.project // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PLAN_ID=$(jq -r '.plan_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PHASE_NUM=$(jq -r '.phase // ""' "$MARKER_FILE" 2>/dev/null || echo "")
    fi
fi

# If no context found, exit (not a Pulsar sub-agent)
if [[ -z "$TASK_ID" || -z "$PROJECT_NAME" || -z "$PLAN_ID" || -z "$PHASE_NUM" ]]; then
    echo '{}'
    exit 0
fi

# Determine status directory (namespaced by project)
COMMS_BASE="${HOME}/comms/plans"
STATUS_DIR="${COMMS_BASE}/${PROJECT_NAME}/active/${PLAN_ID}/status"
STATUS_FILE="${STATUS_DIR}/phase-${PHASE_NUM}.status"

# Create status directory if it doesn't exist (needed for native Task agents
# where session-start may not have created it yet)
if [[ ! -d "$STATUS_DIR" ]]; then
    mkdir -p "$STATUS_DIR" 2>/dev/null || {
        echo '{}'
        exit 0
    }
fi

# Extract tool information from hook input
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')

# Extract file path if tool touches files
LAST_FILE=""
case "$TOOL_NAME" in
    Read|Write|Edit|MultiEdit)
        LAST_FILE=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null | head -1)
        ;;
    Glob|Grep)
        LAST_FILE=$(echo "$TOOL_INPUT" | jq -r '.path // .pattern // ""' 2>/dev/null | head -1)
        ;;
    Bash)
        # Try to extract file from command (rough heuristic)
        LAST_FILE=$(echo "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null | grep -oE '/[^ ]+\.[a-zA-Z]+' | head -1 || echo "")
        ;;
esac

# Ensure LAST_FILE is not null
LAST_FILE="${LAST_FILE:-}"

# Read existing status file or initialize
if [[ -f "$STATUS_FILE" ]]; then
    CURRENT_STATUS=$(cat "$STATUS_FILE")
    TOOL_COUNT=$(echo "$CURRENT_STATUS" | jq -r '.tool_count // 0')
    STARTED_AT=$(echo "$CURRENT_STATUS" | jq -r '.started_at')
else
    TOOL_COUNT=0
    STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Increment tool count
TOOL_COUNT=$((TOOL_COUNT + 1))

# Get current timestamp
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON status using jq for safe escaping
TMP_FILE="${STATUS_FILE}.tmp.$$"

jq -n \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
    --arg status "running" \
    --argjson tool_count "$TOOL_COUNT" \
    --arg last_tool "$TOOL_NAME" \
    --arg last_file "$LAST_FILE" \
    --arg updated_at "$UPDATED_AT" \
    --arg started_at "$STARTED_AT" \
    '{
        task_id: $task_id,
        project: $project,
        status: $status,
        tool_count: $tool_count,
        last_tool: $last_tool,
        last_file: $last_file,
        updated_at: $updated_at,
        started_at: $started_at
    }' > "$TMP_FILE"

# Atomic move to prevent partial reads
mv "$TMP_FILE" "$STATUS_FILE"

# Output empty JSON (hook API requirement)
echo '{}'
exit 0
