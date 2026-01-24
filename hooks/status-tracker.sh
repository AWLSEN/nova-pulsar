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
THREAD_ID=""
PID_IN_MARKER=""

# 1. Check env var first (CLI agents / backward compat)
if [[ -n "${PULSAR_TASK_ID:-}" ]]; then
    TASK_ID="$PULSAR_TASK_ID"
    PROJECT_NAME="${PULSAR_PROJECT:-$(basename "$PWD")}"
    PLAN_ID=$(echo "$TASK_ID" | sed 's/^phase-[0-9]*-//')
    # Use sed instead of grep to avoid pipefail issues when pattern doesn't match
    PHASE_NUM=$(echo "$TASK_ID" | sed -n 's/.*phase-\([0-9]*\).*/\1/p')
fi

# 2. Check for session marker (native Task agents) - with self-healing
# Note: Pulsar pre-creates markers/phase-{N}.json before spawning
# Phase-executor claims it by adding PID, but if not, we self-heal
if [[ -z "$TASK_ID" ]]; then
    COMMS_BASE="$HOME/comms/plans"
    MARKER_FILE=""

    # Strategy 1: Direct PID lookup (legacy + phase-executor claimed by creating PID file)
    MARKER_FILE=$(find "$COMMS_BASE"/*/active/*/markers/"$PPID" -type f 2>/dev/null | head -1 || echo "")

    # Strategy 2: Scan phase-keyed markers for PID match or unclaimed
    if [[ -z "$MARKER_FILE" || ! -f "$MARKER_FILE" ]]; then
        for PLAN_DIR in "$COMMS_BASE"/*/active/*/; do
            [[ -d "$PLAN_DIR/markers" ]] || continue

            for f in "$PLAN_DIR/markers"/phase-*.json; do
                [[ -f "$f" ]] || continue

                PID_IN_MARKER=$(jq -r '.pid // "null"' "$f" 2>/dev/null || echo "null")

                # Already claimed by us
                if [[ "$PID_IN_MARKER" == "$PPID" ]]; then
                    MARKER_FILE="$f"
                    break 2
                fi

                # NOTE: We no longer claim unclaimed markers here.
                # Only the phase-executor should claim markers.
                # The hook only matches markers that are already claimed by this PID.
                # This prevents the orchestrator from stealing markers meant for sub-agents.
            done
        done
    fi

    if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
        TASK_ID=$(jq -r '.session_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PROJECT_NAME=$(jq -r '.project // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PLAN_ID=$(jq -r '.plan_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PHASE_NUM=$(jq -r '.phase // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        THREAD_ID=$(jq -r '.thread_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
    fi
fi

# Also check CONDUCTOR_THREAD_ID env var as fallback
if [[ -z "$THREAD_ID" && -n "${CONDUCTOR_THREAD_ID:-}" ]]; then
    THREAD_ID="$CONDUCTOR_THREAD_ID"
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
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}' 2>/dev/null || echo "{}")

# Extract file path if tool touches files
LAST_FILE=""
case "$TOOL_NAME" in
    Read|Write|Edit|MultiEdit)
        LAST_FILE=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null | head -1 || echo "")
        ;;
    Glob|Grep)
        LAST_FILE=$(echo "$TOOL_INPUT" | jq -r '.path // .pattern // ""' 2>/dev/null | head -1 || echo "")
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
    CURRENT_STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "{}")
    CURRENT_STATUS_VALUE=$(echo "$CURRENT_STATUS" | jq -r '.status // "running"' 2>/dev/null || echo "running")

    # If phase is already completed, don't overwrite with "running"
    # This prevents Pulsar's subsequent tool calls from reverting completion status
    if [[ "$CURRENT_STATUS_VALUE" == "completed" ]]; then
        echo '{}'
        exit 0
    fi

    TOOL_COUNT=$(echo "$CURRENT_STATUS" | jq -r '.tool_count // 0' 2>/dev/null || echo "0")
    STARTED_AT=$(echo "$CURRENT_STATUS" | jq -r '.started_at // ""' 2>/dev/null || echo "")
    # If started_at is empty, initialize it
    [[ -z "$STARTED_AT" ]] && STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

if jq -n \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
    --arg plan_id "$PLAN_ID" \
    --argjson phase "$PHASE_NUM" \
    --arg thread_id "$THREAD_ID" \
    --arg status "running" \
    --argjson tool_count "$TOOL_COUNT" \
    --arg last_tool "$TOOL_NAME" \
    --arg last_file "$LAST_FILE" \
    --arg updated_at "$UPDATED_AT" \
    --arg started_at "$STARTED_AT" \
    '{
        task_id: $task_id,
        project: $project,
        plan_id: $plan_id,
        phase: $phase,
        thread_id: (if $thread_id == "" then null else $thread_id end),
        status: $status,
        tool_count: $tool_count,
        last_tool: $last_tool,
        last_file: $last_file,
        updated_at: $updated_at,
        started_at: $started_at
    }' > "$TMP_FILE" 2>/dev/null; then
    # Atomic move to prevent partial reads
    mv "$TMP_FILE" "$STATUS_FILE" 2>/dev/null || true
else
    # jq failed, clean up and exit gracefully
    rm -f "$TMP_FILE" 2>/dev/null || true
fi

# Output empty JSON (hook API requirement)
echo '{}'
exit 0
