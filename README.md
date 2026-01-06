# Nova-Pulsar

Planning and execution framework for Claude Code with intelligent scheduling.

## Overview

Nova-Pulsar is a Claude Code plugin that separates planning from execution:

- **Nova** (`/nova`) - Intelligent planning agent that researches your codebase, asks clarifying questions, and creates structured execution plans
- **Pulsar** (`/pulsar`) - Execution agent that implements plans with maximum parallelization
- **Orbiter** - Background scheduler that intelligently picks which plan to execute next
- **Archive** (`/archive`) - Archives completed or cancelled plans

## Installation

### Step 1: Install the Plugin

In Claude Code, run:

```
/plugin install AWLSEN/nova-pulsar
```

### Step 2: Run Setup Script

After installing the plugin, run the setup script to create the required folder structure:

```bash
# Basic setup (folders only)
~/.claude/plugins/AWLSEN/nova-pulsar/scripts/setup.sh

# With auto-execution systemd service
~/.claude/plugins/AWLSEN/nova-pulsar/scripts/setup.sh --with-systemd
```

### Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Create folder structure
mkdir -p ~/comms/plans/{queued/auto,queued/manual,active,review,archived,logs}

# Initialize board.json
echo '[]' > ~/comms/plans/board.json
```

## Commands

### `/nova` - Create a Plan

Nova is a planning-only agent that:
- Uses inner monologue to predict what research is needed
- Launches dynamic number of explore agents (not hardcoded)
- Iterates research until ready to plan
- Asks clarifying questions using AskUserQuestion
- Creates structured plans with parallelization analysis

### `/pulsar [plan-id]` - Execute a Plan

Pulsar executes plans with:
- Intelligent parallelization (analyzes dependencies, maximizes parallel execution)
- Quality gates after each round (Dead Code Agent + Test Agent in parallel)
- TDD approach (write tests if none exist)
- Autonomous execution (no user interaction mid-execution)

### `/archive <plan-id>` - Archive Plan

Archives a completed or cancelled plan.

## Folder Structure

Plans are stored in `~/comms/plans/`:

```
~/comms/plans/
├── board.json          # Central tracking
├── queued/
│   ├── auto/           # Auto-execute plans
│   └── manual/         # Manual trigger plans
├── active/             # Currently executing
├── review/             # Completed, awaiting review
├── archived/           # Done or discarded
└── logs/               # Execution logs
```

## Execution Flow

```
/nova
  ↓
Inner Monologue → Predict questions
  ↓
Launch Explore Agents (dynamic, parallel)
  ↓
Review Reports → Need more? Loop back
  ↓
Ask User Questions
  ↓
Create Plan with Parallelization Analysis
  ↓
Save to queued/auto or queued/manual

/pulsar
  ↓
Load Plan → Analyze for parallelism
  ↓
Round 1: Phase 1 + Phase 2 (parallel)
  ↓
Quality Gate: Dead Code + Test Agent (parallel)
  ↓
Round 2: Phase 3
  ↓
Quality Gate: Dead Code + Test Agent (parallel)
  ↓
Finalize → Move to review

/archive plan-id
  ↓
Move plan to archived/
```

## Auto-Execution (Optional)

For background execution of plans in `queued/auto/`, use the watcher daemon.

### Using systemd (Recommended)

If you ran setup with `--with-systemd`:

```bash
# Start the watcher
systemctl --user start pulsar-watcher

# Check status
systemctl --user status pulsar-watcher

# View logs
journalctl --user -u pulsar-watcher -f

# Stop the watcher
systemctl --user stop pulsar-watcher
```

### Manual systemd Setup

Create `~/.config/systemd/user/pulsar-watcher.service`:

```ini
[Unit]
Description=Pulsar Plan Watcher - Auto-executes queued plans
After=default.target

[Service]
Type=simple
ExecStart=%h/.claude/plugins/AWLSEN/nova-pulsar/scripts/pulsar-watcher.sh
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
```

Then enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now pulsar-watcher
```

### Running Manually

```bash
# Run in background
~/.claude/plugins/AWLSEN/nova-pulsar/scripts/pulsar-watcher.sh &

# Run once (for cron jobs)
~/.claude/plugins/AWLSEN/nova-pulsar/scripts/pulsar-watcher.sh --once

# Custom interval (in seconds, default is 300 = 5 min)
~/.claude/plugins/AWLSEN/nova-pulsar/scripts/pulsar-watcher.sh --interval 60
```

## Quick Start

1. Install: `/plugin install AWLSEN/nova-pulsar`
2. Setup: `~/.claude/plugins/AWLSEN/nova-pulsar/scripts/setup.sh`
3. Plan: `/nova`
4. Execute: `/pulsar`

## License

MIT
