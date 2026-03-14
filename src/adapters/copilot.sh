#!/bin/bash
# Tasuki Adapter — GitHub Copilot
# Output: .github/copilot-instructions.md + .github/instructions/*.instructions.md

generate_config() {
  local project_dir="$1"
  local github_dir="$project_dir/.github/instructions"
  mkdir -p "$github_dir"

  log_dim "  Generating GitHub Copilot config..."

  # 1. Main instructions file
  local main_file="$project_dir/.github/copilot-instructions.md"
  if [ -f "$project_dir/TASUKI.md" ]; then
    sed 's/Claude Code/GitHub Copilot/g; s/\.claude\//\.github\//g' \
      "$project_dir/TASUKI.md" > "$main_file"
    log_dim "    copilot-instructions.md"
  fi

  # 2. Path-specific instructions from rules
  if [ -d "$project_dir/.tasuki/rules" ]; then
    for rule_file in "$project_dir/.tasuki/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      local name
      name=$(basename "$rule_file" .md)

      local globs
      globs=$(grep -A20 "^paths:" "$rule_file" 2>/dev/null | grep '^\s*-' | head -1 | sed 's/^\s*-\s*//' | sed 's/"//g' || echo "**/*")

      local inst_file="$github_dir/${name}.instructions.md"
      {
        echo "---"
        echo "applyTo: \"$globs\""
        echo "---"
        echo ""
        sed -n '/^---$/,/^---$/!p' "$rule_file" | tail -n +1
      } > "$inst_file"

      log_dim "    instructions/$name.instructions.md"
    done
  fi

  # 3. AGENTS.md for Copilot agent mode
  if [ ! -f "$project_dir/.github/AGENTS.md" ]; then
    if [ -f "$project_dir/TASUKI.md" ]; then
      cp "$project_dir/TASUKI.md" "$project_dir/.github/AGENTS.md"
      log_dim "    .github/AGENTS.md"
    fi
  fi

  log_success "  Copilot: instructions + $(find "$github_dir" -name "*.md" 2>/dev/null | wc -l) path rules"
}

get_adapter_info() {
  echo "copilot|.github/copilot-instructions.md|GitHub Copilot"
}
