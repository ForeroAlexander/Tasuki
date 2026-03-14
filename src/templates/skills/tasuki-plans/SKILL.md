---
name: tasuki-plans
description: View, search, and manage the plan history. Lists all PRDs and implementation plans, shows status, and provides a summary of what's been planned, in progress, or completed.
allowed-tools: Read, Glob, Grep, Bash, Edit
---

# Tasuki Plans — Plan History Manager

View and manage the history of all plans created by the Planner agent.

## Actions

### List all plans (default)

Read `tasuki-plans/index.md` and present a formatted table:

```
Feature          Status        Created     PRD   Plan
─────────────────────────────────────────────────────
alert-reminders  in-progress   2026-03-14  ✓     ✓
user-profiles    planned       2026-03-13  ✓     ✓
auth-system      done          2026-03-10  ✓     ✓
```

If no arguments provided, show this list.

### View a specific plan

If the user provides a feature name (e.g., `/tasuki-plans alert-reminders`):

1. Read `tasuki-plans/{slug}/prd.md` — show the PRD
2. Read `tasuki-plans/{slug}/plan.md` — show the implementation plan
3. Read `tasuki-plans/{slug}/status.md` — show current progress

### Update status

If the user says "update status" or "mark X as done":

1. Edit `tasuki-plans/{slug}/status.md` — update the status and checkboxes
2. Edit `tasuki-plans/index.md` — update the status column

### Search plans

If the user asks "find plans about X":

```bash
grep -rl "search term" tasuki-plans/ --include="*.md" 2>/dev/null
```

## Notes
- Plans are created by the **Planner agent** automatically
- Each plan has: PRD (what), Plan (how), Status (progress)
- The index is the single source of truth for all plans
- Plans are never deleted — they serve as project history
