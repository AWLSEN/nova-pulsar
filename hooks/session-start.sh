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

                # Unclaimed marker (pid is null) - claim it!
                if [[ "$PID_IN_MARKER" == "null" ]]; then
                    if jq --arg pid "$PPID" '.pid = $pid' "$f" > "$f.tmp" 2>/dev/null; then
                        mv "$f.tmp" "$f" 2>/dev/null || true
                        MARKER_FILE="$f"
                        break 2
                    fi
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

# If still no context, exit (not a Pulsar sub-agent, or marker not yet written)
if [[ -z "$TASK_ID" || -z "$PROJECT_NAME" || -z "$PLAN_ID" || -z "$PHASE_NUM" ]]; then
    # Check if Orbiter should start (run on any session start)
    COMMS_BASE="${HOME}/comms/plans"
    if [[ -d "$COMMS_BASE" ]]; then
        # Count active and queued plans across all projects
        # Note: Don't use grep in pipeline - it fails with exit 1 when no matches, breaking pipefail
        ACTIVE_COUNT=$(find "$COMMS_BASE"/*/active -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        QUEUED_COUNT=$(find "$COMMS_BASE"/*/queued -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ' || echo "0")

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

if jq -n \
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
    }' > "$TMP_FILE" 2>/dev/null; then
    mv "$TMP_FILE" "$STATUS_FILE" 2>/dev/null || true
else
    rm -f "$TMP_FILE" 2>/dev/null || true
fi

echo '{}'
exit 0
