# Contributing to Tasuki

## Project Structure

```
bin/tasuki                  CLI entry point
src/
├── engine/                 Core scripts (bash)
├── adapters/               AI tool adapters (1 per tool)
├── detectors/              Stack detection (bash, outputs JSON)
├── profiles/               Stack conventions (YAML)
├── templates/
│   ├── agents/             Agent templates (.md with frontmatter)
│   ├── rules/              Convention rules (.md)
│   ├── hooks/              Pre-edit hooks (.sh)
│   ├── skills/             Skill definitions (.md)
│   ├── TASUKI.md           Brain file template
│   └── settings.json       Permissions template
├── plugins.yaml            Plugin catalog
├── stacks.yaml             Scaffolding templates
└── registry.yaml           Agent registry + execution modes
```

## Adding a New Stack Profile

1. Create `src/profiles/{lang}-{framework}.yaml`
2. Follow the structure of `python-fastapi.yaml`:
   ```yaml
   stack:
     backend:
       lang: python
       framework: fastapi
       run_cmd: "python3"

     conventions:
       routing: [...]
       models: [...]
       migrations: [...]
       testing: [...]
       docker: [...]

     security_checks:
       python:
         - pattern: 'regex'
           issue: "description"
           fix: "how to fix"

     tools:
       test_runner: "pytest"
       linter: "ruff"
       migration_cmd: "alembic"

     mcp_suggestions: [...]
   ```
3. Update the backend detector if the framework isn't detected yet
4. Run tests: `bash tests/test-tasuki.sh`

## Adding a New AI Tool Adapter

1. Create `src/adapters/{tool}.sh`
2. Implement two functions:
   ```bash
   generate_config() {
     local project_dir="$1"
     # Read from .tasuki/ and generate tool-specific output
   }

   get_adapter_info() {
     echo "tool-name|output-format|Tool Display Name"
   }
   ```
3. Add to `ALL_TARGETS` in `src/adapters/base.sh`
4. Add model mappings in `src/adapters/models.yaml`
5. Add CLI dispatch in `bin/tasuki`
6. Run tests

## Adding a New Agent

1. Create `src/templates/agents/{name}.md`
2. Required frontmatter:
   ```yaml
   ---
   name: agent-name
   description: What this agent does
   tools: Read, Write, Edit, Glob, Grep, Bash
   model: sonnet  # or opus for thinking agents
   memory: project
   domains: [domain1, domain2]
   triggers: [keyword1, keyword2]
   priority: 5  # pipeline order (1=first)
   activation: conditional  # or always/reactive
   stack_required: backend  # optional
   ---
   ```
3. Required sections in the body:
   - `## Your Position in the Pipeline`
   - `## Before You Act (MANDATORY)`
   - `## Not Your Job — Delegate Instead`
   - `## Handoff`
4. The agent will be auto-discovered by the capability map

## Adding a New Skill

1. Create `src/templates/skills/{name}/SKILL.md`
2. Frontmatter:
   ```yaml
   ---
   name: skill-name
   description: What this skill does
   allowed-tools: Read, Write, Edit, Glob, Grep, Bash
   ---
   ```
3. Add to `render_skills()` in `src/engine/render.sh` if it should auto-install

## Adding a New Hook

1. Create `src/templates/hooks/{name}.sh`
2. Must exit 0 (allow) or 2 (block with message)
3. Add to `render_hooks()` in `src/engine/render.sh`
4. Add to `settings.json` template in the hooks section

## Running Tests

```bash
bash tests/test-tasuki.sh
# 35 tests covering: CLI, detectors, onboard, facts, agents,
# hooks, TDD guard, vault, score, validate, adapters
```

## Code Style

- Bash scripts with `set -euo pipefail` for core scripts
- `set +e` for scripts that do heavy grepping (may return 1 on no match)
- Use `common.sh` for shared utilities (colors, logging, JSON helpers)
- All scripts must be executable (`chmod +x`)

## Commit Messages

```
feat: description          # new feature
fix: description           # bug fix
refactor: description      # restructuring
docs: description          # documentation
chore: description         # maintenance
```
