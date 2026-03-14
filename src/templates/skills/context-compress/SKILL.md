---
name: context-compress
description: Generate and maintain compressed context summaries of the project. Used by agents to load minimal context instead of reading full files. Saves tokens and reduces latency.
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Context Compression — Project Summary Generator

Generate compact summaries of the project's key files so agents can load minimal context instead of reading entire files.

## When to Run

- After onboarding a new project
- After significant code changes (new models, new routers, schema changes)
- When `tasuki learn` runs
- Manually: `/context-compress`

## What It Generates

Creates `.tasuki/config/context-summary.md` with compressed representations of:

### 1. Schema Summary
Read all model files, extract: table names, columns, relationships, indexes.
Output a compact table, not full source code.

```markdown
## Schema
| Table | Key Columns | Relationships | Indexes |
|-------|-------------|---------------|---------|
| users | id, email, name, role, tenant_id, deleted_at | has_many: orders, posts | email(unique), tenant_id |
| orders | id, user_id, status, total, created_at | belongs_to: user | user_id, status, created_at |
```

### 2. API Summary
Read all router/controller files, extract: method, path, auth, description.

```markdown
## API Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | none | Health check |
| POST | /auth/login | none | Login, returns JWT |
| GET | /api/users | jwt | List users (paginated) |
| POST | /api/orders | jwt+role:admin | Create order |
```

### 3. Component Summary (frontend)
Read pages/components, extract: route, purpose, key props.

```markdown
## Frontend Routes
| Route | Component | Data Source | States |
|-------|-----------|-------------|--------|
| / | HomePage | server load | loading, error |
| /dashboard | Dashboard | client fetch | loading, error, empty |
| /orders/:id | OrderDetail | server load | loading, error, 404 |
```

### 4. Infrastructure Summary
```markdown
## Infrastructure
- Docker services: api (8000), db (5432), redis (6379)
- CI/CD: GitHub Actions (lint → test → build → deploy)
- Deploy target: docker compose
- Env vars: 12 required (see .env.example)
```

### 5. Dependency Summary
```markdown
## Dependencies
- Backend: fastapi, sqlalchemy, alembic, pyjwt, httpx (7 total)
- Frontend: svelte, sveltekit, tailwindcss (12 total)
- Dev: pytest, ruff, vitest (5 total)
```

## Output File

Write to `.tasuki/config/context-summary.md`:

```markdown
# Project Context — {{PROJECT_NAME}}
Last updated: {date}

{all sections above}
```

## How Agents Use This

Instead of reading 15 files to understand the project, agents read ONE file:
```
.tasuki/config/context-summary.md    # ~50 lines vs ~500 lines of source
```

This is especially useful for:
- **Planner**: needs project overview, not implementation details
- **Security**: needs API surface area, not business logic
- **Reviewer**: needs schema + API summary to cross-reference
- **New agents**: installed plugins get instant project understanding
