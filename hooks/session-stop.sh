#!/bin/bash
# session-stop.sh - Mark status file as completed/failed when sub-agent exits
#
# Part of Starry Night plugin
#
# Updates status field to "completed" or "failed" based on exit context
#
# Required env vars:
#   PULSAR_TASK_ID: format "phase-N-plan-YYYYMMDD-HHMM"
#   PULSAR_PROJECT: project namespace name

set -euo pipefail

# Fast exit if not a Pulsar sub-agent
if [[ -z "${PULSAR_TASK_ID:-}" ]]; then
    echo '{}'
    exit 0
fi

# Read hook input (may contain error indicators)
HOOK_INPUT=$(cat)

TASK_ID="$PULSAR_TASK_ID"

# Get project name (required for namespaced paths)
PROJECT_NAME="${PULSAR_PROJECT:-}"
if [[ -z "$PROJECT_NAME" ]]; then
    # Fallback: try to get from PWD
    PROJECT_NAME=$(basename "$PWD")
fi

# Extract plan ID from task ID (everything after "phase-N-")
PLAN_ID=$(echo "$TASK_ID" | sed 's/^phase-[0-9]*-//')

# Extract phase number
PHASE_NUM=$(echo "$TASK_ID" | grep -oE 'phase-[0-9]+' | grep -oE '[0-9]+')

# Determine status directory (namespaced by project)
COMMS_BASE="${HOME}/comms/plans"
STATUS_DIR="${COMMS_BASE}/${PROJECT_NAME}/active/${PLAN_ID}/status"
STATUS_FILE="${STATUS_DIR}/phase-${PHASE_NUM}.status"

# Exit if status file doesn't exist
if [[ ! -f "$STATUS_FILE" ]]; then
    echo '{}'
    exit 0
fi

# Read current status
CURRENT_STATUS=$(cat "$STATUS_FILE")
TOOL_COUNT=$(echo "$CURRENT_STATUS" | jq -r '.tool_count // 0')
STARTED_AT=$(echo "$CURRENT_STATUS" | jq -r '.started_at')
LAST_TOOL=$(echo "$CURRENT_STATUS" | jq -r '.last_tool // ""')
LAST_FILE=$(echo "$CURRENT_STATUS" | jq -r '.last_file // ""')

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

jq -n \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
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
        status: $status,
        tool_count: $tool_count,
        last_tool: $last_tool,
        last_file: $last_file,
        updated_at: $updated_at,
        started_at: $started_at,
        completed_at: $completed_at
    }' > "$TMP_FILE"

mv "$TMP_FILE" "$STATUS_FILE"

echo '{}'
exit 0
