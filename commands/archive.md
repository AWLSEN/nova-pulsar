---
name: archive
description: Archive a completed or cancelled plan.
arguments:
  - name: plan-id
    description: The plan ID to archive (e.g., plan-20260105-1530)
    required: true
---

# Archive - Plan Archive Command

Archives a plan after completion or cancellation.

## Workflow

### Step 1: Validate

Determine project name from current directory: `basename $PWD`

1. Find plan in `~/comms/plans/{project-name}/active/` or `~/comms/plans/{project-name}/review/`
2. Read board.json entry from `~/comms/plans/{project-name}/board.json`

### Step 2: Update board.json

```json
{
  "status": "archived",
  "archivedAt": "{timestamp}"
}
```

### Step 3: Move Plan

Move plan file from current location to `~/comms/plans/{project-name}/archived/`

### Step 4: Notify User

```
Plan {id} archived.
- Location: ~/comms/plans/{project-name}/archived/{id}.md
```

## Use Cases

- Plan was completed successfully
- Plan was experimental
- Requirements changed
- Want to clean up the queue
