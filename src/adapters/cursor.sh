#!/bin/bash
# Tasuki Adapter — Cursor
# Output: .cursor/rules/*.md + .cursorrules
# Cursor uses .cursor/rules/ directory with markdown files that have
# YAML frontmatter (globs, alwaysApply, description).

generate_config() {
  local project_dir="$1"
  local cursor_dir="$project_dir/.cursor/rules"
  mkdir -p "$cursor_dir"

  log_dim "  Generating .cursor/rules/..."

  # 1. Main project rules file (.cursorrules at root)
  generate_cursorrules "$project_dir"

  # 2. Agent rules as individual rule files
  if [ -d "$project_dir/.tasuki/agents" ]; then
    for agent_file in "$project_dir/.tasuki/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file" .md)
      [ "$name" = "onboard" ] && continue

      # Extract description and domains from frontmatter
      local desc domains
      desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//')
      domains=$(grep "^domains:" "$agent_file" 2>/dev/null | head -1 | sed 's/^domains:\s*//')

      # Convert agent to Cursor rule format
      local rule_file="$cursor_dir/${name}.md"
      {
        echo "---"
        echo "description: \"$desc\""
        echo "globs: \"**/*\""
        echo "alwaysApply: false"
        echo "---"
        echo ""
        # Strip the YAML frontmatter from the agent and use the body
        sed -n '/^---$/,/^---$/!p' "$agent_file" | tail -n +1
      } > "$rule_file"

      log_dim "    rules/$name.md"
    done
  fi

  # 3. Stack-specific rules from .tasuki/rules/
  if [ -d "$project_dir/.tasuki/rules" ]; then
    for rule_file in "$project_dir/.tasuki/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      local name
      name=$(basename "$rule_file" .md)

      # Convert paths frontmatter to globs
      local globs
      globs=$(grep -A20 "^paths:" "$rule_file" 2>/dev/null | grep '^\s*-' | head -1 | sed 's/^\s*-\s*//' | sed 's/"//g' || echo "**/*")

      local cursor_rule="$cursor_dir/stack-${name}.md"
      {
        echo "---"
        echo "description: \"${name} conventions\""
        echo "globs: \"$globs\""
        echo "alwaysApply: true"
        echo "---"
        echo ""
        sed -n '/^---$/,/^---$/!p' "$rule_file" | tail -n +1
      } > "$cursor_rule"

      log_dim "    rules/stack-$name.md"
    done
  fi

  log_success "  Cursor: $(find "$cursor_dir" -name "*.md" | wc -l) rule files generated"
}

generate_cursorrules() {
  local project_dir="$1"
  local output="$project_dir/.cursorrules"

  if [ -f "$project_dir/TASUKI.md" ]; then
    # Convert TASUKI.md to .cursorrules (strip Claude-specific references)
    sed 's/Claude Code/Cursor/g; s/\.claude\//\.cursor\//g; s/CLAUDE\.md/.cursorrules/g' \
      "$project_dir/TASUKI.md" > "$output"
    log_dim "    .cursorrules (from TASUKI.md)"
  fi
}

get_adapter_info() {
  echo "cursor|.cursor/rules/ + .cursorrules|Cursor AI Editor"
}
