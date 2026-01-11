# Nova-Pulsar

**Plan first, then execute.** A Claude Code plugin that helps you break down complex tasks into plans and execute them with parallel agents.

## What It Does

```
You: "Add user authentication to my app"
         ↓
    /nova (plans it)
         ↓
    /pulsar (builds it)
         ↓
    Done!
```

- **Nova** - Researches your codebase, asks questions, creates a step-by-step plan
- **Pulsar** - Executes the plan using multiple agents in parallel
- **Rover** - Explores your codebase (read-only) to help you understand it

## Quick Start

### 1. Install

```bash
# In Claude Code, run:
/plugin marketplace add AWLSEN/nova-pulsar
/plugin install nova-pulsar@local-plugins
```

### 2. Setup Your Project

Run this in your project folder:

```bash
mkdir -p ./comms/plans/{queued/auto,queued/manual,active,review,archived,logs} ./comms/status
echo '[]' > ./comms/plans/board.json
```

### 3. Use It

```
/nova          # Create a plan (Nova asks questions, you approve)
/pulsar        # Execute the plan (runs automatically)
/archive ID    # Archive when done
```

That's it!

## How It Works

### Step 1: Plan with Nova

```
You: /nova I want to add a login page

Nova:
  → Researches your codebase
  → Asks clarifying questions
  → Creates a plan with phases
  → You approve → Plan saved
```

### Step 2: Execute with Pulsar

```
You: /pulsar

Pulsar:
  → Reads the plan
  → Runs phases in parallel (when possible)
  → Writes tests
  → Cleans up dead code
  → Done!
```

## Commands

| Command | What it does |
|---------|--------------|
| `/nova` | Create a new plan |
| `/pulsar` | Execute a plan |
| `/pulsar plan-ID` | Execute a specific plan |
| `/rover` | Explore codebase (read-only) |
| `/archive plan-ID` | Archive a completed plan |

## Where Plans Live

Plans are stored in your project's `./comms/` folder:

```
./comms/
├── plans/
│   ├── queued/auto/    ← Plans waiting to run
│   ├── queued/manual/  ← Plans you trigger manually
│   ├── active/         ← Currently running
│   ├── review/         ← Done, needs your review
│   └── archived/       ← Finished
└── status/             ← Progress tracking
```

## Optional: Codex for Better Research

Nova works best with OpenAI Codex for parallel research:

```bash
npm install -g @openai/codex
```

Without Codex, Nova falls back to Claude's built-in Explore agent (still works, just slower).

## License

MIT
