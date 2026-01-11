# Nova-Pulsar

Planning and execution framework for Claude Code with multi-model routing.

## Overview

Nova-Pulsar is a Claude Code plugin that separates planning from execution with intelligent model selection:

- **Nova** (`/nova`) - Planning agent that uses Codex for parallel research, asks clarifying questions, and creates structured execution plans
- **Pulsar** (`/pulsar`) - Execution agent that routes phases to the right model (Codex/Opus/Sonnet) based on complexity
- **Orbiter** - Background scheduler that intelligently picks which plan to execute next
- **Archive** (`/archive`) - Archives completed or cancelled plans

## Multi-Model Architecture

Nova-Pulsar uses different models for different tasks:

| Task | Model | Why |
|------|-------|-----|
| Research (Nova) | Codex | Parallel codebase analysis |
| High (Architectural) | Codex | Surgical architecture changes |
| High (Implementation) | Opus | Complex features |
| Medium | Opus | Standard features |
| Low | Sonnet | Simple, precise steps |

This multi-model approach optimizes for quality based on task complexity.

## Prerequisites

### Required

1. **Claude Code** - Install from https://claude.ai/code
2. **OpenAI Codex CLI** - Required for Nova's research and architectural phases
   ```bash
   npm install -g @openai/codex
   ```

## Installation

### Step 1: Add the Marketplace

In Claude Code, run:

```
/plugin marketplace add AWLSEN/nova-pulsar
```

### Step 2: Install the Plugin

```
/plugin install nova-pulsar@awlsen-plugins
```

### Step 3: Create Folder Structure (Per Project)

In each project where you want to use Nova-Pulsar:

```bash
# Create folder structure (run in your project root)
mkdir -p ./comms/plans/{queued/auto,queued/manual,active,review,archived,logs}
mkdir -p ./comms/status

# Initialize board.json
echo '[]' > ./comms/plans/board.json
```

Or run the setup script if available:

```bash
~/.claude/plugins/cache/*/nova-pulsar/*/scripts/setup.sh
```

## Commands

### `/nova` - Create a Plan

Nova is a planning-only agent that:
- Uses Codex for parallel research (multiple Bash commands with `run_in_background: true`)
- Iterates research until ready to plan
- Asks clarifying questions using AskUserQuestion
- Creates structured plans with complexity ratings and parallelization analysis

**How Nova Works:**
```
Nova (orchestrator)
├── Bash #1: codex exec "find auth files"    → background
├── Bash #2: codex exec "analyze patterns"   → background
├── Bash #3: codex exec "find tests"         → background
└── TaskOutput to retrieve all results
```

### `/pulsar [plan-id]` - Execute a Plan

Pulsar executes plans with:
- Multi-model routing based on phase complexity
- Intelligent parallelization (analyzes dependencies, maximizes parallel execution)
- Quality gates after each round (Dead Code Agent + Test Agent in parallel)
- TDD approach (write tests if none exist)
- Autonomous execution (no user interaction mid-execution)

**How Pulsar Works:**
```
Pulsar (orchestrator)
├── Bash #1: codex exec "Phase 1 - architectural" → background
├── Bash #2: claude "Phase 2 - medium"            → background
├── Bash #3: claude --model sonnet "Phase 3"      → background
└── TaskOutput to retrieve all results
```

**Model Selection:**
| Complexity | CLI Command |
|------------|-------------|
| High (Architectural) | `codex exec --dangerously-bypass-approvals-and-sandbox` |
| High (Implementation) | `claude --dangerously-skip-permissions` |
| Medium | `claude --dangerously-skip-permissions` |
| Low | `claude --model sonnet --dangerously-skip-permissions` |

### `/archive <plan-id>` - Archive Plan

Archives a completed or cancelled plan.

## Folder Structure

Plans are stored in `./comms/plans/` (project-relative):

```
./comms/plans/
├── board.json          # Central tracking
├── queued/
│   ├── auto/           # Auto-execute plans
│   └── manual/         # Manual trigger plans
├── active/             # Currently executing
├── review/             # Completed, awaiting review
├── archived/           # Done or discarded
└── logs/               # Execution logs
```

**Note:** Each project has its own `./comms/` directory. Plans are project-specific and can be committed to git.

## Execution Flow

```
/nova
  ↓
Inner Monologue → Predict questions
  ↓
Launch Codex Agents (parallel via Bash + run_in_background)
  ↓
Review Reports → Need more? Loop back
  ↓
Ask User Questions
  ↓
Create Plan with Complexity Ratings
  ↓
Save to queued/auto or queued/manual

/pulsar
  ↓
Load Plan → Analyze complexity per phase
  ↓
Round 1: Phase 1 (Codex) + Phase 2 (Opus) [parallel via Bash]
  ↓
Quality Gate: Dead Code + Test Agent (parallel)
  ↓
Round 2: Phase 3 (Sonnet)
  ↓
Quality Gate: Dead Code + Test Agent (parallel)
  ↓
Finalize → Move to review

/archive plan-id
  ↓
Move plan to archived/
```

## Quick Start

1. Install Codex: `npm install -g @openai/codex`
2. Add marketplace: `/plugin marketplace add AWLSEN/nova-pulsar`
3. Install plugin: `/plugin install nova-pulsar@awlsen-plugins`
4. Create folders: `mkdir -p ./comms/plans/{queued/auto,queued/manual,active,review,archived,logs} ./comms/status`
5. Create a plan: `/nova`
6. Execute: `/pulsar`

## License

MIT
