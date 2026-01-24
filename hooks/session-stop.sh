#!/bin/bash
# session-stop.sh - Mark status file as completed/failed when sub-agent exits
#
# Part of Starry Night plugin
#
# Updates status field to "completed" or "failed" based on exit context.
# Also cleans up marker files for native Task agents.
#
# Supported contexts:
#   1. CLI agents: PULSAR_TASK_ID env var set
#   2. Native Task agents: Marker file at ~/comms/plans/*/active/*/markers/$PPID
#
# Required env vars (for CLI agents):
#   PULSAR_TASK_ID: format "phase-N-plan-YYYYMMDD-HHMM"
#   PULSAR_PROJECT: project namespace name

set -euo pipefail

# Read hook input (may contain error indicators)
HOOK_INPUT=$(cat)

TASK_ID=""
PROJECT_NAME=""
PLAN_ID=""
PHASE_NUM=""
MARKER_FILE=""
PID_IN_MARKER=""

# 1. Check env var first (CLI agents / backward compat)
if [[ -n "${PULSAR_TASK_ID:-}" ]]; then
    TASK_ID="$PULSAR_TASK_ID"
    PROJECT_NAME="${PULSAR_PROJECT:-$(basename "$PWD")}"
    PLAN_ID=$(echo "$TASK_ID" | sed 's/^phase-[0-9]*-//')
    # Use sed instead of grep to avoid pipefail issues
    PHASE_NUM=$(echo "$TASK_ID" | sed -n 's/.*phase-\([0-9]*\).*/\1/p')
fi

# 2. Check for session marker (native Task agents) - with self-healing
if [[ -z "$TASK_ID" ]]; then
    COMMS_BASE="$HOME/comms/plans"

    # Strategy 1: Direct PID lookup (legacy + phase-executor claimed)
    MARKER_FILE=$(find "$COMMS_BASE"/*/active/*/markers/"$PPID" -type f 2>/dev/null | head -1 || echo "")

    # Strategy 2: Scan phase-keyed markers for PID match
    if [[ -z "$MARKER_FILE" || ! -f "$MARKER_FILE" ]]; then
        for PLAN_DIR in "$COMMS_BASE"/*/active/*/; do
            [[ -d "$PLAN_DIR/markers" ]] || continue

            for f in "$PLAN_DIR/markers"/phase-*.json; do
                [[ -f "$f" ]] || continue

                PID_IN_MARKER=$(jq -r '.pid // "null"' "$f" 2>/dev/null || echo "null")

                # Found our marker (claimed by us)
                if [[ "$PID_IN_MARKER" == "$PPID" ]]; then
                    MARKER_FILE="$f"
                    break 2
                fi
            done
        done
    fi

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

# Exit if status file doesn't exist
if [[ ! -f "$STATUS_FILE" ]]; then
    echo '{}'
    exit 0
fi

# Read current status (with error handling)
CURRENT_STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "{}")
TOOL_COUNT=$(echo "$CURRENT_STATUS" | jq -r '.tool_count // 0' 2>/dev/null || echo "0")
STARTED_AT=$(echo "$CURRENT_STATUS" | jq -r '.started_at // ""' 2>/dev/null || echo "")
LAST_TOOL=$(echo "$CURRENT_STATUS" | jq -r '.last_tool // ""' 2>/dev/null || echo "")
LAST_FILE=$(echo "$CURRENT_STATUS" | jq -r '.last_file // ""' 2>/dev/null || echo "")
THREAD_ID=$(echo "$CURRENT_STATUS" | jq -r '.thread_id // ""' 2>/dev/null || echo "")
# Fallback to env var if thread_id not in status file
if [[ -z "$THREAD_ID" && -n "${CONDUCTOR_THREAD_ID:-}" ]]; then
    THREAD_ID="$CONDUCTOR_THREAD_ID"
fi
# If started_at is empty, initialize it
[[ -z "$STARTED_AT" ]] && STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

COMPLETED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine final status
# Check hook input for error indicators
STOP_REASON=$(echo "$HOOK_INPUT" | jq -r '.reason // ""' 2>/dev/null || echo "")

if [[ "$STOP_REASON" == *"error"* ]] || [[ "$STOP_REASON" == *"fail"* ]]; then
    FINAL_STATUS="failed"
else
    FINAL_STATUS="completed"
fi

# Write final status
TMP_FILE="${STATUS_FILE}.tmp.$$"

if jq -n \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
    --arg plan_id "$PLAN_ID" \
    --argjson phase "$PHASE_NUM" \
    --arg thread_id "$THREAD_ID" \
    --arg status "$FINAL_STATUS" \
    --argjson tool_count "$TOOL_COUNT" \
    --arg last_tool "$LAST_TOOL" \
    --arg last_file "$LAST_FILE" \
    --arg updated_at "$COMPLETED_AT" \
    --arg started_at "$STARTED_AT" \
    --arg completed_at "$COMPLETED_AT" \
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
        started_at: $started_at,
        completed_at: $completed_at
    }' > "$TMP_FILE" 2>/dev/null; then
    mv "$TMP_FILE" "$STATUS_FILE" 2>/dev/null || true
else
    rm -f "$TMP_FILE" 2>/dev/null || true
fi

# Cleanup marker file if it exists (native Task agents)
# Clean up both PID-keyed and phase-keyed markers
if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
    rm -f "$MARKER_FILE" 2>/dev/null || true
fi
# Also try to clean up phase-keyed marker if it exists
COMMS_BASE="${HOME}/comms/plans"
PHASE_MARKER="${COMMS_BASE}/${PROJECT_NAME}/active/${PLAN_ID}/markers/phase-${PHASE_NUM}.json"
if [[ -f "$PHASE_MARKER" ]]; then
    rm -f "$PHASE_MARKER" 2>/dev/null || true
fi

echo '{}'
exit 0
