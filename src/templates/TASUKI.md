# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quick Reference
- Backend: `{{BACKEND_PATH}}` ({{BACKEND_FRAMEWORK}}, {{BACKEND_LANG}})
- Frontend: `{{FRONTEND_PATH}}` ({{FRONTEND_FRAMEWORK}})
- Run: `{{RUN_CMD}}`
- Migrations: {{MIGRATION_CONVENTION}}
- Docker: `{{DOCKER_COMPOSE_PATH}}`
- DB: {{DB_ENGINE}} ({{DB_CREDENTIALS_REF}})

## CRITICAL: Pipeline Execution Protocol

**When you receive ANY feature request, bug report, or task — you MUST execute the pipeline below automatically. Do NOT just write code directly. Follow the stages in order.**

### How It Works

1. You receive a prompt from the user
2. You execute **each stage sequentially** by switching roles
3. For each stage: read the agent's instructions at `.tasuki/agents/{name}.md`, adopt that role, execute
4. **Verify between stages**: after any implementation stage, run tests. If they fail → Debugger
5. You do NOT stop between stages unless explicitly told to
6. The pipeline runs until Reviewer approves or the user interrupts
7. After completion, show a summary of everything that was done

### How to Invoke an Agent (works in ANY AI tool)

**You MUST read `.tasuki/agents/{agent-name}.md` before executing each stage. No exceptions. Do NOT skip reading the file even if you think you know what to do — each agent has specific checklists, memory to load, and delegation rules you will miss.**

For each stage:
1. **Read the agent file** (e.g., `Read .tasuki/agents/planner.md`) — this is MANDATORY, not optional
2. Adopt that agent's role, expertise, and rules
3. Follow its "Before You Act" section (load memory from vault)
4. Execute the task according to its instructions
5. Produce the Handoff block for the next stage
6. Move to the next stage

This works in Claude Code, Cursor, Codex, Copilot, Windsurf, Continue, Roo Code, Gemini — any tool that reads markdown instructions.

### Context Between Stages (via Taskmaster MCP)

**DO NOT pass the full PRD between agents.** That wastes tokens.

Use Taskmaster MCP as the shared task board:
1. **Planner** creates the PRD → saves to `tasuki-plans/` → pushes tasks to Taskmaster
2. **Each agent** queries Taskmaster for only ITS task (~50 tokens vs ~2000 for full PRD)
3. **Each agent** marks its task complete when done

### Execution Mode: {{CURRENT_MODE}}

{{MODE_BEHAVIOR}}

---

## THE PIPELINE (execute in this exact order)

### IMPORTANT: Report Progress
**At the START of each stage, run this bash command** so the dashboard and terminal track your progress:
```bash
tasuki progress start "TASK_DESCRIPTION" {{CURRENT_MODE}}   # Only at Stage 1
tasuki progress update . STAGE_NUM "STAGE_NAME" running      # At start of each stage
tasuki progress update . STAGE_NUM "STAGE_NAME" done         # When stage completes
tasuki progress complete .                                    # After Stage 9
```
This is NOT optional. Without it, the dashboard stays empty.

### Stage 1: PLANNER → Architecture & PRD
```bash
tasuki progress start "$(echo $USER_TASK | head -c 80)" {{CURRENT_MODE}}
tasuki progress update . 1 "Planner" running
```
→ **Read `.tasuki/agents/planner.md` first, then execute as Planner agent**
**Tools:** Taskmaster MCP, Context7 MCP
**Skills:** /tasuki-plans
**Input:** The user's request
**Output:**
  1. PRD saved to `tasuki-plans/{feature}/prd.md`
  2. Implementation plan with agent-specific instructions (not generic)
  3. Tasks pushed to Taskmaster MCP — one task per agent with acceptance criteria
**After planning, ALWAYS show:**
```
Plan saved to:
  → tasuki-plans/{feature}/prd.md
  → tasuki-plans/{feature}/plan.md
  → tasuki-plans/{feature}/status.md
```
**User checkpoint — MANDATORY, DO NOT SKIP:** After showing the plan summary and saved files, you MUST stop and ask the user: "Continue with implementation? (yes/no)". Wait for their response. Do NOT proceed to Stage 2 until the user explicitly says yes. This is the human's approval gate — no code is written without it.
**Skip when:** Simple bug fix, typo, single-file change — route directly to Dev
```bash
tasuki progress update . 1 "Planner" done
```

### Stage 1b: TASKMASTER → Parse PRD into Tasks
Taskmaster MCP parses the Planner's PRD and creates structured tasks:
- One task per agent (qa, db-architect, backend-dev, frontend-dev, devops)
- Each task has: description, dependencies, acceptance criteria
- Agents query Taskmaster for THEIR task only (~50 tokens vs ~2000 for full PRD)

### Stage 2: QA → Tests FIRST (TDD)
```bash
tasuki progress update . 2 "QA" running
```
→ **Read `.tasuki/agents/qa.md` first, then execute as QA agent**
**Tools:** Playwright MCP (for E2E), Context7 MCP
**Input:** Reads its task from Taskmaster (NOT the full PRD)
**Output:** Failing test files (RED phase — tests that define expected behavior)
**Rule:** Tests MUST fail. If they pass, they're not testing new behavior.
**Skip when:** No testable changes, documentation-only
```bash
tasuki progress update . 2 "QA" done
```

### Stage 3: DB ARCHITECT → Schema & Migrations
```bash
tasuki progress update . 3 "DB-Architect" running
```
→ **Read `.tasuki/agents/db-architect.md` first, then execute as DB Architect agent**
**Tools:** Postgres MCP (inspect live schema), Context7 MCP
**Input:** Reads its task from Taskmaster + tests from QA
**Output:** Migration files + model updates
**Rule:** Migration must be idempotent and reversible. Use EXPLAIN ANALYZE via Postgres MCP.
**Skip when:** No schema changes needed
```bash
tasuki progress update . 3 "DB-Architect" done
```

### Stage 4: BACKEND DEV → Implementation
```bash
tasuki progress update . 4 "Backend-Dev" running
```
→ **Read `.tasuki/agents/backend-dev.md` first, then execute as Backend Dev agent**
**Tools:** Context7 MCP, Postgres MCP, Sentry MCP
**Input:** Reads its task from Taskmaster + failing tests + tables from DBA
**Output:** Code that makes the tests PASS (GREEN phase)
**Rule:** Run tests after implementing. ALL tests must pass. Check Sentry for related errors.
**Skip when:** No backend changes
```bash
tasuki progress update . 4 "Backend-Dev" done
```

### ⚡ TEST CHECKPOINT (after Stage 4)
```bash
{{TEST_COMMAND}}
```
- **All pass?** → Continue to Stage 5
- **Any fail?** → Invoke Debugger (Stage 5.5)
- **Do NOT proceed to Frontend with failing backend tests**

### Stage 5: FRONTEND DEV → Design + Implementation
```bash
tasuki progress update . 5 "Frontend-Dev" running
```
→ **Read `.tasuki/agents/frontend-dev.md` first, then execute as Frontend Dev agent**
**Tools:** Stitch MCP, Figma MCP, Playwright MCP, Context7 MCP
**Skills:** /ui-design, /ui-ux-pro-max
**Input:** Reads its task from Taskmaster + working API endpoints

**Step 5a: DESIGN REFERENCE (before writing code)**
  Ask the user: "Do you have an existing design to reference?"

  **Option A — Figma:** "Yes, I have a Figma file"
    → Use **Figma MCP** to pull the design specs (colors, typography, spacing, layout)
    → Show the user what was extracted: "I'll build this with these specs. Correct?"

  **Option B — Stitch:** "No, generate a design"
    → Use **Stitch MCP** to generate a visual preview based on the plan
    → Show the preview to the user: "Does this design look right? Any changes?"
    → If changes → adjust → re-show → until approved

  **Option C — Skip:** "Just build it, I'll adjust later"
    → Proceed directly to implementation using project's design system

**Step 5b: Implementation**
  - Use **/ui-ux-pro-max** skill for design intelligence (styles, palettes, fonts)
  - Use **/ui-design** skill for accessibility and responsive patterns
  - Build pages, components, stores
  - All states: loading, error, empty, success

**Output:** Complete, accessible, responsive UI that matches the approved design
**Rule:** Backend FIRST, Frontend SECOND. Never in parallel.
**Skip when:** No frontend changes
```bash
tasuki progress update . 5 "Frontend-Dev" done
```

### ⚡ TEST CHECKPOINT (after Stage 5)
```bash
{{TEST_COMMAND}}
```
- **All pass?** → Continue to Security
- **Any fail?** → Invoke Debugger below

### Stage 5.5: DEBUGGER → Only if tests fail
→ **Read `.tasuki/agents/debugger.md` first, then execute as Debugger agent**
**Tools:** Sentry MCP, Postgres MCP, Context7 MCP
**Activation:** ONLY if tests fail at any checkpoint
**Input:** Failing tests + error output
**Output:** Root cause diagnosis
**Flow:**
  1. Check **Sentry MCP** for related error events
  2. Diagnose root cause (read logs, trace code, check DB state via Postgres MCP)
  3. Delegate fix to the right agent (backend-dev, frontend-dev, db-architect)
  4. Re-run tests
  5. If still failing → repeat (max 3 rounds, then ask user)
  6. If passing → continue pipeline

### Stage 6: SECURITY → OWASP Audit
```bash
tasuki progress update . 6 "Security" running
```
→ **Read `.tasuki/agents/security.md` first, then execute as Security agent**
**Tools:** Semgrep MCP, Sentry MCP, Postgres MCP (verify RLS)
**Input:** All code from previous stages (reads from files, not from prompt)
**Output:** Security audit report with findings by severity
**Flow:**
  1. Run **Semgrep MCP** for static analysis
  2. Walk OWASP Top 10 checklist against actual code
  3. Check **Postgres MCP** for RLS policies and unencrypted columns
  4. Compile findings: CRITICAL > HIGH > MEDIUM > LOW
  5. Delegate CRITICAL/HIGH fixes to appropriate agent
  6. Re-scan after fixes (max 3 rounds)
**Rule:** ALWAYS runs. No exceptions.
```bash
tasuki progress update . 6 "Security" done
```

### Stage 7: REVIEWER → Quality Gate (with fix loop)
```bash
tasuki progress update . 7 "Reviewer" running
```
→ **Read `.tasuki/agents/reviewer.md` first, then execute as Reviewer agent**
**Tools:** Semgrep MCP, Context7 MCP, Postgres MCP
**Input:** Changed files + security audit report (reads from files)
**Output:** APPROVE or REQUEST CHANGES

**The Review Loop (max 3 rounds):**
```
Round 1: Review all changed files → find issues → delegate fixes
         Agent fixes → returns
Round 2: Re-review fixed files + files that IMPORT them (regression check)
         New issues? → delegate. Same issue? → re-delegate with clearer instructions.
Round 3: Final review
         Clean? → APPROVE
         Still broken? → REQUEST CHANGES (escalate to user)
```

**Flow:**
  1. Read the plan from `tasuki-plans/{feature}/plan.md`
  2. Read ALL changed files (not just the diff)
  3. Cross-reference: models ↔ routes ↔ schemas ↔ tests ↔ migrations
  4. Run **Semgrep MCP** for patterns the eye might miss
  5. Verify tests cover every new endpoint/feature
  6. Output findings by severity with round tracking: "→ FIXED by backend-dev (round 1) ✓"
  7. After each fix: check for REGRESSIONS in files that import the fixed file
  8. Produce **Handoff block** for the next stage

**Exit conditions:**
  - All CRITICAL + WARNING resolved → **APPROVE**
  - CRITICAL unresolved after 3 rounds → **REQUEST CHANGES** (never approve)
  - Only SUGGESTIONs remaining → **APPROVE** with notes

**Rule:** Nothing ships without APPROVE. NEVER approve with unresolved CRITICALs.
```bash
tasuki progress update . 7 "Reviewer" done
```

### Stage 8: DEVOPS → Deploy (if applicable)
```bash
tasuki progress update . 8 "DevOps" running
```
→ **Read `.tasuki/agents/devops.md` first, then execute as DevOps agent**
**Tools:** GitHub MCP, Sentry MCP, Context7 MCP
**Input:** Approved code (reads from files)
**Output:** Updated Docker config, CI/CD, deployment
**Flow:**
  1. Update Dockerfile/docker-compose if needed
  2. Update CI/CD pipeline if new tests or services
  3. Deploy (or prepare deploy command for user)
  4. Run health checks via **Sentry MCP** after deploy
**Skip when:** No infrastructure changes
```bash
tasuki progress update . 8 "DevOps" done
```

### Stage 9: COMPLETION → Summary + Memory (MANDATORY)
After Reviewer APPROVED, you MUST do both of these:

**9a. Show the summary:**
```
Pipeline Complete ✓
═══════════════════

Feature: {feature name}
Mode: {fast/standard/serious}
Stages run: {list of stages that actually executed}

Files created:
  {list of new files}

Files modified:
  {list of modified files}

Tests:
  ✓ {X} tests passing
  {X} new tests written by QA

Security:
  {PASS/FAIL} — {X} findings resolved

Reviewer: APPROVED

Next steps:
  {any manual steps — env vars, migrations, docker restart}
```

**9b. Write to memory vault (two-layer memory):**
Only if there was a real insight. Don't write "task completed" — that's noise.

**Layer 1 — Wikilinks (fast index, always loaded by agents):**
Write a short .md file in `memory-vault/` with `[[wikilinks]]` to relevant agents.

Write IF:
- Root cause was non-obvious → `memory-vault/bugs/`
- Discovered a reusable pattern → `memory-vault/heuristics/`
- A fix introduced a regression → `memory-vault/lessons/`
- Made an architectural decision → `memory-vault/decisions/`

Format (4-dimension, ~4 lines):
```markdown
## {date} — {Short description}
**Pattern**: {The insight}
**Evidence**: `{file:line}` — {what was observed}
**Scope**: {Where else this applies}
**Prevention**: {How to catch it next time}
```

**Layer 2 — RAG Deep Memory (on-demand, queried via MCP):**
If the insight has rich context (incident timeline, full diff, discussion), also store it via the RAG Memory MCP for deep retrieval. Agents can query this when the wikilink summary isn't enough.

Use RAG Memory MCP to store: full incident details, code diffs, related tickets, timeline.
Agents query RAG when: they read a wikilink and need more context than the 4-line summary provides.

**9c. Update plan status:**
Edit `tasuki-plans/{feature}/status.md` → mark completed stages.
Mark tasks complete in Taskmaster MCP.
```bash
tasuki progress complete .
```

---

## Pipeline Resilience

### If the pipeline crashes or session ends mid-execution

**Before starting any pipeline, check if there's a feature in progress:**
```
Read tasuki-plans/index.md → look for status = "in-progress"
If found → Read tasuki-plans/{feature}/status.md
         → Check which stages are marked [x] (completed)
         → Skip those stages, continue from the first [ ] (pending)
```

This means: if the user says "continue" or starts a new session, the pipeline picks up where it left off instead of restarting from Stage 1.

**Update status.md after EACH stage completes** (not just at Stage 9):
```markdown
- [x] Planning complete
- [x] Tests written (QA)
- [x] Database migration (db-architect)
- [ ] Backend implementation (backend-dev)     ← resume from here
- [ ] Frontend implementation (frontend-dev)
- [ ] Security audit (security)
- [ ] Code review (reviewer)
- [ ] Deployed (devops)
```

### If the Reviewer rejects after 3 rounds
Verdict = REQUEST CHANGES. The pipeline STOPS. The user sees:
- What CRITICALs remain unresolved
- Which agents tried to fix and failed
- What the user needs to decide

The user can: fix manually, give more context, or re-run the pipeline with adjusted instructions.

### If Security finds a CRITICAL
Security delegates the fix. If the fix fails after 3 rounds:
- Security verdict = FAIL
- Reviewer sees FAIL → blocks APPROVE
- Pipeline STOPS with clear report of what's vulnerable and why

---

## Pipeline Flow Diagram

```
User Prompt
     ↓
[1] Planner → PRD + Plan
     ↓
   "Continue?" ←── User confirms
     ↓
[2] QA → Tests FIRST (must FAIL — RED phase)
     ↓
[3] DB Architect → Migration (if schema needed)
     ↓
[4] Backend Dev → Implementation (GREEN phase)
     ↓
   ⚡ TEST CHECKPOINT ←── run tests
     ├── PASS → continue
     └── FAIL → [5.5] Debugger → fix → re-test
     ↓
[5] Frontend Dev → UI (if needed)
     ↓
   ⚡ TEST CHECKPOINT ←── run full suite
     ├── PASS → continue
     └── FAIL → [5.5] Debugger → fix → re-test
     ↓
[6] Security → OWASP audit
     ├── PASS → continue
     └── FAIL → delegate fix → re-scan (max 3 rounds)
     ↓
[7] Reviewer → Quality gate
     ├── APPROVE → continue
     └── REQUEST CHANGES → delegate fix → re-review (max 3 rounds)
     ↓
[8] DevOps → Deploy (if needed)
     ↓
[9] Summary + Memory → show results, save to vault
     ↓
   DONE ✓
```

## Cost Awareness (opt-in)

**Only show cost estimates if** `.tasuki/config/notifications.json` exists with `"cost_warning": true`, or if the user explicitly asks "how much will this cost?"

When enabled:
```
Estimated pipeline: {N} agents, ~{X}K tokens, ~${cost} USD
Mode: {fast/standard/serious}
Continue? (Enter=yes)
```
This is informational, not blocking. Disabled by default to avoid friction.

## Pipeline Rules (NON-NEGOTIABLE)

1. **Sequential**: Each stage completes BEFORE the next starts. No parallelism.
2. **Build order**: Backend FIRST, Frontend SECOND. The API is the contract.
3. **TDD mandatory**: Tests exist BEFORE implementation. The tdd-guard hook enforces this.
4. **Security always runs**: No exceptions, ever.
5. **Reviewer is the gate**: Nothing ships without APPROVE.
6. **Reviewer loops**: If issues found → delegate fix → re-review → repeat until clean.
7. **Debugger is reactive**: Only activates when tests fail. Not in the normal flow.
8. **User can override**: "Hey Dev, just build X" bypasses the pipeline for direct agent access.
9. **Each agent stays in scope**: "Not Your Job" sections are hard boundaries. Agents delegate, never cross lanes.
10. **Memory after completion**: After the pipeline finishes, record lessons/errors in memory-vault.

## Context Loading (before each agent runs)

Each agent MUST read these before acting:
1. `.tasuki/config/project-facts.md` — verified stack, versions, paths (~200 tokens)
2. `memory-vault/errors/` — mistakes to avoid
3. `memory-vault/heuristics/` — rules that apply to this agent (filtered by [[wikilink]])

Do NOT load all files. Load only what the current agent needs.

## Hooks (mechanical enforcement — runs on EVERY file edit)

These hooks run automatically via settings.json. You cannot bypass them.

{{HOOKS_LIST}}

**How hooks interact with the pipeline:**
- **tdd-guard**: Blocks Stage 4 (Backend Dev) and Stage 5 (Frontend Dev) from writing implementation code if tests don't exist yet. This MECHANICALLY enforces TDD — it's not a suggestion.
- **security-check**: Blocks ALL stages from writing SQL injection, eval(), hardcoded secrets. Catches issues BEFORE Security even runs.
- **protect-files**: Blocks ALL stages from editing .env, secrets/, lock files.

If a hook blocks your edit, **don't work around it**. Fix the underlying issue:
- tdd-guard blocked? → Write the test first (or ask QA to write it)
- security-check blocked? → Fix the insecure pattern
- protect-files blocked? → You shouldn't be editing that file

## Rules (`.tasuki/rules/` — conventions loaded per file type)

These rules are loaded automatically when you edit files matching their glob patterns.

{{RULES_LIST}}

**Key rule: `context-loading.md`** — applies to ALL files. Tells every agent to read project-facts.md and memory-vault before acting.

## Skills (`.tasuki/skills/` — invoke with /skill-name)

| Skill | Command | Purpose | When to Use |
|-------|---------|---------|-------------|
{{SKILLS_TABLE}}

**Pipeline-connected skills:**
- **/tasuki-plans** — Planner uses this in Stage 1 to persist PRDs
- **/memory-vault** — All agents use this in Stage 9 to record learnings
- **/context-compress** — Generates compressed project summary for token optimization
- **/ui-design** + **/ui-ux-pro-max** — Frontend Dev uses these in Stage 5 for design intelligence

**Utility skills (manual use):**
- **/hotfix** — Create hotfix branch outside the normal pipeline
- **/test-endpoint** — Quick API testing
- **/db-migrate** — Run migration commands
- **/deploy-check** — Health check all services

## MCP Servers (`.mcp.json` — external tools agents can call)

| MCP | Transport | Purpose | Used By |
|-----|-----------|---------|---------|
{{MCP_TABLE}}

**Pipeline-connected MCPs:**
- **Taskmaster** — Stage 1b: Planner pushes tasks, agents query their task
- **Semgrep** — Stage 6: Security runs static analysis
- **Sentry** — Stage 5.5 (Debugger) + Stage 6 (Security) + Stage 8 (DevOps health check)
- **Postgres** — Stage 3 (DBA schema inspection) + Stage 5.5 (Debugger data check)
- **Figma/Stitch** — Stage 5a: Frontend design preview before coding
- **Playwright** — Stage 2 (QA E2E tests) + Stage 5 (Frontend visual testing)
- **Context7** — ALL stages: up-to-date framework documentation
