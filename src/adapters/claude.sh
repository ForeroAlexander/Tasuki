#!/bin/bash
# Tasuki Adapter — Claude Code
# Claude Code expects CLAUDE.md with Agent(subagent_type="X") calls

generate_config() {
  local project_dir="$1"

  if [ -f "$project_dir/TASUKI.md" ]; then
    # Copy TASUKI.md as CLAUDE.md with Claude-specific translations
    sed \
      -e 's/→ \*\*Invoke: \([a-z-]*\) agent\*\*/```\nAgent(subagent_type="\1")\n```/g' \
      -e 's/invoke the \*\*\([a-z-]*\)\*\* agent/`Agent(subagent_type="\1")`/g' \
      -e 's/Invoke \([a-z-]*\) agent with:/Agent(subagent_type="\1", prompt=/g' \
      "$project_dir/TASUKI.md" > "$project_dir/CLAUDE.md"
    log_dim "  CLAUDE.md (from TASUKI.md with Agent() calls)"
  fi
}

get_adapter_info() {
  echo "claude|CLAUDE.md + .tasuki/ + .mcp.json|Claude Code"
}
