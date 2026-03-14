#!/bin/bash
# Tasuki Adapter — OpenAI Codex CLI
# Output: AGENTS.md + .codex/skills/

generate_config() {
  local project_dir="$1"
  local codex_dir="$project_dir/.codex"
  mkdir -p "$codex_dir/skills"

  log_dim "  Generating Codex config..."

  # 1. AGENTS.md — main instruction file (Codex reads this)
  generate_agents_md "$project_dir"

  # 2. Skills directory
  if [ -d "$project_dir/.tasuki/skills" ]; then
    for skill_dir in "$project_dir/.tasuki/skills"/*/; do
      [ -d "$skill_dir" ] || continue
      local name
      name=$(basename "$skill_dir")
      if [ -f "$skill_dir/SKILL.md" ]; then
        mkdir -p "$codex_dir/skills/$name"
        cp "$skill_dir/SKILL.md" "$codex_dir/skills/$name/SKILL.md"
        log_dim "    skills/$name"
      fi
    done
  fi

  log_success "  Codex: AGENTS.md + $(find "$codex_dir/skills" -name "*.md" 2>/dev/null | wc -l) skills"
}

generate_agents_md() {
  local project_dir="$1"
  local output="$project_dir/AGENTS.md"

  {
    if [ -f "$project_dir/TASUKI.md" ]; then
      # Convert TASUKI.md to AGENTS.md format
      sed 's/Claude Code/Codex/g; s/\.claude\//\.codex\//g' "$project_dir/TASUKI.md"
    else
      echo "# Project Agents"
      echo ""
      echo "This project uses Tasuki multi-agent orchestration."
    fi

    echo ""
    echo "---"
    echo ""
    echo "## Available Agents"
    echo ""

    if [ -d "$project_dir/.tasuki/agents" ]; then
      for agent_file in "$project_dir/.tasuki/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        local name desc
        name=$(basename "$agent_file" .md)
        [ "$name" = "onboard" ] && continue
        desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' | cut -c1-80)
        echo "- **$name**: $desc"
      done
    fi
  } > "$output"

  log_dim "    AGENTS.md"
}

get_adapter_info() {
  echo "codex|AGENTS.md + .codex/skills/|OpenAI Codex CLI"
}
