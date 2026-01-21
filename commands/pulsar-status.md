---
name: pulsar-status
description: View detailed execution status for a specific plan or the current active plan.
arguments:
  - name: plan-id
    description: The plan ID to check (e.g., plan-20260105-1530). If omitted, shows current active plan.
    required: false
---

# Pulsar Status - Detailed Plan Execution Status

Shows detailed execution status for a specific plan, including per-phase progress, timing, and any issues.

## Workflow

### Step 1: Find the Plan

Determine project name from current directory: `basename $PWD`

**If plan-id provided:**
- Look in `~/comms/plans/{project-name}/active/{plan-id}/`

**If no plan-id:**
- Find the currently active plan in `~/comms/plans/{project-name}/active/`
- If multiple active plans, list them and ask which one
- If no active plans, check queued plans

### Step 2: Read Status Files

For the target plan, read all files in:
- `~/comms/plans/{project-name}/active/{plan-id}/status/*.status`
- `~/comms/plans/{project-name}/active/{plan-id}/markers/*` (for PID info)

### Step 3: Read Plan File

Read the plan markdown to get phase descriptions:
- `~/comms/plans/{project-name}/active/{plan-id}.md` or
- `~/comms/plans/{project-name}/active/{plan-id}/{plan-id}.md`

### Step 4: Display Detailed Status

**Output format:**

```
╭─────────────────────────────────────────────────────────────╮
│  PULSAR STATUS: plan-20260117-1500                          │
│  Project: starry-night                                      │
│  Started: 2026-01-17 15:00:00 (25 minutes ago)              │
╰─────────────────────────────────────────────────────────────╯

EXECUTION PROGRESS
══════════════════════════════════════════════════════════════

Phase 1: Refactor Authentication Module
─────────────────────────────────────────
  Status:     ✓ COMPLETED
  Agent:      Opus 4.5
  Duration:   8m 45s
  Tools used: 67
  Commit:     abc1234 "feat: refactor auth module"

Phase 2: Add OAuth Integration
─────────────────────────────────────────
  Status:     ⟳ RUNNING
  Agent:      Opus 4.5
  Runtime:    12m 30s
  Tools used: 45
  Last tool:  Edit
  Last file:  src/auth/oauth.ts
  Updated:    15 seconds ago
  PID:        54321

Phase 3: Update API Endpoints
─────────────────────────────────────────
  Status:     ○ PENDING
  Agent:      Sonnet 4.5 (planned)
  Blocked by: Phase 2

══════════════════════════════════════════════════════════════

SUMMARY
  Total Phases: 3
  Completed:    1 (33%)
  Running:      1
  Pending:      1

  Estimated remaining: ~15 minutes (based on Phase 1 timing)
```

### Step 5: Handle Different States

**Plan not found:**
```
Plan {plan-id} not found in active plans.

Check:
  - ~/comms/plans/{project}/queued/     (queued plans)
  - ~/comms/plans/{project}/completed/  (completed plans)
```

**Plan completed:**
```
╭─────────────────────────────────────────────────────────────╮
│  PULSAR STATUS: plan-20260117-1500                          │
│  Status: COMPLETED                                          │
│  Duration: 45 minutes                                       │
╰─────────────────────────────────────────────────────────────╯

All 3 phases completed successfully.
Location: ~/comms/plans/{project}/completed/plan-20260117-1500.md
```

**Stalled phase detected:**
```
Phase 2: Add OAuth Integration
─────────────────────────────────────────
  Status:     ⚠ STALLED
  Agent:      Opus 4.5
  Runtime:    25m 00s (no update for 12 minutes)
  Tools used: 45
  Last tool:  Bash
  Last file:  (npm test)
  PID:        54321

  ⚠ WARNING: This phase appears stalled.
  The Orbiter watcher will kill it after 10 minutes of inactivity.
  Pulsar will then retry automatically (max 2 retries).
```

## Implementation

```bash
COMMS_BASE="$HOME/comms/plans"
PROJECT_NAME=$(basename "$PWD")
PLAN_ID="${1:-}"

# Find plan
if [[ -z "$PLAN_ID" ]]; then
    # Find active plan
    ACTIVE_PLANS=$(ls "$COMMS_BASE/$PROJECT_NAME/active/" 2>/dev/null | grep -v '^\.' | head -5)
    PLAN_COUNT=$(echo "$ACTIVE_PLANS" | grep -c . || echo 0)

    if [[ $PLAN_COUNT -eq 0 ]]; then
        echo "No active plans found for $PROJECT_NAME"
        exit 1
    elif [[ $PLAN_COUNT -eq 1 ]]; then
        PLAN_ID="$ACTIVE_PLANS"
    else
        echo "Multiple active plans found. Specify one:"
        echo "$ACTIVE_PLANS"
        exit 1
    fi
fi

STATUS_DIR="$COMMS_BASE/$PROJECT_NAME/active/$PLAN_ID/status"
MARKERS_DIR="$COMMS_BASE/$PROJECT_NAME/active/$PLAN_ID/markers"

# Read and display status for each phase
for status_file in "$STATUS_DIR"/*.status; do
    if [[ -f "$status_file" ]]; then
        echo "---"
        cat "$status_file" | jq '.'
    fi
done
```

## Related Commands

- `/pulse` - Quick overview of all active executions
- `/pulsar` - Start plan execution
- `/nova` - Create a new plan
