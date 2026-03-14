---
name: tasuki-mode
description: Switch execution mode (fast, standard, serious) or let auto-detection decide.
argument-hint: "[fast|standard|serious|auto]"
allowed-tools: Read, Edit
---

# Tasuki Mode — Execution Mode Switch

Switch the pipeline execution mode to: $ARGUMENTS

## Modes

### fast
- Skip planner (jump straight to implementation)
- QA writes tests inline with implementation
- Security: lightweight grep scan only
- Reviewer: single-pass review, no delegation loops
- Best for: Bug fixes, small tweaks, known patterns

### standard (default)
- Planner: brief analysis + implementation order
- QA: TDD enforced (tests first)
- Security: full OWASP checklist
- Reviewer: full review with delegation
- Best for: Medium features, new endpoints, new pages

### serious
- Planner: full architecture plan with data model + API design
- QA: TDD enforced + E2E tests
- Security: full audit with automated scanning tools
- Reviewer: full review, max 3 rounds, escalate unresolved
- Best for: New modules, architecture changes, security-sensitive features

### auto
- Analyze the next task's complexity and choose the appropriate mode
- Score 1-3 → fast, Score 4-6 → standard, Score 7-10 → serious

## Action

1. Read `TASUKI.md`
2. Find the `## Execution Mode` section
3. Update the mode value to `$ARGUMENTS`
4. Confirm: "Mode switched to **{mode}**. Pipeline behavior updated."
