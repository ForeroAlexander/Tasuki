---
name: memory-vault
description: Write structured memory notes to the knowledge graph. Every agent uses this to record bugs, lessons, heuristics, and decisions as individual nodes with [[wikilinks]] to create a navigable graph. Two memory types -- heuristic (permanent rules) and episodic (specific events).
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Memory Vault — Knowledge Graph Writer

Record knowledge as structured nodes in `memory-vault/`. Each note is a node, [[wikilinks]] are edges.

## Two Memory Types

### Heuristic Memory (permanent rules)
**What**: General rules learned from experience. Apply ALWAYS, regardless of context.
**Where**: `memory-vault/heuristics/`
**Lifespan**: Permanent — never expires
**Example**: "Always index lookup columns" — this is true forever.

### Episodic Memory (specific events)
**What**: Specific incidents with date, context, root cause, and fix. Searchable by similarity.
**Where**: `memory-vault/bugs/` and `memory-vault/lessons/`
**Lifespan**: Long — but context-dependent (may not apply if stack changes)
**Example**: "2026-03-14: Deploy failed because migration had no downgrade()"

## When to Write Memory

### After fixing a bug → write a Bug node
```markdown
# {Descriptive Bug Name}

Type: Bug
Created: {date}
Severity: {CRITICAL|HIGH|MEDIUM|LOW}

## Agent
[[{agent-that-found-it}]]

## Stack
[[{technology}]]

## Symptoms
{What was observed — error messages, user reports, log entries}

## Root Cause
{Why it happened — the actual underlying issue}

## Fix
{What was done to resolve it — file:line references}

## Prevention
{What to do to prevent this from happening again}

## Related Heuristic
[[{heuristic-slug-if-exists}]]
```

### After learning something → write a Lesson node
```markdown
# Lesson: {What Was Learned}

Type: Lesson
Created: {date}

## Agent
[[{agent-that-learned}]]

## Context
{What were you doing when you learned this}

## Insight
{The key takeaway — what would you tell your past self}

## Rule
{If this becomes a pattern, promote to a Heuristic}

## Related
- [[{related-bug}]]
- [[{related-decision}]]
```

### After discovering a pattern → write a Heuristic node
```markdown
# {Rule Name}

Type: Heuristic
Severity: {CRITICAL|HIGH|MEDIUM}

## Applies To
- [[{agent-1}]]
- [[{agent-2}]]

## Rule
{The rule stated clearly in one sentence}

## Reason
{Why this rule exists — what goes wrong if you violate it}

## Anti-Pattern
{Code example of what NOT to do}

## Correct Pattern
{Code example of the right way}

## Related
- [[{related-bug}]]
- [[{related-lesson}]]
```

### After making a technical decision → write a Decision node
```markdown
# Decision: {What Was Decided}

Type: Decision
Created: {date}
Status: {accepted|superseded|deprecated}

## Context
{What was the situation? Why did a decision need to be made?}

## Options Considered
1. **{Option A}** — {pros/cons}
2. **{Option B}** — {pros/cons}

## Decision
{What was chosen and why}

## Consequences
- {positive consequence}
- {negative consequence / tradeoff}

## Related
- [[{related-architecture-node}]]
- [[{related-agent}]]
```

### After designing architecture → write an Architecture node
```markdown
# {Pattern/Component Name}

Type: Architecture
Created: {date}

## Overview
{What is this architectural component/pattern}

## Components
- [[{component-1}]]
- [[{component-2}]]

## Data Flow
{How data moves through this component}

## Decisions
- [[{decision-that-led-to-this}]]

## Constraints
{Performance, security, scalability requirements}
```

## Wikilink Rules

1. **Always link to agents**: `[[backend-dev]]`, `[[qa]]`, `[[security]]`
2. **Always link to stack**: `[[postgres]]`, `[[fastapi]]`, `[[docker]]`
3. **Always link related nodes**: bug → heuristic, lesson → bug, decision → architecture
4. **Use kebab-case**: `[[always-index-lookup-columns]]`, not `[[Always Index Lookup Columns]]`
5. **Create links even if target doesn't exist yet** — they'll resolve when the target is created

## Promoting Episodic → Heuristic

When you see the SAME lesson or bug pattern 2+ times:
1. Create a Heuristic node that captures the general rule
2. Link the original Bug/Lesson nodes to the new Heuristic
3. The heuristic becomes a permanent rule that all agents follow

Example flow:
```
Bug: missing-db-index-users → caused full table scan
Bug: missing-db-index-orders → same pattern
  ↓ (pattern detected)
Heuristic: always-index-lookup-columns → general rule
  ↑ linked from both bugs
```

## Anti-Bloat Rules (CRITICAL)

Without limits, memory becomes noise. These rules are NON-NEGOTIABLE:

1. **Max 20 entries per node type per agent.** When full, remove the oldest LOW-value entry before adding.
2. **No duplicating TASUKI.md.** If the info is already in TASUKI.md or agent instructions, don't repeat it in memory.
3. **One entry per insight.** Don't batch multiple learnings into one node.
4. **Only write when there's a real insight.** "The fix worked" is NOT a learning. "The fix required 3 rounds because advisory_lock doesn't rollback on exception" IS a learning.

**Without the 20-entry limit:** In 6 months, each agent would have 200+ entries. The LLM context fills with noise, valuable insights get buried, and token cost grows linearly.

## 4-Dimension Format (for all entries)

Every memory entry MUST use this format — proven in production:

```markdown
## {date} — {Short description}
**Pattern**: {The insight — what you learned, not the symptom}
**Evidence**: `{file:line}` — {what was observed}
**Scope**: {Where else this applies — which modules, files, patterns}
**Prevention**: {Grep pattern, rule, config check, or convention to add}
```

**Why 4 dimensions:**
- **Pattern** = the knowledge (reusable)
- **Evidence** = proof it's real (not hallucinated)
- **Scope** = where to apply it (beyond the original case)
- **Prevention** = how to catch it next time (actionable)

Example:
```markdown
## 2026-03-14 — Advisory lock doesn't rollback on exception
**Pattern**: Python context managers with advisory locks don't auto-rollback if an exception occurs inside the block
**Evidence**: `app/services/billing.py:142` — duplicate charges when payment webhook timed out
**Scope**: Any service using `with advisory_lock(key):` — billing, sync, export
**Prevention**: grep -rn "advisory_lock" app/services/ — verify each has explicit try/except with rollback
```

## Trigger Conditions (when to write)

Don't write memory after every task. Only write when:

| Trigger | Example |
|---------|---------|
| Root cause was non-obvious (>2 investigation steps) | "Took 3 rounds to find the real cause" |
| A fix introduced a regression | "First fix broke auth, had to redo" |
| Discovered a pattern that applies elsewhere | "Same bug could exist in 4 other files" |
| A convention violation was caught by Reviewer | "Was using raw dicts instead of Pydantic" |
| A security finding was new (not in OWASP checklist) | "CSV injection via exported filenames" |
| An estimation was significantly off | "Planned 2 files, actually touched 8" |
