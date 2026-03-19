#!/bin/bash
# Tasuki Adapter — OpenAI Codex CLI
# Output: AGENTS.md

generate_config() {
  local project_dir="$1"

  log_dim "  Generating Codex config..."

  # AGENTS.md — main instruction file (Codex reads this from project root)
  generate_agents_md "$project_dir"

  log_success "  Codex: AGENTS.md generated"
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

  translate_tasuki_paths "codex" "$output"

  log_dim "    AGENTS.md"
}

get_adapter_info() {
  echo "codex|AGENTS.md|OpenAI Codex CLI"
}
