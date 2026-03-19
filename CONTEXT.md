# Tasuki — Complete Architecture, Pipeline, & Decision Guide

Last updated: 2026-03-18

Complete architecture, decisions, and technical reference for Tasuki — memory, discipline, and a process your AI can't skip.

---

## Table of Contents

**What & Why**
1. [What is Tasuki and why it exists](#1-what-is-tasuki-and-why-it-exists)
2. [The design philosophy](#2-the-design-philosophy)

**The Pipeline**
3. [The pipeline in detail](#3-the-pipeline-in-detail)
4. [Each agent in detail](#4-each-agent-in-detail)
5. [The mode system](#5-the-mode-system)

**Memory System**
6. [The memory system](#6-the-memory-system)

**Enforcement**
7. [Hooks and how they enforce the pipeline](#7-hooks-and-how-they-enforce-the-pipeline)

**Tooling & Integration**
8. [MCP servers and their pipeline stages](#8-mcp-servers-and-their-pipeline-stages)
9. [Skills and when they activate](#9-skills-and-when-they-activate)
10. [Multi-AI adapter system](#10-multi-ai-adapter-system)
11. [Plugin system](#11-plugin-system)

**Onboard & Operations**
12. [The onboard process step by step](#12-the-onboard-process-step-by-step)
13. [The dashboard](#13-the-dashboard)

**Technical Reference**
14. [Engine architecture: bash + Python](#14-engine-architecture-bash--python)
15. [Algorithmic complexity analysis](#15-algorithmic-complexity-analysis)
16. [Cost analysis](#16-cost-analysis)
17. [Interview system](#17-interview-system)
18. [Decisions that were evaluated and why](#18-decisions-that-were-evaluated-and-why)
19. [What's NOT in Tasuki and why](#19-whats-not-in-tasuki-and-why)
20. [File inventory](#20-file-inventory)

---

## 1. What is Tasuki and why it exists

### The problem

AI coding assistants are powerful but dumb out of the box. They don't know your stack, your conventions, your architecture. Every session starts cold:

- **Hallucinated file paths**: "I'll create `src/models/user.py`" when the project uses `app/models/`
- **Guessed dependency versions**: "Using SQLAlchemy 1.4" when the project has 2.0
- **Wrong test framework**: Writes Jest tests for a pytest project
- **No security review**: Introduces SQL injection because nobody checks
- **No TDD enforcement**: Writes implementation first, tests never
- **No delegation**: One agent tries to do everything — no specialization, no observability
- **No memory**: Makes the same mistake in task #89 that it made in task #45

### The solution

Tasuki scans your project once (`tasuki onboard .`), generates configuration files, and your AI assistant instantly becomes a team of 9 specialized engineers who follow a sequential pipeline with TDD, security audits, and a two-layer knowledge system that gets smarter with every task.

**You don't change how you talk to your AI.** Tasuki changes how your AI behaves. It's invisible infrastructure — like ESLint, you don't say "hey ESLint", it just works.

### The analogy

Tasuki is Docker Compose for AI agents. Docker Compose doesn't run your code — it defines what services run, in what order, with what config. Tasuki does the same with AI agents.

### What Tasuki is NOT

- **NOT a chatbot**: It generates config files. You talk to your existing AI tool normally.
- **NOT a SaaS**: It's a CLI tool. Runs locally. Nothing goes to a server.
- **NOT a library you import**: No `import tasuki`. It generates `.tasuki/` and `TASUKI.md`.
- **NOT locked to Claude Code**: Works with 8 AI tools via adapters.
- **NOT a replacement for the developer**: The human decides what to build, approves plans, and has the last word.
- **NOT a RAG replacement**: Uses RAG as Layer 2, but the primary memory is wikilinks ($0, offline, human-readable).

---

## 2. The design philosophy

### Why the pipeline is sequential

**Decision:** Backend FIRST, Frontend SECOND. Never in parallel.
**Alternatives evaluated:** Backend and Frontend in parallel for "going faster."
**Why this option:** The frontend consumes the backend's endpoints. If both build in parallel, Frontend assumes a response structure that may not match what Backend implemented. The result: rework. The API is the contract — Backend defines it, Frontend consumes it.
**Consequence if changed:** API contract mismatches. Frontend builds a form with 5 fields, Backend implements the endpoint with 7. Discovered during integration, frontend redone.

Same applies to the DBA -> Dev sequence: Dev needs the tables to implement queries. If Dev runs before DBA, imports fail because the model doesn't exist.

### Why QA goes first (TDD)

**Decision:** QA writes tests before any implementation exists (Stage 2, before DBA and Dev).
**Why this option:** The test defines the expected behavior. If Dev writes first, the test becomes a validation of code that already exists — it doesn't discover bugs, it confirms what was already written.
**Enforcement:** The `tdd-guard` hook blocks writes to implementation files if there are no tests first. Exit code 2 = blocked. Not advisory — mechanical.

### Why Security and Reviewer go at the end

**Decision:** Security (Stage 6) and Reviewer (Stage 7) audit after all code exists.
**Why this option:** You can't audit what doesn't exist. A security audit on partial code produces false positives (auth is added at the end) and false negatives (you can't see the interaction between components).

### Why agents are specialized (not one general agent)

**Decision:** 9 agents with limited scopes instead of 1 general agent.
**Why this option:** Observability. When a test fails, you know which stage to look at. Each agent has a "Not Your Job" section that prevents interference. A DBA who writes routers bypasses Security review.

### Why memory has two layers

**Decision:** Wikilinks (Layer 1) + RAG via MCP (Layer 2) instead of RAG-only.
**Why this option:** Layer 1 is always loaded at zero cost (files already in the agent's context). Layer 2 is on-demand for deep queries. Traditional RAG loads everything on every query — expensive and noisy.
**Consequence if changed:** RAG-only means every agent query costs tokens and needs a vector DB running. Wikilinks-only means agents can't search across schema, git history, or past PRDs semantically.

### Why memory is behavioral, not a hook

**Decision:** Memory is written by the agent using LLM reasoning, not extracted by a PostToolUse hook.
**Why this option:** A shell script can't evaluate significance. "Root cause required 3 investigation rounds" is valuable insight that needs LLM reasoning, not regex.
**Consequence if changed:** A PostToolUse hook writes on every tool call -> thousands of useless entries in 6 months.

### Why hooks write to .claude/settings.local.json

**Decision:** Hooks are registered in `.claude/settings.local.json`, NOT in `.tasuki/settings.json`.
**Why this option:** Claude Code reads `.claude/settings.local.json` as its native hook configuration. The original approach wrote to `.tasuki/settings.json`, which Claude Code silently ignored — hooks never fired.
**Discovery:** Hooks were being generated correctly but never executed. Investigation revealed Claude Code only reads its own `.claude/` directory for local settings. The `write_ai_hooks()` function in `onboard.sh` now writes directly to `.claude/settings.local.json`.
**Consequence if changed:** Hooks become decorative. TDD guard doesn't block, pipeline tracker doesn't track, security check doesn't scan. The entire enforcement layer is inert.

---

## 3. The pipeline in detail

### The complete flow

```
User Prompt
     |
[1]  PLANNER
     Read .tasuki/agents/planner.md (MANDATORY — never skip reading the file)
     Read project-context.md (business understanding)
     Read project-facts.md (verified stack)
     Read tasuki-plans/index.md (previous plans)
     Read capability-map.yaml (available agents)
     Design: PRD + implementation plan with agent-specific instructions
     Save to: tasuki-plans/{feature}/prd.md + plan.md + status.md
     Push tasks to: Taskmaster MCP (one task per agent)
     Show user: brief plan summary
     Ask: "Continue with implementation?"
     Report: tasuki progress update . 1 "Planner" done
     |
[1b] TASKMASTER MCP
     Parses Planner's PRD into structured tasks
     One task per agent (~50 tokens vs ~2000 for full PRD)
     |
[2]  QA
     Read .tasuki/agents/qa.md (MANDATORY)
     Before You Act: tasuki vault expand . qa (loads graph-expanded memories)
     Read task from Taskmaster
     Schema Protocol: if model doesn't exist -> BLOCK, report to DBA
     Write failing tests (RED phase)
     Tests MUST fail. If they pass -> not testing new behavior.
     Report: tasuki progress update . 2 "QA" done
     |
[3]  DB ARCHITECT
     Read .tasuki/agents/db-architect.md (MANDATORY)
     Before You Act: tasuki vault expand . db-architect
     Pipeline Coordination: verify plan matches QA's tests
     Create migration + model using Production-Safe DDL patterns
     Report: tasuki progress update . 3 "DB-Architect" done
     |
[4]  BACKEND DEV
     Read .tasuki/agents/backend-dev.md (MANDATORY)
     Before You Act: tasuki vault expand . backend-dev + query RAG if mode=serious
     Run QA's tests first — confirm they fail for the RIGHT reason
     Implement until ALL tests pass (GREEN phase)
     Report: tasuki progress update . 4 "Backend-Dev" done
     |
[*]  TEST CHECKPOINT
     Run: {{TEST_COMMAND}}
     All pass? -> Continue to Stage 5
     Any fail? -> Invoke Debugger (Stage 5.5)
     Do NOT proceed to Frontend with failing backend tests
     |
[5]  FRONTEND DEV
     Read .tasuki/agents/frontend-dev.md (MANDATORY)
     Step 5a: Design preview (Figma MCP or Stitch MCP -> user approves)
     Step 5b: Build with /ui-ux-pro-max skill
     Report: tasuki progress update . 5 "Frontend-Dev" done
     |
[*]  TEST CHECKPOINT
     |
[5.5] DEBUGGER (only if tests fail)
     Read .tasuki/agents/debugger.md (MANDATORY)
     Max 5 diagnostic steps, then escalate
     Delegate fix to right agent -> re-run tests
     Max 3 rounds
     |
[6]  SECURITY
     Read .tasuki/agents/security.md (MANDATORY)
     Before You Act: tasuki vault expand . security + query RAG for past findings
     Run Semgrep MCP
     Walk OWASP Top 10 checklist
     Check Postgres MCP for RLS policies
     CRITICAL/HIGH -> delegate fix -> re-scan (max 3 rounds)
     Report: tasuki progress update . 6 "Security" done
     |
[7]  REVIEWER
     Read .tasuki/agents/reviewer.md (MANDATORY)
     Read ALL changed files (not just diff)
     Cross-reference: models <-> routes <-> schemas <-> tests <-> migrations
     3-round fix loop with regression detection
     APPROVE or REQUEST CHANGES (never approve unresolved CRITICALs)
     Report: tasuki progress update . 7 "Reviewer" done
     |
[8]  DEVOPS
     Read .tasuki/agents/devops.md (MANDATORY)
     Update Docker/CI if needed
     Report: tasuki progress update . 8 "DevOps" done
     |
[9]  COMPLETION
     Show summary (files created/modified, tests, security, reviewer verdict)
     Write to memory vault — Layer 1 (wikilinks) + Layer 2 (RAG auto-sync)
     Update tasuki-plans/{feature}/status.md
     Report: tasuki progress complete .
```

### Pipeline tracking

The pipeline is tracked mechanically via hooks — Claude Code doesn't need to "decide" to report progress:

**Pipeline Trigger Hook** (`UserPromptSubmit`): Detects task-like prompts (action words like "add", "fix", "create") and injects "Follow the pipeline in CLAUDE.md" into the AI's context. Also triggered by keywords "tasuki:", "plan:", "fix:". Sets the pipeline active flag by initializing `.tasuki/config/pipeline-progress.json` with the task name, mode, start time, and status "running".

**Pipeline Tracker Hook** (`PreToolUse: Read|Edit|Write|Bash|Agent|Glob|Grep`): Runs on EVERY tool use. When Claude reads `.tasuki/agents/planner.md`, the hook writes Stage 1 to `.tasuki/config/pipeline-progress.json`. When it reads `agents/qa.md`, Stage 2. Automatic — Claude doesn't need to cooperate. The tracker also:
- Logs every Read to `tracker-debug.log` (used by `force-agent-read.sh` to verify agent files were loaded)
- Marks previous stages as "done" when a higher stage starts
- Detects pipeline completion when Reviewer is done and all stages are "done"
- Writes completed pipelines to `pipeline-history.log` with date, mode, score, agents, duration, and task name
- Auto-triggers RAG sync in background when writes to `memory-vault/` are detected

**Mandatory agent file reading**: The TASUKI.md says "You MUST read `.tasuki/agents/{agent-name}.md` before executing each stage. No exceptions." This ensures (1) the agent gets its full instructions, (2) the tracker hook detects which stage is active, and (3) the `force-agent-read.sh` hook can verify that an agent file was loaded before any code edits happen.

### Pipeline state machine

The pipeline tracker records machine-readable state per stage:

```json
{
  "task": "add overdue loans",
  "mode": "standard",
  "started": "2026-03-15 21:25:00",
  "status": "running",
  "current_stage": 4,
  "total_stages": 9,
  "stages": {
    "Planner": {
      "status": "done",
      "time": "21:25:49",
      "files_created": ["tasuki-plans/overdue/prd.md", "tasuki-plans/overdue/plan.md"],
      "files_read": ["agents/planner.md"],
      "files_edited": [],
      "tests_run": 0,
      "tests_passed": 0
    },
    "QA": {
      "status": "done",
      "time": "21:29:22",
      "files_created": ["loans/tests/test_overdue.py"],
      "files_read": ["agents/qa.md"],
      "tests_run": 3,
      "tests_passed": 0
    },
    "Backend-Dev": {
      "status": "running",
      "time": "21:33:43",
      "files_created": [],
      "files_edited": ["loans/views.py", "loans/services.py", "loans/repositories.py"],
      "files_read": ["agents/backend-dev.md"],
      "tests_run": 5,
      "tests_passed": 3
    }
  }
}
```

| Field | Source | Purpose |
|-------|--------|---------|
| `files_read` | PreToolUse Read hook | What the agent examined |
| `files_created` | PreToolUse Write hook | New files the agent wrote |
| `files_edited` | PreToolUse Edit hook | Existing files the agent modified |
| `tests_run` | PreToolUse Bash (pytest/jest/etc detected) | Number of test suite executions |
| `status` | Stage transitions | done, running, skipped |
| `time` | Clock | When the stage started |

**Session continuity:** If the session is interrupted at Backend-Dev:
1. Next session reads `pipeline-progress.json`
2. Sees Backend-Dev was running, created no files, edited 3, ran 5 tests
3. The `force-planner-first` hook sees Planner is done → allows edits
4. The `force-agent-read` hook sees Backend-Dev in progress → allows edits after re-reading the agent
5. The agent picks up exactly where it left off — with mechanical state, not LLM interpretation

**Completion detection:** The tracker auto-detects completion when Reviewer stage exists with status "done", all other stages are done, and at least 3 stages completed. On completion it writes to `pipeline-history.log` and the dashboard auto-refreshes via SSE.

**Pipeline history log** (`.tasuki/config/pipeline-history.log`):
```
2026-03-15 02:30|standard|8|Planner,QA,Backend-Dev,Security,Reviewer|420|add overdue loans endpoint
2026-03-15 03:15|fast|4|QA,Backend-Dev,Reviewer|180|fix login error
```

**Terminal display** (`tasuki progress`):
```
Pipeline: add overdue loans
████████░░░░░░░░░░░░ 44% (4/9)
Mode: standard | Status: running
Stages:
  ✓ Planner (done) (21:25:49) — 2 created
  ✓ QA (done) (21:29:22) — 1 created, 3 tests
  → Backend-Dev (running) (21:33:43) — 3 edited, 5 tests
────
Files: 3 created, 3 edited | Tests: 8 runs
```

### Pipeline resilience

If the session ends mid-pipeline:
1. Each stage updates `tasuki-plans/{feature}/status.md` with `[x]` checkboxes
2. Next session: AI reads status.md -> sees which stages completed -> continues from first `[ ]`
3. No restart from Stage 1 unless user explicitly requests it

---

## 4. Each agent in detail

Each agent file is 250-400 lines with this structure:

```markdown
---
name: agent-name
domains: [domain1, domain2, ...]
triggers: [keyword1, keyword2, ...]
priority: 1-10
activation: always | conditional | reactive
model: thinking | execution
stack_required: backend | frontend | database | infra | none
---

## Your Position in the Pipeline
Where you sit, who comes before, who comes after.

## Before You Act (MANDATORY)
1. Read project-facts.md
2. tasuki vault expand . agent-name (graph expansion — loads memories N levels deep)
3. If mode=serious: query RAG deep memory for domain context

## [Domain-specific sections]
Checklists, protocols, patterns for this agent's domain.

## Not Your Job — Delegate Instead
Hard boundaries. What this agent must NEVER do.

## Consuming Work from Other Agents
How to read handoffs from previous stages.

## Post-Task Reflection
Trigger conditions for writing to memory vault.

## Handoff
Structured block for the next stage.
```

### The "Before You Act" section — graph expansion integration

Every agent's "Before You Act" section calls `tasuki vault expand . agent-name` instead of raw grep. This means:

1. The vault builds a graph in memory with a single `os.walk` (dict of nodes + reverse index)
2. BFS traversal follows wikilinks N levels deep from the agent node
3. Results are filtered by the current mode's confidence level
4. The agent receives related memories it didn't explicitly ask for

Example: When `backend-dev` runs vault expand, it starts from the `[[backend-dev]]` node and discovers:
- Direct links: `[[fastapi]]`, `[[postgres]]`, `[[context7-mcp]]`
- One hop: `[[always-use-parameterized-queries]]` (linked from postgres), `[[never-trust-client-input]]` (linked from security to backend-dev)
- Two hops (serious mode): `[[advisory-lock-bug]]` (linked from db-architect, which links to postgres)

The depth is auto-detected from mode: fast=0 (direct links only), standard=1 (one hop), serious=2 (two hops).

### The 9 agents

| Agent | Model | Activation | Stack Required | Key Responsibility |
|-------|-------|-----------|----------------|-------------------|
| **Planner** | thinking | always | none | Architecture, PRDs, task decomposition via Taskmaster |
| **QA** | execution | always | none | TDD enforcement, Schema Protocol, comprehensive tests |
| **DB Architect** | execution | conditional | database | Production-safe DDL, pipeline coordination with QA |
| **Backend Dev** | execution | conditional | backend | Implementation until tests pass, structured handoff |
| **Frontend Dev** | execution | conditional | frontend | Design preview -> approval -> build with /ui-ux-pro-max |
| **Debugger** | execution | reactive | none | Root cause in max 5 steps, Safety Net, Re-investigation Protocol |
| **Security** | thinking | always | none | OWASP Top 10, variant analysis, FP Protocol |
| **Reviewer** | thinking | always | none | 3-round fix loop, regression detection, quality gate |
| **DevOps** | execution | conditional | infra | Docker, CI/CD, zero-downtime deploys |

### Production-hardened features per agent

- **QA**: Schema Protocol (blocks if model doesn't exist) + TDD Phase Awareness (knows RED vs GREEN)
- **Debugger**: Safety Net (max 5 steps) + Re-investigation Protocol (never restarts from zero)
- **DB Architect**: Production-Safe DDL (expand-contract, batched defaults, CONCURRENTLY) + Pipeline Coordination
- **Security**: Variant Analysis (finds one vuln, searches entire codebase) + FP Protocol (no false positives)
- **Reviewer**: 3-round fix loop + regression detection (checks files that IMPORT the fixed file)

---

## 5. The mode system

Tasuki has three execution modes that control the pipeline depth, agent selection, memory expansion depth, confidence filtering, and RAG usage.

### Fast mode

**Use case:** Bug fixes, small tweaks, typos, config changes.

```
Pipeline:  QA -> Dev -> Reviewer
Skip:      Planner, DBA, Frontend, Debugger, Security, DevOps
Depth:     0 (direct links only in vault expand)
Confidence: high only
RAG:       Disabled (Layer 1 wikilinks only)
Planner:   Skipped (force-planner-first.sh is exempt)
Reviewer:  Single pass (no 3-round loop)
Security:  Lightweight scan (no full OWASP audit)
Tokens:    ~18K
Cost:      ~$0.26
```

### Standard mode (default)

**Use case:** Medium features, new endpoints, UI components, integrations.

```
Pipeline:  Planner -> QA -> Dev -> Security -> Reviewer
Optional:  DBA (if database changes needed), Frontend (if UI needed)
Depth:     1 (one hop in vault expand)
Confidence: high + experimental
RAG:       On-demand (Layer 2 when agent needs deep context)
Planner:   Full PRD with implementation plan
Reviewer:  Standard review pass
Security:  Semgrep + OWASP checklist
Tokens:    ~46K
Cost:      ~$0.68
```

### Serious mode

**Use case:** Architecture changes, security-sensitive features, payment systems, auth overhauls.

```
Pipeline:  Planner -> QA -> DBA -> Dev -> Security -> Reviewer (3 rounds)
All:       Every agent runs at full power
Depth:     2 (two hops in vault expand — full subgraph)
Confidence: all (high + experimental + deprecated)
RAG:       Mandatory (every agent MUST query RAG before acting)
Planner:   Full PRD + architecture review
Reviewer:  3-round fix loop with regression detection
Security:  Full OWASP audit with Semgrep MCP + Postgres RLS check
Tokens:    ~71K+
Cost:      ~$1-3
```

### Mode switching

```bash
tasuki mode fast
tasuki mode standard
tasuki mode serious
tasuki mode auto    # Score 1-3 -> fast, 4-6 -> standard, 7-10 -> serious
```

Mode is persisted to `.tasuki/config/mode` — no re-onboard needed. The `switch_mode()` function updates TASUKI.md and the mode file. The vault, hooks, and dashboard all read from this file.

### Mode impact on each subsystem

| Subsystem | Fast | Standard | Serious |
|-----------|------|----------|---------|
| vault expand depth | 0 | 1 | 2 |
| Confidence filter | high | high+experimental | all |
| RAG queries | none | on-demand | mandatory |
| Planner | skipped | full PRD | full PRD + arch review |
| force-planner-first hook | exempt | enforced | enforced |
| Security audit | lightweight | Semgrep + OWASP | Semgrep + OWASP + RLS |
| Reviewer rounds | 1 | 1 | 3 |
| Dashboard pipeline display | 3 stages | 5-8 stages | 9 stages |

---

## 6. The memory system

### The problem memory solves

An LLM starts every session cold. Task #89 requires knowledge from task #45. Without persistent memory, the agent reinvestigates from zero.

### Architecture: Two layers

```
Layer 1: Wikilinks (always loaded, $0)
  memory-vault/heuristics/always-index-lookups.md -> [[db-architect]] [[backend-dev]]
  -> Agent calls: tasuki vault expand . agent-name
  -> BFS traversal finds related nodes N levels deep
  -> Zero extra cost — tokens are already in the agent file context

Layer 2: RAG Deep Memory (on-demand, via MCP)
  .tasuki/config/rag-sync-batch.jsonl -> 50+ entries from schema, APIs, plans, git
  -> Agent queries: "how do we handle payments?" -> semantic search
  -> Returns full models, endpoints, past PRDs, incidents
  -> <50ms, local SQLite, $0
```

**Why not RAG-only:** RAG queries cost tokens on every call and need infrastructure. Wikilinks are free — they're already inside the agent file. Layer 2 complements when the agent needs deep context beyond the 4-line summary.

**Why not wikilinks-only:** Agents can't semantically search across schema, git history, or past PRDs with grep alone. Layer 2 enables "find everything related to payments" across the entire project.

### 6.1 Layer 1: Knowledge Graph (Wikilinks)

```
memory-vault/
├── index.md                                    <- graph index
├── agents/                                     <- auto-generated from installed agents
│   ├── backend-dev.md                          -> [[fastapi]] [[postgres]]
│   └── security.md                             -> [[semgrep-mcp]] [[owasp]]
├── heuristics/                                 <- PERMANENT rules (never expires)
│   ├── always-index-lookup-columns.md          -> [[db-architect]] [[backend-dev]] [[reviewer]]
│   ├── always-use-parameterized-queries.md     -> [[backend-dev]] [[security]]
│   ├── tests-before-code.md                    -> [[qa]] [[backend-dev]] [[reviewer]]
│   ├── never-trust-client-input.md             -> [[backend-dev]] [[security]] [[reviewer]]
│   └── handle-all-ui-states.md                 -> [[frontend-dev]] [[reviewer]]
├── bugs/                                       <- EPISODIC (specific incidents)
│   └── advisory-lock-bug.md                    -> [[db-architect]] [[backend-dev]]
├── errors/                                     <- "DO NOT" entries
│   └── used-print-not-logger.md                -> [[backend-dev]]
├── decisions/                                  <- architectural decisions with reasoning
├── lessons/                                    <- insights from implementation
├── tools/                                      <- MCP server nodes (auto-generated)
├── architecture/                               <- system design patterns
└── stack/                                      <- technology nodes (auto-generated)
```

**4-dimension format (every entry):**

```markdown
## {date} — {Short description}
**Pattern**: {The insight — what you learned}
**Evidence**: `{file:line}` — {what was observed}
**Scope**: {Where else this applies}
**Prevention**: {Grep pattern or rule to catch it next time}
```

**Anti-bloat rules:**
- Max 20 entries per agent (20 per type x 9 types = max 180 files)
- Only write when: root cause was non-obvious, fix caused regression, pattern discovered, security finding was new
- No duplicating TASUKI.md — if info is already in agent instructions, don't repeat
- Promotion protocol: same pattern appears 2+ times in bugs/lessons -> create permanent heuristic

### 6.2 Graph expansion with BFS

Agents need related knowledge they didn't explicitly ask for. A backend developer writing a payments endpoint should know about the `advisory-lock-bug` (linked to db-architect, which links to postgres, which links to backend-dev). With flat grep, the agent only finds memories that directly mention `[[backend-dev]]`. With graph expansion, it follows the wikilink graph and discovers related memories N hops away.

**The algorithm: O(V+E) with BFS using deque** (implemented in `vault_graph.py`):

**Step 1: Build graph in memory (single os.walk)**

```python
# One pass over all .md files in memory-vault/
nodes = {}       # name -> {type, summary, links, confidence, applied}
reverse = defaultdict(set)  # name -> set of nodes that reference it

for root, dirs, files in os.walk(vault):
    for f in files:
        # Extract: confidence level, applied count, summary, outgoing [[wikilinks]]
        # Build forward index (node -> its links) and reverse index (node -> who links to it)
```

This is a single `os.walk` — one pass over the filesystem. O(V) where V = number of memory files.

**Step 2: BFS traversal from start node**

```python
visited = set()
queue = deque([(start, 0)])  # (node_name, current_depth)
results = []

while queue:
    current, depth = queue.popleft()
    if current in visited or depth > max_depth:
        continue
    visited.add(current)

    # Get neighbors: outgoing links + reverse references
    neighbors = nodes[current]['links'] | reverse.get(current, set())

    for neighbor in neighbors:
        if neighbor not in visited and neighbor in nodes:
            # Filter by confidence level
            if nodes[neighbor]['confidence'] not in allowed_confidence:
                continue
            results.append(neighbor_info)
        if depth + 1 < max_depth:
            queue.append((neighbor, depth + 1))
```

Using `deque` for O(1) popleft. Total traversal: O(V+E) where E = number of wikilinks.

**Step 3:** Filter by confidence, deduplicate, output results. The start node is excluded from output.

**How agents call it:**

```bash
tasuki vault expand . agent-name
# Depth auto-detected from mode: fast=0, standard=1, serious=2
```

**Output example:**
```
  Graph expansion for [[backend-dev]] (depth=1, mode={'high', 'experimental'}):
      [heuristics] always-use-parameterized-queries: Never use string interpolation in SQL
      [heuristics] always-index-lookup-columns: Every column used in WHERE must have an index
      [heuristics] tests-before-code: Write failing tests FIRST
      [heuristics] never-trust-client-input: ALL data from the client must be validated [experimental]
      [stack] fastapi: Used By backend-dev
      [stack] postgres: Used By db-architect, backend-dev
      [tools] context7-mcp: Up-to-date documentation for frameworks
      [bugs] advisory-lock-bug: PostgreSQL advisory lock deadlock (applied 2x)
```

### 6.3 Confidence scoring

Not all memories are equal. A freshly validated heuristic is more trustworthy than a 6-month-old experimental pattern.

**Metadata fields (every memory node):**

```markdown
Confidence: high
Last-Validated: 2026-03-15
Applied-Count: 3
```

| Level | Meaning | When assigned |
|-------|---------|---------------|
| **high** | Proven, validated, safe to follow | Default for new memories. Pattern confirmed in production. |
| **experimental** | Promising but unconfirmed | Pattern observed once, needs more evidence. |
| **deprecated** | Outdated, may cause issues | Framework changed, pattern no longer applies. Kept for context. |

**Filtering by mode:**

| Mode | Allowed confidence levels | Rationale |
|------|--------------------------|-----------|
| **fast** | high only | Quick fixes need proven patterns only |
| **standard** | high + experimental | Normal features can benefit from experimental insights |
| **serious** | high + experimental + deprecated | Architecture changes need full context, even deprecated knowledge |

**Commands:**
```bash
tasuki vault confidence advisory-lock-bug deprecated  # mark obsolete
tasuki vault confidence new-pattern experimental       # mark as unproven
tasuki vault applied always-index-lookup-columns       # increment applied count
```

### 6.4 Auto-decay of memories

Over time, heuristics can become obsolete. Without cleanup, the vault accumulates stale advice that can mislead agents.

**Automatic decay based on age and usage** (implemented in `vault_decay.py`):

```
high → 90 days no validate/apply → experimental
experimental → 60 days more → deprecated
deprecated → 30 days more → archived (moved to memory-vault/archive/)
```

And the reverse — promotion:

```
experimental + applied 3+ times → promoted to high
```

**When does decay run?**
- Automatically during `tasuki vault sync` (before indexing to RAG)
- Automatically during `tasuki doctor` (memory health check)
- Manually with `tasuki vault decay`

No cron jobs, no daemons, no background processes. It runs as part of operations the developer already does.

**Manual override:**
```bash
tasuki vault confidence always-use-parameterized-queries deprecated  # mark obsolete
tasuki vault confidence new-pattern experimental                     # mark as unproven
```

**Archive:** Archived memories are moved to `memory-vault/archive/`. They're not deleted — they can be recovered if needed. The archive directory is excluded from graph expansion and RAG indexing.

### 6.5 Team memory sync (vault push/pull)

Developer A discovers "never use advisory locks with PostgreSQL 15" and saves it as a heuristic. Developer B on the same team doesn't know. The memory vault is local per developer.

**Solution:** `vault push` and `vault pull` sync generalizable knowledge through git — no server, no SaaS.

```bash
tasuki vault push    # push heuristics + decisions + lessons to tasuki-knowledge branch
tasuki vault pull    # pull team knowledge into local vault
```

**What syncs and what doesn't:**

| Type | Syncs? | Why |
|------|--------|-----|
| **Heuristics** | Yes | Universal patterns the whole team benefits from |
| **Decisions** | Yes | Architectural decisions everyone should know |
| **Lessons** | Yes | Learnings that apply across the team |
| **Bugs** | No | Specific to the developer's local context |
| **Errors** | No | Local mistakes, not generalizable |
| **Agents/Tools** | No | Structural nodes, not knowledge |
| **RAG index** | No | Depends on local repo state |

**How push works:**
1. Reads `memory-vault/heuristics/`, `decisions/`, `lessons/`
2. Filters: only `confidence: high` memories (no experimental or deprecated)
3. Filters: skips files with `-team` suffix (merge artifacts)
4. Creates orphan branch `tasuki-knowledge` (no shared history with main)
5. Copies memories, commits with author attribution
6. Pushes to remote if available

**How pull works:**
1. Fetches `tasuki-knowledge` from remote
2. For each memory in the branch:
   - If local file doesn't exist → pull directly
   - If local file exists with identical content → skip
   - If local file exists with different content → **keep-both strategy**: saves remote as `{name}-team.md`
3. Developer consolidates duplicates manually, then pushes the unified version

**Keep-both merge strategy:** When two developers write about the same topic, remote version is saved as `{name}-team.md` alongside the local version. No information is ever lost — worst case is a duplicate that gets consolidated. This is intentional: losing a memory is worse than having a duplicate.

### 6.6 Layer 2: RAG Deep Memory

`tasuki vault sync` indexes the entire project into a vector store:

| Type | What | Count (Django example) |
|------|------|----------------------|
| **Memories** | Heuristics, bugs, lessons, decisions, errors | 19 |
| **Schema** | Models, migrations, tables, columns | 8 |
| **API** | Views, routes, serializers, endpoints | 13 |
| **Plans** | PRDs, status, architectural decisions | 7 |
| **Git** | Recent commits and diffs | 20 |
| **Config** | Docker, settings, package.json | 3 |
| **Total** | | **70 entries, 148 KB, <50ms queries** |

**Output format:** `.tasuki/config/rag-sync-batch.jsonl` — one JSON object per line:
```json
{"id": "vault/heuristics/always-index-lookup-columns", "type": "heuristics", "name": "always-index-lookup-columns", "tags": "db-architect,backend-dev,reviewer,postgres", "content": "...full file content..."}
```

**How agents use it:**

```bash
# Fast mode — Layer 1 only (depth=0, confidence=high)
tasuki vault expand . backend-dev -> direct links only, ~72 tokens, $0

# Standard mode — Layer 1 + Layer 2 when needed (depth=1, confidence=high+experimental)
tasuki vault expand . backend-dev + query RAG "payments" -> full schema + related code

# Serious mode — Layer 1 + Layer 2 mandatory (depth=2, all confidence)
Every agent MUST: tasuki vault expand + query RAG before acting for full project context
```

**Auto-sync triggers:**
1. During onboard: Phase 5.5 runs `vault_rag_sync()` after vault initialization
2. During pipeline: When the pipeline-tracker hook detects a write to `memory-vault/`, it runs `tasuki vault sync` in the background

**Query example:**
```bash
$ tasuki vault query "authentication"
  [schema] authentication models — CustomAPIKey, JWT tokens
  [api]    authentication views — login, register, logout
  [api]    authentication serializers — token validation
  [plan]   auth-logout-profile — PRD + implementation
  4 results in 12ms
```

### 6.7 RAG growth path

The agent query never changes — only the MCP backend in `.mcp.json`:

| Scale | Backend | Infrastructure | Query Type | When to upgrade |
|-------|---------|---------------|------------|----------------|
| 0 | Wikilinks only | None | grep/BFS | Default for offline/simple projects |
| 1 | `rag-memory-mcp` | Local SQLite | Keyword + basic vector | **Default** — sufficient for most projects |
| 2 | Qdrant MCP | Qdrant container | Full vector search | Team use, >500 memories |
| 3 | pgvector | PostgreSQL | Full vector + SQL | Production, multi-team |

**The agent is backend-agnostic.** Swap `.mcp.json` from `rag-memory-mcp` to `qdrant-mcp` — no agent prompt changes.

### How memory connects to the pipeline (6 points)

```
Pipeline runs -> agents act -> learn -> write to vault (Stage 9)
                                              |
Next pipeline -> agents read vault -> act smarter -> learn more
                        ^                               |
                        +---- write new learnings ------+
```

1. **Before You Act** (every stage): `tasuki vault expand . agent-name` (BFS graph expansion, depth from mode)
2. **Stage 9 writes**: After Reviewer APPROVES, write to vault if non-obvious insight
3. **Error Memory**: `tasuki error "desc" --agent X` -> creates node + appears in project-facts "Do NOT"
4. **Project Facts**: Auto-generated from real files. Every agent reads first. Anti-hallucination.
5. **Project Context**: Business understanding from interview. Only Planner reads it (~500 tokens saved per agent).
6. **Capability Map**: Auto-generated from agent frontmatter. Planner reads to route by domain, not by name.

---

## 7. Hooks and how they enforce the pipeline

### Overview: 9 hooks total

Tasuki has 9 hooks that enforce the pipeline mechanically. Hooks use exit code 2 to BLOCK operations — this is not advisory, it's a hard stop that Claude Code respects.

All hooks are written to `.claude/settings.local.json` during onboard (the file Claude Code actually reads for local configuration).

**Agent Teams hooks (Claude Code only):**

| Hook | Event | What it does |
|------|-------|-------------|
| **teammate-idle.sh** | TeammateIdle | Quality gate — runs tests and security checks before a teammate can go idle |
| **task-completed.sh** | TaskCompleted | Validates acceptance criteria before marking a task done |

These hooks are only registered when Agent Teams is active (the default for Claude Code).

### PreToolUse hooks (mechanical enforcement)

| Hook | Matcher | What it does | Exit code |
|------|---------|-------------|-----------|
| **pipeline-tracker.sh** | Read\|Edit\|Write\|Bash\|Agent\|Glob\|Grep | Silently tracks pipeline stage based on which agent file Claude reads. Writes to pipeline-progress.json. Logs reads to tracker-debug.log. Auto-syncs RAG on memory-vault/ writes. Writes to pipeline-history.log on completion. | Always 0 (never blocks) |
| **tdd-guard.sh** | Edit\|Write | Blocks edits to implementation files if no test file exists | 2 = blocked |
| **security-check.sh** | Edit\|Write | Scans for SQL injection, eval(), hardcoded secrets, etc. | 2 = blocked |
| **protect-files.sh** | Edit\|Write | Blocks edits to .env, secrets/, lock files | 2 = blocked |
| **force-agent-read.sh** | Edit\|Write | Blocks code edits unless an agent file was read first (ensures Before You Act runs) | 2 = blocked |
| **force-planner-first.sh** | Edit\|Write | Blocks code edits unless a PRD exists in tasuki-plans/ (ensures Planner runs before implementation). Exempt in fast mode. | 2 = blocked |

### UserPromptSubmit hook

| Hook | What it does |
|------|-------------|
| **pipeline-trigger.sh** | Detects task-like prompts (action words + dev keywords) and injects "Follow the pipeline in CLAUDE.md". Skips questions ("how", "what", "why"). Respects "skip pipeline" / "no pipeline". Initializes pipeline-progress.json with task name and sets status to "running". |

### How force-agent-read works

```
User (or Claude) tries to edit app/routers/users.py
  -> Hook checks .tasuki/config/tracker-debug.log for agent file reads
  -> Also checks pipeline-progress.json for any stage "running"
  -> No agent file was read? -> Exit 2: "BLOCKED: Read an agent file first"
  -> Agent file was read? -> Exit 0: edit allowed

Exempt files: .tasuki/*, tasuki-plans/*, memory-vault/*, CLAUDE.md, TASUKI.md,
              config files (*.json, *.yaml, *.yml, *.toml, *.ini, *.cfg, *.env*),
              documentation (*.md, *.txt, *.rst),
              test files (test_*, _test.*, *.test.*, *.spec.*, conftest*, fixture*),
              migrations (*migration*, *alembic*),
              Docker/CI (Dockerfile*, docker-compose*, .github/*, .gitlab-ci*),
              lock files (*lock*, *Lock*)
```

**Pipeline connection:** This MECHANICALLY ensures agents load their "Before You Act" section (which includes memory vault expansion, project facts, and context loading) before making any code changes.

### How force-planner-first works

```
User (or Claude) tries to edit app/routers/users.py
  -> Hook checks: is mode "fast"? -> Yes? Exit 0 (fast skips Planner)
  -> Hook checks: does tasuki-plans/ contain any prd.md/plan.md/status.md? -> Yes? Exit 0
  -> Hook checks: does pipeline-progress.json mention "Planner"? -> Yes? Exit 0
  -> None of the above? -> Exit 2: "BLOCKED: Planner must run before implementation."
```

### How tdd-guard works

```
User writes app/routers/users.py
  -> Hook checks: does tests/test_users.py exist?
  -> No -> Exit 2: "TDD GUARD: No tests found. Create the test file first."
  -> Yes -> Exit 0: edit allowed

Exceptions: config files, docs, migrations, test files, Docker, CI, .tasuki/
```

### How pipeline-trigger works

```
User types: "add overdue loans endpoint"
  -> Hook detects action word "add" + dev keyword "endpoint"
  -> Initializes pipeline-progress.json
  -> Outputs: "IMPORTANT: Follow the pipeline defined in CLAUDE.md."

User types: "how does authentication work?"
  -> Hook detects question word "how" -> skips injection (exit 0)

User types: "fix the login bug, skip pipeline"
  -> Hook detects "skip pipeline" -> skips injection (exit 0)
```

### Hook configuration in .claude/settings.local.json

During onboard, `write_ai_hooks()` writes this structure:

```json
{
  "permissions": {
    "allow": [
      "Bash(tasuki *)", "Bash(python3 -m pytest *)", "Bash(pytest *)",
      "Bash(git *)", "Bash(npm *)", "Read(*)", "Edit(*)", "Write(*)",
      "Glob(*)", "Grep(*)", "Agent(*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|Bash|Agent|Glob|Grep",
        "hooks": [{"type": "command", "command": "/path/.tasuki/hooks/pipeline-tracker.sh"}]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "/path/.tasuki/hooks/protect-files.sh"},
          {"type": "command", "command": "/path/.tasuki/hooks/security-check.sh"},
          {"type": "command", "command": "/path/.tasuki/hooks/tdd-guard.sh"}
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{"type": "command", "command": "/path/.tasuki/hooks/pipeline-trigger.sh"}]
      }
    ]
  }
}
```

**Critical: This must be `.claude/settings.local.json`, not `.tasuki/settings.json`.** Claude Code only reads its own `.claude/` directory for local hook configuration.

---

## 8. MCP servers and their pipeline stages

| MCP | Stage | Agent(s) | Purpose |
|-----|-------|----------|---------|
| Taskmaster | 1b | Planner | Parse PRD into per-agent tasks (~50 tokens each) |
| Context7 | ALL | All agents | Up-to-date framework documentation |
| Playwright | 2, 5 | QA, Frontend | E2E testing, visual regression |
| Postgres | 3, 5.5 | DBA, Debugger | Schema inspection, EXPLAIN ANALYZE, RLS check |
| Figma | 5a | Frontend | Pull design specs from Figma files |
| Stitch | 5a | Frontend | Generate design preview for approval |
| Semgrep | 6, 7 | Security, Reviewer | Static analysis patterns |
| Sentry | 5.5, 6, 8 | Debugger, Security, DevOps | Error tracking, health checks |
| GitHub | 7, 8 | Reviewer, DevOps | PR review, CI status |
| RAG Memory | 4, 6 (standard), ALL (serious) | Backend, Security, all in serious | Deep memory vector search |

---

## 9. Skills and when they activate

### Pipeline-connected skills

| Skill | Stage | Agent | Purpose |
|-------|-------|-------|---------|
| /tasuki-plans | 1 | Planner | Persist PRDs with index |
| /memory-vault | 9 | All | Write learnings to knowledge graph |
| /ui-design | 5 | Frontend | Design-first workflow |
| /ui-ux-pro-max | 5 | Frontend | 161 rules, 67 styles, 57 font pairings |
| /context-compress | on-demand | Thinking agents | Compressed project summary |

### Utility skills

| Skill | Purpose |
|-------|---------|
| /hotfix | Create hotfix branch, minimal fix, run tests |
| /test-endpoint | Quick API testing with curl |
| /db-migrate | Run migration commands |
| /deploy-check | Health check all services |
| /tasuki-mode | Switch execution mode |
| /tasuki-status | Show pipeline configuration |
| /tasuki-onboard | Re-scan and regenerate config |

---

## 10. Multi-AI adapter system

### Architecture

`.tasuki/` is the universal internal format. Adapters translate to each platform:

```
.tasuki/ (universal)
  ├── agents/*.md
  ├── rules/*.md
  ├── hooks/*.sh
  ├── skills/*/SKILL.md
  ├── config/
  └── settings.json
       | adapters translate to:
  ├── CLAUDE.md (Agent Teams team lead) + settings.local.json   (Claude Code)
  ├── .cursor/rules/                                            (Cursor)
  ├── AGENTS.md                                                 (Codex CLI)
  ├── .github/copilot-instructions.md + .github/instructions/   (GitHub Copilot)
  ├── .continue/rules/                                          (Continue)
  ├── .windsurfrules                                            (Windsurf)
  ├── .roo/rules/ + .roomodes                                   (Roo Code)
  └── GEMINI.md                                                 (Gemini CLI)
```

### Path translation

All adapters translate `.tasuki/` paths in agent content to the target's equivalent paths. For example, `.tasuki/agents/planner.md` becomes `.cursor/rules/planner.md` for Cursor, `.roo/rules/agent-planner.md` for Roo Code, etc. References to hooks include a note that they only run in Claude Code.

### Claude Code: Agent Teams (real multi-agent orchestration)

Claude Code uses **Agent Teams** — each agent runs as a separate Claude Code instance with its own context window and model. This is real orchestration, not role-switching:

- **Planner** is the team lead (Opus) — receives the user's request, creates the plan, spawns teammates
- **QA, Backend Dev, DB Architect, Frontend Dev, Security, Reviewer, DevOps** are teammates (Sonnet/Haiku) — each spawned with its own context, loads its `.tasuki/agents/*.md` instructions
- **Shared task list** — teammates self-coordinate via Claude's native task system
- **TeammateIdle hook** — runs tests + security checks before a teammate can go idle (quality gate)
- **TaskCompleted hook** — validates acceptance criteria before marking a task done

Agent Teams is enabled automatically during `tasuki onboard .` — the adapter writes `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to `.claude/settings.local.json`. No manual configuration needed. Can be disabled with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0`.

Hooks that are redundant with Agent Teams (pipeline-trigger, pipeline-tracker, force-planner-first) are not registered in Claude's settings when Agent Teams is active. They remain in `.tasuki/hooks/` for other adapters.

### Other AI tools: role-switching

All other tools use role-switching within the same context window. The pipeline instructions in TASUKI.md tell the AI to read each agent file sequentially and adopt that role. Works but without true context isolation or model switching.

### Model translation

| Tier | Claude Code | Codex CLI | Gemini CLI | Cursor |
|------|-------------|-----------|-----------|--------|
| thinking | claude-opus-4 | o3 | gemini-2.5-pro | claude-sonnet-4 |
| execution | claude-sonnet-4 | o4-mini | gemini-2.5-flash | claude-sonnet-4 |

---

## 11. Plugin system

### Overview

Tasuki has a plugin catalog (`src/plugins.yaml`) with three types of installable components:

- **MCP Servers** — external tools the AI can use (databases, APIs, search, monitoring)
- **Skills** — markdown instruction files that teach the AI specific workflows
- **Agents** — additional specialist agents beyond the core 9

### Commands

```bash
tasuki plugins                    # list all available plugins
tasuki plugins mcp                # list available MCP servers only
tasuki plugins skills             # list available skills only
tasuki install mcp sentry         # install Sentry MCP + show setup instructions
tasuki install skill gen-openapi  # install OpenAPI generator skill
tasuki install agent pen-tester   # install penetration testing agent
tasuki uninstall mcp sentry       # remove from .mcp.json
```

### How install works

**MCP install (`tasuki install mcp <name>`):**
1. Reads the MCP definition from `plugins.yaml` (package, transport, url)
2. Adds the server entry to `.mcp.json`
3. Shows setup instructions specific to that MCP (credentials, env vars, account creation)
4. Reminds the user to restart their AI tool

**Skill install (`tasuki install skill <name>`):**
1. Copies the skill directory from templates to `.tasuki/skills/`
2. Renders any placeholders in the SKILL.md
3. Available immediately (no restart needed)

**Agent install (`tasuki install agent <name>`):**
1. Copies the agent template to `.tasuki/agents/`
2. Renders placeholders (project name, paths, etc.)
3. Updates the capability map
4. Requires AI tool restart to pick up

### MCP setup instructions

Each MCP that requires credentials shows step-by-step setup after install:

| MCP | Needs | Setup shown |
|-----|-------|-------------|
| **Sentry** | Account + API token | Create account -> API Keys -> export SENTRY_AUTH_TOKEN |
| **Figma** | Personal access token | Figma developers -> Create token -> export FIGMA_ACCESS_TOKEN |
| **Semgrep** | uvx installed | pip install uvx, optional SEMGREP_APP_TOKEN for cloud rules |
| **PostgreSQL** | Running database | Update DSN in .mcp.json or export DATABASE_URL |
| **MongoDB** | Running database | export MONGODB_URI |
| **Context7** | Nothing | Works via npx, no account needed |
| **Taskmaster** | Nothing | Works via npx, no account needed |
| **Playwright** | Nothing | Works via npx, no account needed |

### Smart MCP detection during onboard

During `tasuki onboard`, MCPs are added based on what the project actually has:

| MCP | Added when |
|-----|-----------|
| Context7 | Always (universal docs, free) |
| GitHub | `.git` directory exists |
| Taskmaster | Always (task management, free) |
| PostgreSQL | Database engine detected as postgresql |
| Semgrep | `uvx` available |
| Playwright | Frontend detected |
| Figma | Frontend detected AND `FIGMA_ACCESS_TOKEN` set |

This prevents broken MCPs from being added.

---

## 12. The onboard process step by step

`tasuki onboard .` runs these phases (all bash, $0 tokens):

```
Phase 1:    SCAN — run 5 detectors (backend, frontend, DB, infra, testing)
Phase 1.5:  INTERVIEW — ask business context questions (optional, skippable)
Phase 2a:   PROFILE — match detected stack to convention profile (13 profiles)
Phase 2b:   AGENTS — determine which agents to activate based on stack
Phase 3:    RENDER — substitute {{PLACEHOLDERS}} in templates, write .tasuki/
Phase 4:    VERIFY — check generated files (JSON valid, no unresolved placeholders)
Phase 5:    VAULT — initialize knowledge graph with agent/tool/heuristic nodes
Phase 5.5:  RAG SYNC — index project into deep memory (schema, APIs, plans, git, config)
Phase 5.6:  FACTS — generate verified project facts from real files
Phase 6:    DISCOVER — build capability map from agent frontmatter
Phase 7:    GITIGNORE — auto-add .tasuki/, memory-vault/, tasuki-plans/, TASUKI.md, CLAUDE.md to .gitignore
Phase 8:    HOOKS — write hooks to .claude/settings.local.json (the file Claude Code reads)
Phase 9:    ADAPT — translate to target AI tool (Claude, Cursor, Codex, etc.)
```

### Phase 8: Hooks to .claude/settings.local.json

The `write_ai_hooks()` function:
1. Creates `.claude/` directory if needed
2. Reads existing `.claude/settings.local.json` (preserves user settings)
3. Adds Tasuki permissions (tasuki, pytest, git, npm, etc.)
4. Writes PreToolUse hooks: pipeline-tracker (all tools), protect-files + security-check + tdd-guard (Edit|Write)
5. Writes UserPromptSubmit hook: pipeline-trigger

### Auto-detect AI tool

If no `--target` specified, Tasuki checks for installed AI tools and auto-selects. Claude Code is default if detected.

### Cost: $0

Everything is bash scripts (grep, find, awk, sed) plus Python for vault operations. No LLM calls during onboard.

### 13 Stack Profiles

Auto-detected on onboard: FastAPI, Django, Flask, Next.js, SvelteKit, Nuxt, Express, NestJS, Rails, Gin, Spring Boot, Laravel, Generic.

Each profile provides: test runner, routing conventions, migration commands, linter, Docker patterns, model conventions, testing patterns.

---

## 13. The dashboard

`tasuki dashboard` generates an HTML file and serves it on `localhost:8686`:

### Panels

- **Pipeline Status**: Animated agent characters (SVG), live stage tracking from pipeline-progress.json, progress bar. Active agent has glow effect (CSS `drop-shadow` with pulsing animation). Completed agents show green check mark. Skipped agents shown dimmed (opacity 0.12, grayscale) with NO check mark.
- **Knowledge Graph**: D3.js force-directed graph of memory-vault. Click nodes to highlight connections. Clickable legend filters by node type.
- **Health Score**: 0-100 with breakdown (Testing, Security, Documentation, Configuration, Quality, Infrastructure)
- **Overview**: Pipeline runs, total cost, avg complexity, active agents
- **Agent Usage**: Bar chart of which agents run most
- **Mode Distribution**: Doughnut chart (fast/standard/serious split)
- **Cost per Task**: Table with mode, agents, tokens, USD per task. Color-coded model tiers.
- **Complexity Distribution**: Histogram of task scores (1-10)
- **Recent Activity**: Timeline of pipeline runs
- **What Tasuki Did For You**: Impact counters (errors prevented, heuristics applied, hooks blocked, bugs avoided)

### Live updates (SSE with ThreadedServer)

1. **File watching**: Server watches `pipeline-progress.json`, `activity-log.json`, and `pipeline-history.log` using file modification time polling
2. **Change detection**: When any watched file changes, the server regenerates the HTML dashboard
3. **SSE endpoint**: `/events` endpoint sends "reload" events to connected browsers
4. **Browser reload**: JavaScript `EventSource` receives the event and calls `location.reload()`
5. **Live indicator**: Green pulsing dot in header shows connection status. Turns red if disconnected.

### Agent characters (SVG)

Each agent has a unique SVG character: Planner (strategist with clipboard), QA (tester with magnifying glass), DB Architect (database with schema), Backend Dev (code terminal), Frontend Dev (paintbrush), Debugger (bug with magnifying glass), Security (shield), Reviewer (eyes/checkmark), DevOps (gear/container).

Agent slot states: **pending** (dimmed, grayscale), **running** (full opacity, glow ring pulsing), **done** (full opacity, green check), **skipped** (dimmed, grayscale, NO check mark).

### Technical

- Chart.js for charts, D3.js for knowledge graph
- `ThreadingMixIn` server for concurrent SSE + HTTP handling
- `TASUKI_GENERATE_ONLY` env var for headless regeneration (used by file watcher)
- Port 8686, binds 0.0.0.0 for WSL/SSH access
- Colors per agent: CSS custom properties (`--planner: #D8D4CC`, `--qa: #F5E642`, `--backend: #00D4FF`, etc.)

---

## 14. Engine architecture: bash + Python

### Design principle

Tasuki's CLI and orchestration layer is 100% bash — zero runtime dependencies for setup and execution. Python is used for algorithmic operations that require data structures bash can't express efficiently (graphs, JSON manipulation, BFS traversal).

**The split:**
- **Bash (35 scripts in `src/engine/`)**: CLI dispatch, template rendering, detection, profile matching, mode switching, adapter generation, hook shell logic
- **Python (6 scripts in `src/engine/`)**: Graph algorithms, state machines, RAG indexing, confidence decay

### The 6 Python modules

| Module | Lines | Called from | Purpose |
|--------|-------|-------------|---------|
| `vault_graph.py` | 199 | `vault.sh` | BFS graph expansion with deque, O(V+E). Builds forward+reverse index with single `os.walk`, traverses N levels deep, filters by confidence. |
| `vault_decay.py` | 145 | `vault.sh` | Auto-decay: high->experimental (90d), experimental->deprecated (60d), deprecated->archived (30d). Promotion at 3+ applies. |
| `vault_seed.py` | 194 | `vault.sh` | Seeds 5 universal heuristics (always-index-lookup-columns, never-trust-client-input, always-use-parameterized-queries, tests-before-code, handle-all-ui-states). |
| `vault_sync.py` | 309 | `vault.sh` | RAG indexing: memory, schema, API routes, plans, git history, config. Also handles MCP setup and keyword query. CLI dispatch: `python3 vault_sync.py <action> [args...]` |
| `pipeline_state.py` | 236 | `pipeline-tracker.sh` | Pipeline state machine: stage transitions, file tracking (read/created/edited), test counting, completion detection, history logging, activity logging. |
| `hook_logger.py` | 43 | All blocking hooks | Shared activity logging. Replaces 5 separate inline blocks. Usage: `python3 hook_logger.py <activity_file> <timestamp> <hook_name> <detail>` |

### Why this split exists

Originally all Python was embedded inside bash heredocs (`python3 - <<'PYEOF' ... PYEOF`). This made the code invisible to readers — `vault.sh` appeared to be "simple bash" but had hundreds of lines of sophisticated Python (BFS with deque, state machines, RAG sync) hidden inside heredocs starting hundreds of lines deep.

The extraction makes the architecture visible: bash files are orchestration, Python files are algorithms. Each Python file has docstrings, clear function signatures, and is independently testable.

### Path resolution for hooks

Hooks run from `.tasuki/hooks/` (installed location) but need to find Python files in `src/engine/`. Solved with a candidate path search:

```bash
local logger=""
for candidate in \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../src/engine/hook_logger.py" \
  "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/hook_logger.py"; do
  [ -f "$candidate" ] && logger="$candidate" && break
done 2>/dev/null
```

This checks both the relative path from the hook's location and the path relative to the `tasuki` binary.

---

## 15. Algorithmic complexity analysis

### Graph expansion: O(V+E)

| Operation | Complexity | Implementation |
|-----------|-----------|----------------|
| Build graph (single os.walk) | O(V) | One pass over all .md files |
| Build reverse index | O(E) | One pass over all wikilinks during graph build |
| BFS traversal | O(V+E) | deque for O(1) popleft, visited set for O(1) lookup |
| Confidence filtering | O(1) per node | Set membership check |
| Total | O(V+E) | Single os.walk + BFS |

### Real-world performance

| Metric | Value |
|--------|-------|
| Max memory files | 180 (20 per type x 9 types) |
| Typical memory files | 20-50 |
| Graph expansion time (180 files) | <5ms |
| RAG query time (70 entries) | <50ms (SQLite) |

### Pre-built JSON index (future optimization)

If latency becomes an issue at scale:
1. On `vault sync`, build a `vault-graph.json` with all nodes, edges, and metadata
2. BFS reads from JSON (no os.walk needed)
3. Invalidate cache on vault writes (detected by pipeline-tracker hook)

Not needed yet — BFS completes in microseconds at current scale.

---

## 16. Cost analysis

| Scenario | Agents | Tokens | Cost (API) |
|----------|--------|--------|------------|
| Full feature (complexity 10) | 9 | ~71K | ~$1-3 |
| Standard feature (complexity 5-6) | 6 | ~46K | ~$0.68 |
| Fast fix (complexity 1-3) | 3 | ~18K | ~$0.26 |
| Onboarding | 0 | 0 | $0.00 |

**With $50 API credits:** ~50-80 tasks = roughly 1 month of development.

**Savings vs no Tasuki:**
- Thinking=opus + execution=sonnet: ~60% model cost
- Agent-specific memory loading via [[wikilinks]]: ~86% context reduction
- Taskmaster per-agent tasks: ~12K tokens/pipeline saved
- Error memory prevents retrying failed approaches: cumulative
- Capability routing skips irrelevant agents: ~40% fewer invocations
- Layer 2 RAG on-demand instead of always: tokens only when needed
- Confidence filtering in fast mode (high only): reduced noise, faster agent execution

---

## 17. Interview system

### What the interview captures

During Phase 1.5 of onboard, `interview.sh` asks optional questions about:
- Business domain (fintech, healthcare, e-commerce, etc.)
- Team size and structure
- Deployment environment (cloud provider, Kubernetes, etc.)
- Compliance requirements (PCI DSS, HIPAA, SOC 2, GDPR)
- Security sensitivity level

### Where interview answers go

Answers are written to `project-context.md` in the project root. This file is read by the Planner agent during Stage 1.

### Impact

- **Planner reads project-context.md**: Uses business domain knowledge to inform architectural decisions. A fintech project gets different PRD considerations than an e-commerce project.
- **Other agents save ~500 tokens each**: Only the Planner reads project-context.md. Other agents read project-facts.md (machine-verified stack) instead.
- **Domain profiles**: If interview reveals "fintech" domain, additional security directives are injected (PCI DSS compliance checks, encryption at rest, audit logging). 6 domain profiles available: fintech, healthcare, e-commerce, SaaS, education, government.

### Interview is optional

The interview is skippable (users can press Enter through all questions):
- CI/CD environments can't answer questions (non-interactive)
- Quick onboards shouldn't require Q&A
- project-context.md is still created with defaults if skipped

---

## 18. Decisions that were evaluated and why

| Decision | Why | Alternative evaluated | Consequence if changed |
|----------|-----|----------------------|----------------------|
| Sequential pipeline | API is the contract | Parallel backend+frontend | API mismatches, rework |
| QA before Dev (TDD) | Test IS the specification | QA after Dev | Tests become rubber-stamps |
| Security + Reviewer last | Can't audit partial code | Security parallel with Dev | False positives/negatives |
| 9 specialized agents | Observability per stage | 1 general agent | Failure diagnosis is archaeology |
| Bash CLI + Python algorithms | Zero CLI deps, algorithms need data structures | All Python | Requires runtime install for CLI |
| .tasuki/ not .claude/ | AI-agnostic framework | .claude/ (original) | Locks to one vendor |
| TASUKI.md not CLAUDE.md | Universal brain file | CLAUDE.md (original) | Platform-specific |
| Two-layer memory | $0 always + deep on-demand | RAG-only | Every query costs tokens |
| Wikilinks as Layer 1 | Zero cost, human-readable | Flat MEMORY.md | Noise after 50 entries |
| SQLite RAG as Layer 2 | Local, $0, <50ms | External vector API | Needs API key, costs $$ |
| MCP-agnostic RAG | Swap backend without touching agents | Hardcoded vector DB | Locked to one provider |
| Max 20 memory entries | Prevent noise | Unlimited entries | Context fills with garbage |
| Mechanical hooks (not advisory) | Exit code 2 can't be ignored | Rules in agent prompt | LLM can ignore rules |
| Pipeline tracker hook | Claude doesn't report willingly | Trust Claude to run commands | Progress stays empty |
| Auto-gitignore | .tasuki/ shouldn't be in repo | Manual gitignore | Users commit agent files |
| Behavioral memory (not hook) | Needs LLM reasoning | PostToolUse hook | Exponential noise |
| No custom pipeline order | Dependencies are designed | User-defined order | Breaks TDD/security |
| BFS graph expansion | O(V+E) follows wikilinks naturally | Nested os.walk per agent | O(n^2), slow at scale |
| Confidence scoring | Not all memories are equal trust | No confidence levels | Agents load deprecated patterns in fast mode |
| Auto-decay on existing commands | No daemons, runs during sync/doctor | Cron-based decay | Requires background process |
| Depth from mode | Fast=shallow, serious=deep | Fixed depth for all modes | Fast loads too much, serious loads too little |
| Hooks in .claude/settings.local.json | Claude Code reads this file | .tasuki/settings.json | Hooks silently ignored |
| force-agent-read hook | Ensures Before You Act runs | Trust agent to self-load | Agents skip memory loading |
| force-planner-first hook | Ensures plans before code | Trust workflow compliance | Direct-to-code, no architecture review |
| Fast mode exempt from Planner | Bug fixes don't need PRDs | Always require Planner | Friction on simple fixes |
| SSE for dashboard updates | Real-time without WebSocket complexity | Polling | Delayed updates or wasted requests |
| Python extracted to standalone files | Algorithms visible and testable | Embedded in bash heredocs | Code invisible to readers and LLMs |
| Keep-both merge for vault sync | Losing memory worse than duplicates | Git merge conflicts | Information lost on conflict |

---

## 19. What's NOT in Tasuki and why

- **No daemon/auto-fix mode:** Evaluated from WatchTower. Too complex, little real use, requires headless LLM execution.
- **No external RAG by default:** Local SQLite via MCP is sufficient. Users can swap to Qdrant/pgvector via Scale 2-3.
- **No OAuth/domain purchasing:** Tasuki is a CLI tool, not a SaaS.
- **No custom pipeline ordering:** Stage order has specific dependencies. Reordering breaks TDD and security.
- **No automatic profile generation:** Would require LLM tokens during onboard (currently $0).
- **No telemetry/analytics:** Zero network requests. Everything local.
- **No WebSocket for dashboard:** SSE is simpler, sufficient for one-way updates, and works without additional libraries.
- **No pre-built graph index:** Current vault size (max 180 files) doesn't justify the complexity. BFS on filesystem completes in <5ms.
- **No cron-based decay:** Auto-decay runs during existing operations (`vault sync`, `doctor`), not as a background daemon. No extra infrastructure needed.
- **No per-agent hook configuration:** All 7 hooks apply to all Edit|Write operations. Per-agent hooks would add complexity without clear benefit — the exemption system handles edge cases.

---

## 20. File inventory

```
135 total files (excluding .git/)
35 engine scripts (src/engine/*.sh)
6  engine Python modules (src/engine/*.py) — graph, decay, seed, sync, pipeline state, hook logger
10 adapters (8 AI tools + base + model-map)
10 agent templates (9 pipeline + onboard)
13 stack profiles + 6 domain profiles
12 skills
7  rules
9  hooks:
  - pipeline-tracker.sh    (PreToolUse: Read|Edit|Write|Bash|Agent|Glob|Grep — tracks stage)
  - tdd-guard.sh           (PreToolUse: Edit|Write — enforces tests-first)
  - security-check.sh      (PreToolUse: Edit|Write — scans for vulnerabilities)
  - protect-files.sh       (PreToolUse: Edit|Write — blocks .env/secrets edits)
  - force-agent-read.sh    (PreToolUse: Edit|Write — ensures agent file loaded)
  - force-planner-first.sh (PreToolUse: Edit|Write — ensures plan exists)
  - pipeline-trigger.sh    (UserPromptSubmit — detects tasks, injects pipeline)
  - teammate-idle.sh       (TeammateIdle — quality gate for Agent Teams)
  - task-completed.sh      (TaskCompleted — validates acceptance criteria for Agent Teams)
5  detectors (backend, frontend, DB, infra, testing)
48 self-tests
36+ CLI commands
```

### Key file paths

| File | Purpose |
|------|---------|
| `.tasuki/config/mode` | Current execution mode (fast/standard/serious) |
| `.tasuki/config/pipeline-progress.json` | Live pipeline state (read by dashboard) |
| `.tasuki/config/pipeline-history.log` | Completed pipeline history (pipe-delimited) |
| `.tasuki/config/tracker-debug.log` | Agent file read log (used by force-agent-read) |
| `.tasuki/config/rag-sync-batch.jsonl` | RAG index entries (one JSON per line) |
| `.tasuki/config/activity-log.json` | Activity timeline (read by dashboard) |
| `.tasuki/config/project-facts.md` | Machine-verified stack facts (read by all agents) |
| `.tasuki/config/capability-map.yaml` | Agent capabilities (read by Planner for routing) |
| `.tasuki/hooks/*.sh` | Installed hook scripts (copied from templates) |
| `.claude/settings.local.json` | Claude Code hook registration (the file CC reads) |
| `memory-vault/` | Knowledge graph (wikilink nodes organized by type) |
| `tasuki-plans/` | Pipeline plans (PRDs, status, decisions per feature) |
| `project-context.md` | Business context from interview (read by Planner) |
