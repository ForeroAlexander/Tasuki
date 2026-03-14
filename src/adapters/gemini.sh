#!/bin/bash
# Tasuki Adapter — Gemini CLI
# Output: GEMINI.md (root file, similar to TASUKI.md)

generate_config() {
  local project_dir="$1"
  local output="$project_dir/GEMINI.md"

  log_dim "  Generating GEMINI.md..."

  if [ -f "$project_dir/TASUKI.md" ]; then
    # Convert TASUKI.md to GEMINI.md
    sed 's/Claude Code/Gemini/g; s/CLAUDE\.md/GEMINI.md/g; s/\.claude\//\.gemini\//g' \
      "$project_dir/TASUKI.md" > "$output"
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

    if [ -d "$project_dir/.tasuki/agents" ]; then
      for agent_file in "$project_dir/.tasuki/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        local name desc
        name=$(basename "$agent_file" .md)
        [ "$name" = "onboard" ] && continue
        desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' | cut -c1-80)
        echo "### $name"
        echo "$desc"
        echo ""
      done
    fi
  } >> "$output"

  log_success "  Gemini: GEMINI.md ($(wc -l < "$output") lines)"
}

get_adapter_info() {
  echo "gemini|GEMINI.md|Google Gemini CLI"
}
