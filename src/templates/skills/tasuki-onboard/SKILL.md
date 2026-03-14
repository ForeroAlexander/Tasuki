---
name: tasuki-onboard
description: Scan a codebase, detect the stack, and auto-generate a complete .tasuki/ configuration with agents, rules, hooks, skills, and TASUKI.md.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Tasuki Onboard — Project Discovery & Configuration

Run the full onboarding pipeline for the current project.

## Step 1: SCAN — Detect the stack

Run each detection script and capture the JSON output:

```bash
bash tasuki/src/detectors/detect-backend.sh .
bash tasuki/src/detectors/detect-frontend.sh .
bash tasuki/src/detectors/detect-database.sh .
bash tasuki/src/detectors/detect-infra.sh .
bash tasuki/src/detectors/detect-testing.sh .
```

Collect the results into a detection summary.

## Step 2: ANALYZE — Match against profiles

1. Read `tasuki/src/profiles/` to find the best-fit stack profile
2. Read `tasuki/src/registry.yaml` to determine which agents to activate
3. Decide which agents to skip based on `stack_required` fields:
   - No frontend detected? Skip `frontend-dev`
   - No database detected? Skip `db-architect`
   - No Docker detected? Simplify `devops`
   - Always include: `planner`, `qa`, `security`, `reviewer`

## Step 3: ANALYZE — Study the codebase

Read ~10-15 key files to understand project-specific conventions:
- Entry point (main.py, app.ts, etc.)
- 2-3 existing route/controller files (to learn patterns)
- 1-2 model/schema files
- Auth middleware or dependency
- Existing test files (to learn test patterns)
- Docker/compose files
- CI/CD config

Extract:
- Project name
- Project description
- File path conventions
- Auth pattern
- Coding conventions not in the profile

## Step 4: GENERATE — Write configuration

Using the templates from `tasuki/src/templates/` and the profile conventions:

1. **`.tasuki/agents/*.md`** — One file per activated agent, populated with project context
2. **`.tasuki/rules/*.md`** — One file per detected file type, with project conventions
3. **`.tasuki/hooks/protect-files.sh`** — Copy from template, optionally customize
4. **`.tasuki/hooks/security-check.sh`** — Copy from template
5. **`.tasuki/settings.json`** — Generate permissions for detected paths + tools
6. **`.mcp.json`** — Suggest MCP servers based on profile
7. **`TASUKI.md`** — The complete orchestration brain, using the TASUKI.md template

Replace all `{{PLACEHOLDER}}` values in templates with actual project values.

## Step 5: VERIFY

1. Read back all generated files
2. Check that agent names in TASUKI.md match agent files
3. Check that rule paths match actual project structure
4. Present a summary:

```
Tasuki Onboarding Complete
==========================

Project: {name}
Stack: {backend} + {frontend} + {database}

Agents activated (N/9):
  [x] planner
  [x] qa
  [x] db-architect
  [x] backend-dev
  [ ] frontend-dev (skipped: no frontend detected)
  [x] security
  [x] reviewer
  [x] devops

Rules: {list}
Hooks: protect-files, security-check
Skills: {list}
MCP Servers: {list}

Ready to test? Try: "Plan a small feature to verify the pipeline"
```
