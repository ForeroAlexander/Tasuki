---
name: hotfix
description: Create a hotfix branch, apply the fix, run tests, and prepare for merge.
argument-hint: "[issue description]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Hotfix — Quick Fix Workflow

Hotfix for: $ARGUMENTS

## Steps

1. Create branch: `git checkout -b hotfix/{description}`
2. Find and fix the issue (minimal change only — no refactoring)
3. Run related tests
4. Commit: `git commit -m "fix: {description}"`
5. Report:
   - What broke
   - Root cause
   - What changed
   - What tests verify the fix
