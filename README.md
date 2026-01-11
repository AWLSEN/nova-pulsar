# Nova-Pulsar

**Plan first, then execute.** A Claude Code plugin that helps you break down complex tasks into plans and execute them with parallel agents.

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
- **Rover** - Explores your codebase (read-only) to help you understand it

## Smart Model Routing

We optimize for **cost and performance** by using the right model for each task:

| Task Complexity | Model | Why |
|-----------------|-------|-----|
| High (Architectural) | Codex | Best for analyzing existing code patterns |
| High (Implementation) | Opus | Complex features need deep reasoning |
| Medium | Opus | Standard coding tasks |
| Low | Sonnet | Fast & cheap for simple changes |

This means simple tasks use Sonnet (cheaper), complex tasks use Opus (smarter).

## Install

```
/plugin marketplace add AWLSEN/nova-pulsar
/plugin install nova-pulsar@local-plugins
```

That's it! The `./comms/` folder is created automatically when you first run `/nova`.

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
| `/rover` | Explore codebase (read-only) |
| `/archive <plan-id>` | Archive a completed plan |

## Optional: Codex for Better Research

Nova works even better with OpenAI Codex for parallel research and architectural analysis:

```bash
npm install -g @openai/codex
```

Without Codex, Nova falls back to Claude's built-in Explore agent (still works fine).

## License

MIT
