#!/bin/bash
# starry-daemon.sh - Background daemon for Starry Night plugin
#
# Watches all project namespaces for background plans and executes them.
#
# Usage: ./starry-daemon.sh [--once] [--interval SECONDS]
#   --once: Check once and exit (for cron jobs)
#   --interval: Poll interval in seconds (default: 300 = 5 minutes)
#
# Directory structure (namespaced by project):
#   ~/comms/plans/
#   ├── {project-name}/
#   │   ├── queued/background/
#   │   ├── queued/interactive/
#   │   ├── active/
#   │   ├── review/
#   │   ├── archived/
#   │   └── logs/
#   └── daemon.log

set -euo pipefail

COMMS_BASE="$HOME/comms/plans"
DAEMON_LOG="$COMMS_BASE/daemon.log"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default: 5 minutes
POLL_INTERVAL=300
RUN_ONCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --once)
            RUN_ONCE=true
            shift
            ;;
        --interval)
            POLL_INTERVAL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

mkdir -p "$COMMS_BASE"

log() {
    echo "$(date -Iseconds) - $1" | tee -a "$DAEMON_LOG"
}

# Get list of all project namespaces
get_projects() {
    local projects=()
    for dir in "$COMMS_BASE"/*/; do
        [ -d "$dir" ] || continue
        local project_name=$(basename "$dir")
        # Skip if not a valid project namespace (has queued directory)
        [ -d "$dir/queued/background" ] && projects+=("$project_name")
    done
    echo "${projects[@]}"
}

# Check if any plan is currently executing across all projects
is_any_plan_active() {
    for project in $(get_projects); do
        local active_dir="$COMMS_BASE/$project/active"
        local logs_dir="$COMMS_BASE/$project/logs"

        # Check for active plan files
        if ls "$active_dir"/*.md 1>/dev/null 2>&1; then
            return 0
        fi

        # Check for running PID files
        if [ -d "$logs_dir" ]; then
            for pid_file in "$logs_dir"/*.pid; do
                [ -f "$pid_file" ] || continue
                local pid=$(cat "$pid_file")
                if ps -p "$pid" > /dev/null 2>&1; then
                    return 0
                fi
            done
        fi
    done
    return 1
}

# Find all queued background plans across all projects
# Returns: "project_name:plan_id" for each plan
find_all_queued_plans() {
    local plans=()
    for project in $(get_projects); do
        local queue_dir="$COMMS_BASE/$project/queued/background"
        for plan_file in "$queue_dir"/*.md; do
            [ -f "$plan_file" ] || continue
            local plan_id=$(basename "$plan_file" .md)
            plans+=("$project:$plan_id")
        done
    done
    echo "${plans[@]}"
}

# Count total queued plans
count_queued_plans() {
    local count=0
    for project in $(get_projects); do
        local queue_dir="$COMMS_BASE/$project/queued/background"
        for f in "$queue_dir"/*.md; do
            [ -f "$f" ] && ((count++))
        done
    done
    echo $count
}

# Call Orbiter to pick the best plan from all projects
# Orbiter receives the full context of all queued plans
call_orbiter() {
    local plans_list=$(find_all_queued_plans)

    if [ -z "$plans_list" ]; then
        echo ""
        return
    fi

    # Build context for Orbiter
    local context="Available plans in background queue:\n"
    for plan_ref in $plans_list; do
        local project=$(echo "$plan_ref" | cut -d: -f1)
        local plan_id=$(echo "$plan_ref" | cut -d: -f2)
        context+="- Project: $project, Plan: $plan_id\n"
    done

    local result
    result=$(claude -p "You are Orbiter. Analyze these queued plans and pick the best one to execute next.

$context

Consider:
1. Plan dependencies (some plans may depend on others)
2. Project priority (if any indicators in plan metadata)
3. Creation time (older plans may need attention)

Return ONLY the response in format: project_name:plan_id
Or return 'none' if no plan should be executed now." \
        --allowedTools "Read,Glob,Grep" \
        --model haiku \
        --output-format text \
        --max-turns 5 \
        2>/dev/null) || true

    # Extract project:plan_id from result
    local selected=$(echo "$result" | grep -oE '[a-zA-Z0-9_-]+:plan-[0-9]{8}-[0-9]{4}' | head -1)

    if [ -n "$selected" ]; then
        local project=$(echo "$selected" | cut -d: -f1)
        local plan_id=$(echo "$selected" | cut -d: -f2)
        local plan_file="$COMMS_BASE/$project/queued/background/$plan_id.md"

        if [ -f "$plan_file" ]; then
            echo "$selected"
            return
        fi
    fi

    echo ""
}

# Main check and execute logic
check_and_execute() {
    local queued_count
    queued_count=$(count_queued_plans)

    if [ "$queued_count" -eq 0 ]; then
        log "No plans in any background queue"
        return
    fi

    log "Found $queued_count plan(s) across all projects"

    if is_any_plan_active; then
        log "A plan is currently active, waiting..."
        return
    fi

    log "No active plan, calling Orbiter..."

    local selected
    selected=$(call_orbiter)

    if [ -z "$selected" ]; then
        log "Orbiter returned no plan (dependencies blocking or none eligible)"
        return
    fi

    local project=$(echo "$selected" | cut -d: -f1)
    local plan_id=$(echo "$selected" | cut -d: -f2)

    log "Orbiter selected: $plan_id from project $project"

    # Trigger execution with project context
    "$SCRIPTS_DIR/pulsar-auto.sh" "$project" "$plan_id"

    log "Triggered execution for $plan_id in $project"
}

# Main execution
if [ "$RUN_ONCE" = true ]; then
    log "Running single check..."
    check_and_execute
    log "Check complete"
else
    log "Starry Night Daemon started"
    log "Monitoring: $COMMS_BASE/*/queued/background/"
    log "Poll interval: ${POLL_INTERVAL}s ($(( POLL_INTERVAL / 60 )) min)"
    log "Mode: Sequential (one plan at a time across all projects)"
    log "Scheduler: Orbiter (intelligent cross-project)"
    echo "Press Ctrl+C to stop"
    echo ""

    while true; do
        check_and_execute
        sleep $POLL_INTERVAL
    done
fi
