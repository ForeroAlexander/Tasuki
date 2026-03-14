#!/bin/bash
# Tasuki Engine — Status
# Shows current pipeline configuration for a project.
# Usage: bash status.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

show_status() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  # Check if onboarded
  if [ ! -d "$claude_dir" ] || [ ! -f "$project_dir/TASUKI.md" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki Pipeline Status${NC}"
  echo -e "${DIM}══════════════════════${NC}"
  echo ""

  # Project name (from TASUKI.md first line)
  local project_name
  project_name=$(head -1 "$project_dir/TASUKI.md" | sed 's/^#\s*//')
  echo -e "  ${BOLD}Project:${NC}  $project_name"

  # Current mode (find in TASUKI.md)
  local mode
  mode=$(grep -A1 "Execution Mode:" "$project_dir/TASUKI.md" 2>/dev/null | head -1 | sed 's/.*Mode:\s*//' | tr -d '[:space:]')
  echo -e "  ${BOLD}Mode:${NC}     ${mode:-unknown}"
  echo ""

  # Agents
  echo -e "  ${BOLD}Agents:${NC}"
  if [ -d "$claude_dir/agents" ]; then
    for agent_file in "$claude_dir/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file" .md)
      local desc
      desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' | cut -c1-60)
      echo -e "    ${GREEN}*${NC} $name"
    done
  else
    echo -e "    ${DIM}No agents found${NC}"
  fi
  echo ""

  # Rules
  echo -e "  ${BOLD}Rules:${NC}"
  if [ -d "$claude_dir/rules" ]; then
    for rule_file in "$claude_dir/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      echo -e "    ${BLUE}*${NC} $(basename "$rule_file" .md)"
    done
  else
    echo -e "    ${DIM}No rules found${NC}"
  fi
  echo ""

  # Hooks
  echo -e "  ${BOLD}Hooks:${NC}"
  if [ -d "$claude_dir/hooks" ]; then
    for hook_file in "$claude_dir/hooks"/*.sh; do
      [ -f "$hook_file" ] || continue
      echo -e "    ${YELLOW}*${NC} $(basename "$hook_file")"
    done
  else
    echo -e "    ${DIM}No hooks found${NC}"
  fi
  echo ""

  # Skills
  echo -e "  ${BOLD}Skills:${NC}"
  if [ -d "$claude_dir/skills" ]; then
    for skill_dir in "$claude_dir/skills"/*/; do
      [ -d "$skill_dir" ] || continue
      echo -e "    ${CYAN}*${NC} $(basename "$skill_dir")"
    done
  else
    echo -e "    ${DIM}No skills found${NC}"
  fi
  echo ""

  # MCP Servers
  echo -e "  ${BOLD}MCP Servers:${NC}"
  if [ -f "$project_dir/.mcp.json" ]; then
    if $HAS_JQ; then
      jq -r '.mcpServers | keys[]' "$project_dir/.mcp.json" 2>/dev/null | while read -r server; do
        echo -e "    ${GREEN}*${NC} $server"
      done
    else
      grep -oE '"[a-z0-9_-]+"\s*:\s*\{' "$project_dir/.mcp.json" 2>/dev/null | grep -v mcpServers | sed 's/"\s*:.*//' | sed 's/"//g' | while read -r server; do
        echo -e "    ${GREEN}*${NC} $server"
      done
    fi
  else
    echo -e "    ${DIM}No .mcp.json found${NC}"
  fi
  echo ""

  # Agent memory
  local memory_count=0
  if [ -d "$claude_dir/agent-memory" ]; then
    memory_count=$(find "$claude_dir/agent-memory" -name "MEMORY.md" 2>/dev/null | wc -l)
  fi
  echo -e "  ${BOLD}Memory:${NC}   $memory_count agents with persistent memory"
  echo ""
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  show_status "$@"
fi
