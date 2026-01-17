#!/bin/bash
# session-start.sh - Initialize status file when sub-agent starts
#
# Part of Starry Night plugin
#
# Creates initial status file with status: "starting"
# Also checks if Orbiter watcher should be spawned.
#
# Supported contexts:
#   1. CLI agents: PULSAR_TASK_ID env var set
#   2. Native Task agents: Marker file at ~/comms/plans/*/active/*/markers/$PPID
#
# Required env vars (for CLI agents):
#   PULSAR_TASK_ID: format "phase-N-plan-YYYYMMDD-HHMM"
#   PULSAR_PROJECT: project namespace name

set -euo pipefail

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
# Note: Marker may not exist yet at session start - phase-executor writes it as first action
# This hook may be called before the marker exists, so we check but don't fail
if [[ -z "$TASK_ID" ]]; then
    MARKER_FILE=$(find "$HOME/comms/plans"/*/active/*/markers/"$PPID" -type f 2>/dev/null | head -1)
    if [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]]; then
        TASK_ID=$(jq -r '.session_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PROJECT_NAME=$(jq -r '.project // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PLAN_ID=$(jq -r '.plan_id // ""' "$MARKER_FILE" 2>/dev/null || echo "")
        PHASE_NUM=$(jq -r '.phase // ""' "$MARKER_FILE" 2>/dev/null || echo "")
    fi
fi

# If still no context, exit (not a Pulsar sub-agent, or marker not yet written)
if [[ -z "$TASK_ID" || -z "$PROJECT_NAME" || -z "$PLAN_ID" || -z "$PHASE_NUM" ]]; then
    # Check if Orbiter should start (run on any session start)
    COMMS_BASE="${HOME}/comms/plans"
    if [[ -d "$COMMS_BASE" ]]; then
        # Count active and queued plans across all projects
        ACTIVE_COUNT=$(find "$COMMS_BASE"/*/active -maxdepth 1 -type d 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
        QUEUED_COUNT=$(find "$COMMS_BASE"/*/queued -maxdepth 2 -type d 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')

        # If there are active/queued plans and no Orbiter running, could spawn one
        # (Orbiter auto-start disabled for now - uncomment when ready)
        # if [[ $((ACTIVE_COUNT + QUEUED_COUNT)) -gt 0 ]]; then
        #     if ! pgrep -f 'orbiter-watcher' > /dev/null 2>&1; then
        #         nohup claude --model haiku "Run as Orbiter watcher for $PROJECT_NAME" > /dev/null 2>&1 &
        #     fi
        # fi
    fi
    echo '{}'
    exit 0
fi

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
