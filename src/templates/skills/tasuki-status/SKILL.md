---
name: tasuki-status
description: Show current Tasuki pipeline configuration — active agents, mode, rules, hooks, MCP servers.
allowed-tools: Read, Glob, Bash
---

# Tasuki Status — Pipeline Configuration Report

Show the current state of the Tasuki pipeline.

## Steps

1. Read `TASUKI.md` and extract:
   - Project name
   - Current execution mode
   - Pipeline stages table

2. List active agents:
   ```bash
   ls .tasuki/agents/*.md 2>/dev/null
   ```

3. List active rules:
   ```bash
   ls .tasuki/rules/*.md 2>/dev/null
   ```

4. List active hooks:
   ```bash
   ls .tasuki/hooks/*.sh 2>/dev/null
   ```

5. List available skills:
   ```bash
   ls .tasuki/skills/*/SKILL.md 2>/dev/null
   ```

6. Check MCP servers:
   ```bash
   cat .mcp.json 2>/dev/null | jq -r '.mcpServers | keys[]'
   ```

7. Check agent memory:
   ```bash
   ls .tasuki/agent-memory/*/MEMORY.md 2>/dev/null
   ```

## Output

```
Tasuki Pipeline Status
======================

Project:  {name}
Mode:     {current_mode}

Agents ({count}/9):
  {list with status}

Rules:    {list}
Hooks:    {list}
Skills:   {list}
MCP:      {list}
Memory:   {count} agents with persistent memory
```
