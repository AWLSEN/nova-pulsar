# Starry Night

**Plan first, then execute.** A Claude Code plugin that helps you break down complex tasks into plans and execute them with parallel agents.

## Install

**Step 1:** Add the marketplace
```bash
/plugin marketplace add AWLSEN/starry-night
```

**Step 2:** Install the plugin
```bash
/plugin install starry-night@awlsen-plugins
```
When prompted, select **"Install for you (user scope)"** for personal use.

Restart Claude Code after installing.

## Directory Structure

Plans are stored globally but namespaced by project:

```
~/comms/plans/
├── {project-name}/           # One folder per project
│   ├── queued/
│   │   ├── background/       # Plans for daemon execution
│   │   └── interactive/      # Plans for /pulsar execution
│   ├── active/               # Currently executing plans
│   ├── review/               # Completed, pending review
│   ├── archived/             # Archived plans
│   ├── logs/                 # Execution logs
│   └── config.json           # Project config
└── daemon.log                # Global daemon log
```

## What It Does

```
You: /nova Add user authentication to my app
              ↓
         Nova plans it (asks questions, you approve)
              ↓
You: /pulsar
              ↓
         Pulsar builds it (runs in parallel)
              ↓
         Done!
```

- **Nova** - Researches your codebase, asks questions, creates a step-by-step plan
- **Pulsar** - Executes the plan using multiple agents in parallel

## Smart Model Routing

We optimize for **cost and performance** by using the right model for each task:

| Task Complexity | Model | Why |
|-----------------|-------|-----|
| High (Architectural) | Codex | Best for analyzing existing code patterns |
| High (Implementation) | Opus | Complex features need deep reasoning |
| Medium | Opus | Standard coding tasks |
| Low | Sonnet | Fast & cheap for simple changes |

Simple tasks use Sonnet (cheaper), complex tasks use Opus (smarter).

## Parallel Execution (Rounds)

Pulsar runs phases **in parallel** when they don't depend on each other:

```
Plan: Add auth system
├── Phase 1: Create User model
├── Phase 2: Create Auth service
├── Phase 3: Create API endpoints (needs 1 & 2)
└── Phase 4: Add tests

Pulsar figures out:
  Round 1: Phase 1 + Phase 2 + Phase 4  ← run together (independent)
  Round 2: Phase 3                       ← waits for Round 1
```

Phases that touch **different files** run at the same time. Phases that **depend on others** wait.

## How to Use

### 1. Plan with Nova

Type `/nova` followed by what you want to build:

```
/nova Add a dark mode toggle to the settings page
```

Nova will:
- Research your codebase
- Ask clarifying questions
- Show you a plan
- Save it when you approve

### 2. Execute with Pulsar

```
/pulsar
```

Pulsar will:
- Read the plan
- Run phases in parallel (when possible)
- Write tests automatically
- Clean up dead code
- Notify you when done

### Understanding Plan IDs

Each plan gets an ID like `plan-20260113-1430`. You'll see it when Nova saves your plan.

- **Just run `/pulsar`** - Picks the most recent queued plan automatically
- **Run `/pulsar plan-20260113-1430`** - Execute a specific plan

To see your queued plans: `ls ~/comms/plans/{project-name}/queued/interactive/`

### Execution Modes

Nova will ask about execution mode:

- **Interactive** (recommended): You run `/pulsar` when you're ready to execute
- **Background**: The starry-daemon watches the background queue and executes plans automatically - perfect for "fire and forget" workflows

### 3. Archive when finished

```
/archive plan-20260111-1530
```

## Commands

| Command | What it does |
|---------|--------------|
| `/nova <description>` | Create a plan for your task |
| `/pulsar` | Execute the latest plan |
| `/pulsar <plan-id>` | Execute a specific plan |
| `/archive <plan-id>` | Archive a completed plan |

## Background Daemon (Optional)

For automated background execution (works on macOS and Linux):

```bash
# Start the daemon
./scripts/setup.sh --daemon start

# Stop the daemon
./scripts/setup.sh --daemon stop

# Check status
./scripts/setup.sh --daemon status

# Restart
./scripts/setup.sh --daemon restart
```

The daemon monitors all project namespaces and executes background plans automatically.

Logs are stored at `~/comms/plans/daemon.log`.

## Folder Rename Detection

If you rename your project folder, Starry Night automatically detects this and updates the namespace to match. No manual intervention needed.

## Enhanced Research with Codex (Optional)

Nova automatically detects if Codex is available. If installed, it uses Codex for faster parallel codebase research. If not, it seamlessly falls back to Claude's native Explore agents.

**You don't need Codex** - Nova works great without it. But if you want faster research on large codebases:

```bash
npm install -g @openai/codex
```

The orchestrator is smart enough to use whatever's available.

## Questions or Feedback?

Reach out to us on Twitter:
- [@OAFTOBARKK](https://twitter.com/OAFTOBARKK)
- [@artmarryscience](https://twitter.com/artmarryscience)

Or open an issue in the repository.

## License

MIT
