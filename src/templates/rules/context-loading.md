---
paths:
  - "**/*"
---

# Context Loading Protocol (ALL AGENTS)

## Before ANY task, load context in this order:

### 1. Project Facts (MANDATORY — always read first)
```
.tasuki/config/project-facts.md
```
Verified facts: stack, versions, paths, commands.
If something here contradicts your assumptions, **trust the facts file**.

### 1b. Project Context (PLANNER ONLY)
```
.tasuki/config/project-context.md
```
Business context: what the project does, domain, users, deploy target.
**Only the Planner reads this.** Other agents receive business context through the Planner's task instructions via Taskmaster.

### 2. Error Memory (MANDATORY — check before acting)
```
memory-vault/errors/
```
These are mistakes that were made before. Each one says "DO NOT: ..."
If your planned action matches a recorded error, **stop and reconsider**.

### 3. Domain Heuristics (load only yours)
```
memory-vault/heuristics/
```
Only read heuristics that reference YOUR agent name via [[wikilink]].
Don't load heuristics for other agents — that wastes tokens.

### 4. Context Summary (if available)
```
.tasuki/config/context-summary.md
```
Compressed project overview. Only read sections relevant to your domain.
- Backend agent → read Schema + API sections
- Frontend agent → read Frontend Routes + Components sections
- QA → read API + Schema sections

### 5. Source Files (only when needed)
Read specific source files ONLY when you need implementation details.
Never read "all models" or "all routers" — read the specific one you're changing.

## Anti-Hallucination Rules
- NEVER guess a file path — verify it exists with Glob first
- NEVER assume a dependency version — read package.json or requirements.txt
- NEVER assume an API endpoint exists — read the router file
- NEVER assume a database column exists — read the model or use Postgres MCP
- If you're not sure about something, READ THE FILE. Don't guess.
