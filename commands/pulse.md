---
name: pulse
description: View live status overview of all active Pulsar executions across projects.
arguments: []
---

# Pulse - Live Execution Status Overview

Shows a quick overview of all active plan executions across all projects.

## Workflow

### Step 1: Scan for Active Plans

```bash
# Find all active plan directories
find ~/comms/plans/*/active -maxdepth 1 -type d 2>/dev/null
```

### Step 2: Check for pulse.json Files

For each project with active plans, check for `~/comms/plans/{project}/pulse.json`

If pulse.json exists and is recent (< 60 seconds old), display it.
Otherwise, build status from individual status files.

### Step 3: Build Status Overview

For each active plan:
1. Read all `status/*.status` files
2. Aggregate phase statuses
3. Calculate progress

### Step 4: Display Overview

**Output format:**

```
╭─────────────────────────────────────────────────────────────╮
│                     PULSAR PULSE                            │
├─────────────────────────────────────────────────────────────┤
│ Active Plans: 1    Queued: 2    Last Update: 15s ago        │
╰─────────────────────────────────────────────────────────────╯

starry-night/plan-20260117-1500
├── Phase 1: ✓ completed (45 tools, 2m 30s)
├── Phase 2: ⟳ running   (23 tools, last: Edit src/auth.ts)
└── Phase 3: ○ pending

my-app/plan-20260117-1430
├── Phase 1: ✓ completed
├── Phase 2: ✓ completed
└── Phase 3: ⚠ stalled   (no update for 12m)
```

**Status icons:**
- `✓` completed
- `⟳` running
- `○` pending
- `⚠` stalled (> 10 min no update)
- `✗` failed

### Step 5: Handle Empty State

If no active plans:

```
╭─────────────────────────────────────────────────────────────╮
│                     PULSAR PULSE                            │
├─────────────────────────────────────────────────────────────┤
│ No active executions                                        │
│                                                             │
│ Queued plans: 3                                             │
│ Run /pulsar to start execution                              │
╰─────────────────────────────────────────────────────────────╯
```

## Implementation

```bash
COMMS_BASE="$HOME/comms/plans"
PROJECT_NAME=$(basename "$PWD")

# Check for project-specific pulse.json first
PULSE_FILE="$COMMS_BASE/$PROJECT_NAME/pulse.json"
if [[ -f "$PULSE_FILE" ]]; then
    # Check if recent (< 60 seconds)
    PULSE_AGE=$(($(date +%s) - $(stat -f %m "$PULSE_FILE" 2>/dev/null || stat -c %Y "$PULSE_FILE" 2>/dev/null)))
    if [[ $PULSE_AGE -lt 60 ]]; then
        cat "$PULSE_FILE" | jq '.'
        exit 0
    fi
fi

# Build from status files
for plan_dir in "$COMMS_BASE"/*/active/*/; do
    if [[ -d "$plan_dir/status" ]]; then
        echo "Plan: $(basename "$plan_dir")"
        for status_file in "$plan_dir"/status/*.status; do
            if [[ -f "$status_file" ]]; then
                cat "$status_file" | jq -c '{phase: .task_id, status: .status, tools: .tool_count, last: .last_tool}'
            fi
        done
    fi
done
```

## Notes

- This command is read-only, it doesn't modify any state
- For detailed status of a specific plan, use `/pulsar-status {plan-id}`
- Pulse data is aggregated by Orbiter watcher when running
