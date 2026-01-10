#!/bin/bash
# Neutron Status Update Hook
# Updates ~/comms/status/{TASK_ID}.status after each tool use
#
# This hook is triggered by PostToolUse events. It reads the tool
# information from stdin and updates the status file atomically.
#
# Also handles Stop hook (NEUTRON_HOOK_EVENT=stop) to mark completion.
#
# Environment:
#   NEUTRON_TASK_ID - Task identifier (e.g., "phase-1-plan-20260110-1430")
#                     If not set, hook exits silently (not a tracked task)
#   NEUTRON_HOOK_EVENT - Set to "stop" when called from Stop hook

set -euo pipefail

# Exit silently if not a tracked task
if [[ -z "${NEUTRON_TASK_ID:-}" ]]; then
    exit 0
fi

# Status file location
STATUS_DIR="${HOME}/comms/status"
STATUS_FILE="${STATUS_DIR}/${NEUTRON_TASK_ID}.status"
TMP_FILE="${STATUS_FILE}.tmp"

# Ensure status directory exists
mkdir -p "$STATUS_DIR"

# Handle Stop hook - mark as completed and exit
if [[ "${NEUTRON_HOOK_EVENT:-}" == "stop" ]]; then
    if [[ -f "$STATUS_FILE" ]]; then
        completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq --arg completed_at "$completed_at" \
           '.status = "completed" | .completed_at = $completed_at' \
           "$STATUS_FILE" > "$TMP_FILE"
        mv "$TMP_FILE" "$STATUS_FILE"
    fi
    exit 0
fi

# Read input from stdin
input=$(cat)

# Extract tool information using jq
tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"')
tool_input=$(echo "$input" | jq -c '.tool_input // {}')

# Extract file path if present (varies by tool)
last_file=$(echo "$tool_input" | jq -r '
    .file_path //
    .path //
    .notebook_path //
    (if .command then
        (.command | capture("(?<f>/[^\\s]+\\.[a-z]+)") | .f) // null
    else null end) //
    null
')

# Get current timestamp
updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read existing status file or create default
if [[ -f "$STATUS_FILE" ]]; then
    existing=$(cat "$STATUS_FILE")
    tool_count=$(echo "$existing" | jq -r '.tool_count // 0')
    started_at=$(echo "$existing" | jq -r '.started_at')
    plan_id=$(echo "$existing" | jq -r '.plan_id')
    phase=$(echo "$existing" | jq -r '.phase')
else
    # First tool call - extract from task ID
    # Format: phase-{N}-{plan-id}
    tool_count=0
    started_at="$updated_at"

    # Parse task ID: phase-1-plan-20260110-1430
    if [[ "$NEUTRON_TASK_ID" =~ ^phase-([0-9]+)-(.+)$ ]]; then
        phase="${BASH_REMATCH[1]}"
        plan_id="${BASH_REMATCH[2]}"
    else
        phase=0
        plan_id="unknown"
    fi
fi

# Increment tool count
tool_count=$((tool_count + 1))

# Build updated status JSON
jq -n \
    --arg task_id "$NEUTRON_TASK_ID" \
    --arg plan_id "$plan_id" \
    --argjson phase "$phase" \
    --arg started_at "$started_at" \
    --arg updated_at "$updated_at" \
    --arg last_tool "$tool_name" \
    --arg last_file "$last_file" \
    --argjson tool_count "$tool_count" \
    --arg status "running" \
    '{
        task_id: $task_id,
        plan_id: $plan_id,
        phase: $phase,
        started_at: $started_at,
        updated_at: $updated_at,
        last_tool: $last_tool,
        last_file: (if $last_file == "null" or $last_file == "" then null else $last_file end),
        tool_count: $tool_count,
        status: $status
    }' > "$TMP_FILE"

# Atomic write
mv "$TMP_FILE" "$STATUS_FILE"

# Exit success (don't interfere with tool execution)
exit 0
