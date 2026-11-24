#!/bin/bash
# Tasuki Adapter — Gemini CLI
# Output: GEMINI.md (root file, similar to TASUKI.md)

generate_config() {
  local project_dir="$1"
  local output="$project_dir/GEMINI.md"

  log_dim "  Generating GEMINI.md..."

  if [ -f "$(brain_file "$project_dir")" ]; then
    # Convert TASUKI.md to GEMINI.md
    sed 's/Claude Code/Gemini/g; s/CLAUDE\.md/GEMINI.md/g; s/\.claude\//\.gemini\//g' \
      "$(brain_file "$project_dir")" > "$output"
  else
    echo "# Project Configuration for Gemini" > "$output"
    echo "" >> "$output"
    echo "This project uses Tasuki multi-agent orchestration." >> "$output"
  fi

  # Append agent summaries
  {
    echo ""
    echo "---"
    echo ""
    echo "## Available Agents"
    echo ""

    list_agents_with_models "gemini" "$project_dir" 80
  } >> "$output"

  translate_tasuki_paths "gemini" "$output"

  log_success "  Gemini: GEMINI.md ($(wc -l < "$output") lines)"
}

get_adapter_info() {
  echo "gemini|GEMINI.md|Google Gemini CLI"
}
