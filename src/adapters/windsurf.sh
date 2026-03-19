#!/bin/bash
# Tasuki Adapter — Windsurf
# Output: .windsurfrules (single file at project root)

generate_config() {
  local project_dir="$1"
  local output="$project_dir/.windsurfrules"

  log_dim "  Generating .windsurfrules..."

  {
    if [ -f "$project_dir/TASUKI.md" ]; then
      sed 's/Claude Code/Windsurf/g; s/\.claude\///g' "$project_dir/TASUKI.md"
    fi

    echo ""
    echo "---"
    echo ""

    # Append all rules inline
    if [ -d "$project_dir/.tasuki/rules" ]; then
      for rule_file in "$project_dir/.tasuki/rules"/*.md; do
        [ -f "$rule_file" ] || continue
        echo ""
        sed -n '/^---$/,/^---$/!p' "$rule_file" | tail -n +1
        echo ""
      done
    fi

    # Append agent instructions
    if [ -d "$project_dir/.tasuki/agents" ]; then
      echo ""
      echo "## Agent Roles"
      echo ""
      for agent_file in "$project_dir/.tasuki/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        local name
        name=$(basename "$agent_file" .md)
        [ "$name" = "onboard" ] && continue
        local desc
        desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//')
        echo "- **$name**: $desc"
      done
    fi
  } > "$output"

  translate_tasuki_paths "windsurf" "$output"

  log_success "  Windsurf: .windsurfrules ($(wc -l < "$output") lines)"
}

get_adapter_info() {
  echo "windsurf|.windsurfrules|Windsurf Editor"
}
