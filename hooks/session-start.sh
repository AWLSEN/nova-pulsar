#!/bin/bash
# session-start.sh - Initialize status file when sub-agent starts
#
# Part of Starry Night plugin
#
# Creates initial status file with status: "starting"
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

# Wait briefly for orchestrator to create directory (race condition mitigation)
for i in 1 2 3; do
    [[ -d "$STATUS_DIR" ]] && break
    sleep 0.1
done

# Exit if directory still doesn't exist
if [[ ! -d "$STATUS_DIR" ]]; then
    echo '{}'
    exit 0
fi

STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write initial status
TMP_FILE="${STATUS_FILE}.tmp.$$"

jq -n \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
    --arg status "starting" \
    --argjson tool_count 0 \
    --arg last_tool "" \
    --arg last_file "" \
    --arg updated_at "$STARTED_AT" \
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

mv "$TMP_FILE" "$STATUS_FILE"

echo '{}'
exit 0
