#!/bin/bash
# pulsar-watcher.sh - Watch for auto plans and execute them one at a time
#
# Usage: ./pulsar-watcher.sh [--once] [--interval SECONDS]
#   --once: Check once and exit (for cron jobs)
#   --interval: Poll interval in seconds (default: 300 = 5 minutes)
#
# This script:
# 1. Checks if any plan is currently active (only one at a time)
# 2. Calls Orbiter sub-agent to intelligently pick the next plan
# 3. Triggers execution via pulsar-auto.sh

# Project-relative paths (run from project root)
PLANS_DIR="./comms/plans"
AUTO_QUEUE="$PLANS_DIR/queued/auto"
ACTIVE_DIR="$PLANS_DIR/active"
LOGS_DIR="$PLANS_DIR/logs"
SCRIPTS_DIR="$HOME/.claude/plugins/marketplaces/local-plugins/scripts"
WATCHER_LOG="$LOGS_DIR/watcher.log"

# Default: 5 minutes
POLL_INTERVAL=300

# Parse arguments
RUN_ONCE=false
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

mkdir -p "$LOGS_DIR"

log() {
    echo "$(date -Iseconds) - $1" | tee -a "$WATCHER_LOG"
}

# Check if any plan is currently executing
is_plan_active() {
    # Method 1: Check active directory for any plans
    if ls "$ACTIVE_DIR"/*.md 1>/dev/null 2>&1; then
        return 0  # true, a plan is active
    fi

    # Method 2: Check for running PID files
    for pid_file in "$LOGS_DIR"/*.pid; do
        [ -f "$pid_file" ] || continue
        pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # true, a process is running
        fi
    done

    return 1  # false, no active plan
}

# Count plans in auto queue
count_queued_plans() {
    local count=0
    for f in "$AUTO_QUEUE"/*.md; do
        [ -f "$f" ] && ((count++))
    done
    echo $count
}

# Call Orbiter sub-agent to pick the next plan
call_orbiter() {
    # Use Claude with Orbiter agent to intelligently decide
    local result
    result=$(claude -p "Analyze the plan queue and pick the best plan to execute next. Return only the plan ID or 'none'." \
        --allowedTools "Read,Glob,Grep,Task" \
        --model haiku \
        --output-format text \
        --max-turns 10 \
        2>/dev/null)

    # Extract plan ID from result (look for plan-XXXXXXXX-XXXX pattern)
    local plan_id
    plan_id=$(echo "$result" | grep -oE 'plan-[0-9]{8}-[0-9]{4}' | head -1)

    if [ -n "$plan_id" ] && [ -f "$AUTO_QUEUE/$plan_id.md" ]; then
        echo "$plan_id"
    else
        echo ""
    fi
}

# Main check and execute logic
check_and_execute() {
    local queued_count
    queued_count=$(count_queued_plans)

    # No plans in queue
    if [ "$queued_count" -eq 0 ]; then
        log "No plans in auto queue"
        return
    fi

    log "Found $queued_count plan(s) in auto queue"

    # Check if a plan is already running
    if is_plan_active; then
        log "A plan is currently active, waiting..."
        return
    fi

    log "No active plan, calling Orbiter..."

    # Call Orbiter to pick the next plan
    local next_plan
    next_plan=$(call_orbiter)

    if [ -z "$next_plan" ]; then
        log "Orbiter returned no plan (dependencies blocking or none eligible)"
        return
    fi

    log "Orbiter selected: $next_plan"

    # Trigger execution
    "$SCRIPTS_DIR/pulsar-auto.sh" "$next_plan"

    log "Triggered execution for $next_plan"
}

# Main execution
if [ "$RUN_ONCE" = true ]; then
    log "Running single check..."
    check_and_execute
    log "Check complete"
else
    log "Pulsar Watcher started"
    log "Monitoring: $AUTO_QUEUE"
    log "Poll interval: ${POLL_INTERVAL}s ($(( POLL_INTERVAL / 60 )) min)"
    log "Mode: Sequential (one plan at a time)"
    log "Scheduler: Orbiter (intelligent)"
    echo "Press Ctrl+C to stop"
    echo ""

    while true; do
        check_and_execute
        sleep $POLL_INTERVAL
    done
fi
