<p align="center">
  <img src="https://raw.githubusercontent.com/ForeroAlexander/usetasuki/master/assets/tasuki-hero2.png" alt="Tasuki">
</p>

<p align="center">
  <b>Memory, discipline, and a process your AI can't skip.</b><br>
  <i>Built for Claude Code. Compatible with Cursor, Codex, Copilot, Windsurf, Continue, Roo Code, and Gemini.</i><br><br>
  <sub>Tasuki (襷) — the sash used in Japan to tie back sleeves before working.<br>It prepares your AI assistant with structure, workflow, and memory so it can work properly.</sub>
</p>

## Install

```bash
npm install -g tasuki
```

Or manually:

```bash
git clone https://github.com/ForeroAlexander/Tasuki.git
cd Tasuki && bash install.sh
```

**Requirements:** bash, git, curl, awk. Optional: python3, node/npx, jq.

## The Problem

Without Tasuki, your AI assistant:
- **Invents file paths** that don't exist in your project
- **Skips tests** and goes straight to implementation
- **Ignores security** — introduces SQL injection, hardcoded secrets
- **Repeats mistakes** — task #89 has the same bug as task #45
- **Has no process** — you say "write tests first" and it ignores you

With Tasuki, **hooks mechanically block those behaviors.** No tests? Edit blocked. No plan? Implementation blocked. No agent context loaded? Code changes blocked. It's not a suggestion — it's enforcement.

## Quick Start

```bash
cd your-project
tasuki                    # scans stack, generates agents, ready
```

Close and reopen your AI tool so it loads the new hooks. Then:

```bash
# In your AI tool chat, prefix with "tasuki" to activate the pipeline:
"tasuki: add user authentication with JWT"
```

> **Important:** The pipeline activates when you say **"tasuki"** in your prompt. Without it, your AI works normally. With it, the full pipeline runs — plan first, tests first, security audit, code review. You control when to use it.

The pipeline runs automatically — 9 agents, sequential:

**Planner** → **QA** (TDD) → **DB Architect** → **Backend Dev** → test checkpoint → **Frontend Dev** → **Security** (OWASP) → **Reviewer** (quality gate) → **DevOps** → done.

## Agents

| Agent | Role | Stage |
|-------|------|-------|
| **Planner** | Architecture, PRDs, task decomposition | 1 |
| **QA** | TDD enforcement, test suites | 2 |
| **DB Architect** | Schema design, migrations | 3 |
| **Backend Dev** | APIs, services, business logic | 4 |
| **Frontend Dev** | UI with design preview | 5 |
| **Debugger** | Root cause analysis (reactive) | 5.5 |
| **Security** | OWASP audit, variant analysis | 6 |
| **Reviewer** | Quality gate, 3-round fix loop | 7 |
| **DevOps** | Docker, CI/CD, deploys | 8 |

Each agent is a 250+ line specialist. Thinking agents (planner, security, reviewer) use the strongest model. Execution agents use fast models. ~60% token savings.

## Memory

Two-layer system — not a traditional RAG:

- **Layer 1 — Wikilinks**: each agent reads only its memories via `[[links]]`. Zero cost, offline, human-readable.
- **Layer 2 — Deep Memory**: vector search over schema, APIs, plans, git history. On-demand via MCP. Local SQLite, $0.

Scales from wikilinks-only to pgvector without changing agent logic.

```bash
tasuki vault sync          # index project into deep memory
tasuki vault query "auth"  # semantic search across everything
```

## Commands

```bash
tasuki                     # onboard or show status
tasuki dashboard           # interactive dashboard (localhost:8686)
tasuki score "task"        # complexity analysis (1-10)
tasuki doctor              # diagnose + auto-fix
tasuki vault stats         # knowledge graph metrics
```

<details>
<summary><b>All commands</b></summary>

```bash
# Setup
tasuki init <stack> <name>           tasuki onboard [path] [--target=X]
tasuki adapt <target>                tasuki validate
tasuki monorepo                      tasuki ai

# Execution
tasuki mode <fast|standard|serious>  tasuki score "task"
tasuki route "task" [mode]           tasuki cost "task" [mode]
tasuki progress                      tasuki dashboard

# Memory
tasuki vault <stats|search|sync|query>
tasuki facts                         tasuki error "desc" --agent X
tasuki errors [list|clear]           tasuki discover

# Plugins
tasuki plugins                       tasuki install <type> <name>

# Team
tasuki vault push                    tasuki vault pull
tasuki export                        tasuki import <file.tar.gz>
tasuki snapshot <name>               tasuki notify <setup|test>

# Maintenance
tasuki cleanup [--all]               tasuki restore [--all]
tasuki doctor [--fix]                tasuki hooks <install|uninstall>
```

</details>

## Stacks

Auto-detected: FastAPI, Django, Flask, Next.js, SvelteKit, Nuxt, Express, NestJS, Rails, Gin, Spring Boot, Laravel, Generic.

## Learn More

- **[Landing page](https://www.usetasuki.dev)** — pipeline visual, memory architecture, before/after demo
- **[CONTEXT.md](CONTEXT.md)** — full architecture guide
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — how to add profiles, agents, plugins

## License

MIT
