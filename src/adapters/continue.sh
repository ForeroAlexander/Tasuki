#!/bin/bash
# Tasuki Adapter — Continue
# Output: .continue/rules/*.md with YAML frontmatter (name, globs, alwaysApply)

generate_config() {
  local project_dir="$1"
  local continue_dir="$project_dir/.continue/rules"
  mkdir -p "$continue_dir"

  log_dim "  Generating .continue/rules/..."

  local idx=1

  # 1. Main project rule (always apply)
  if [ -f "$project_dir/TASUKI.md" ]; then
    local main_rule="$continue_dir/$(printf '%02d' $idx)-project.md"
    {
      echo "---"
      echo "name: Project Conventions"
      echo "globs: \"**/*\""
      echo "alwaysApply: true"
      echo "---"
      echo ""
      sed 's/Claude Code/Continue/g; s/\.claude\//\.continue\//g' "$project_dir/TASUKI.md"
    } > "$main_rule"
    log_dim "    $(printf '%02d' $idx)-project.md"
    idx=$((idx + 1))
  fi

  # 2. Stack rules
  if [ -d "$project_dir/.tasuki/rules" ]; then
    for rule_file in "$project_dir/.tasuki/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      local name
      name=$(basename "$rule_file" .md)

      local globs
      globs=$(grep -A20 "^paths:" "$rule_file" 2>/dev/null | grep '^\s*-' | head -1 | sed 's/^\s*-\s*//' | sed 's/"//g' || echo "**/*")

      local continue_rule="$continue_dir/$(printf '%02d' $idx)-${name}.md"
      {
        echo "---"
        echo "name: \"${name} conventions\""
        echo "globs: \"$globs\""
        echo "alwaysApply: true"
        echo "---"
        echo ""
        sed -n '/^---$/,/^---$/!p' "$rule_file" | tail -n +1
      } > "$continue_rule"

      log_dim "    $(printf '%02d' $idx)-$name.md"
      idx=$((idx + 1))
    done
  fi

  # 3. Agent rules (on-demand, not always apply)
  if [ -d "$project_dir/.tasuki/agents" ]; then
    for agent_file in "$project_dir/.tasuki/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file" .md)
      [ "$name" = "onboard" ] && continue

      local desc
      desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' | cut -c1-80)

      local continue_rule="$continue_dir/$(printf '%02d' $idx)-agent-${name}.md"
      {
        echo "---"
        echo "name: \"Agent: $name\""
        echo "globs: \"**/*\""
        echo "alwaysApply: false"
        echo "description: \"$desc\""
        echo "---"
        echo ""
        sed -n '/^---$/,/^---$/!p' "$agent_file" | tail -n +1
      } > "$continue_rule"

      log_dim "    $(printf '%02d' $idx)-agent-$name.md"
      idx=$((idx + 1))
    done
  fi

  log_success "  Continue: $(find "$continue_dir" -name "*.md" | wc -l) rule files"
}

get_adapter_info() {
  echo "continue|.continue/rules/*.md|Continue Dev"
}
