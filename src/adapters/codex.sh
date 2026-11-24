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
    if [ -f "$(brain_file "$project_dir")" ]; then
      # Convert TASUKI.md to AGENTS.md format
      sed 's/Claude Code/Codex/g; s/\.claude\//\.codex\//g' "$(brain_file "$project_dir")"
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

    list_agents_with_models "codex" "$project_dir" 80
  } > "$output"

  translate_tasuki_paths "codex" "$output"

  log_dim "    AGENTS.md"
}

get_adapter_info() {
  echo "codex|AGENTS.md|OpenAI Codex CLI"
}
