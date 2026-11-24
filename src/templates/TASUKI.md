# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quick Reference
- Backend: `{{BACKEND_PATH}}` ({{BACKEND_FRAMEWORK}}, {{BACKEND_LANG}})
- Frontend: `{{FRONTEND_PATH}}` ({{FRONTEND_FRAMEWORK}})
- Run: `{{RUN_CMD}}`
- Migrations: {{MIGRATION_CONVENTION}}
- Docker: `{{DOCKER_COMPOSE_PATH}}`
- DB: {{DB_ENGINE}} ({{DB_CREDENTIALS_REF}})

## Pipeline

**Read `.tasuki/agents/planner.md` for full pipeline instructions.** It is the authoritative source.

Current mode: **{{CURRENT_MODE}}**

{{MODE_BEHAVIOR}}

## Progress Tracking
```bash
tasuki progress start "TASK" {{CURRENT_MODE}}     # Stage 1 only
tasuki progress update . N "STAGE_NAME" running   # Start of each stage
tasuki progress update . N "STAGE_NAME" done      # End of each stage
tasuki progress complete .                         # After final stage
```

## Spawn Pattern (Claude Code Agent Teams)

The Planner compiles a brief for each agent before spawning. The brief contains everything the agent needs — no file reads required to start work.

```
Agent(
  prompt="""
ROLE: {agent-name}
STACK: {lang}/{framework}, {db}, {test-runner}
PROJECT: {{PROJECT_DIR}}
KEY PATHS: {only paths this agent touches}

TASK: {specific, unambiguous description}
ACCEPTANCE CRITERIA:
- {criterion 1}
- {criterion 2}

CONSTRAINTS: {only constraints relevant to this agent}
INPUTS: {file paths from previous stages — not summaries}

Reference: .tasuki/agents/{name}.md — read only if you need pattern examples.
""",
  model="{model}"
)
```

Models: planner/reviewer/security → `opus` | all others → `sonnet`

Brief size target: ~100 tokens (small) · ~200 tokens (medium) · ~300 tokens (standard). Over 400 = over-explaining.

## Context Between Stages
The Planner reads shared context once and compiles per-agent briefs. Do NOT pass full PRDs in prompts — pass the path: `tasuki-plans/{feature}/prd.md`.

## Hooks (auto-enforced on every file edit)
{{HOOKS_LIST}}

## Rules
{{RULES_LIST}}

## Skills
| Skill | Command | Purpose |
|-------|---------|---------|
{{SKILLS_TABLE}}

## MCP Servers
| MCP | Purpose | Used By |
|-----|---------|---------|
{{MCP_TABLE}}
