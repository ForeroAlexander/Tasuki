#!/bin/bash
# Tasuki Adapter — Roo Code
# Output: .roo/rules/*.md + .roomodes

generate_config() {
  local project_dir="$1"
  local roo_dir="$project_dir/.roo/rules"
  mkdir -p "$roo_dir"

  log_dim "  Generating .roo/ config..."

  # 1. Rules from stack
  if [ -d "$project_dir/.tasuki/rules" ]; then
    for rule_file in "$project_dir/.tasuki/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      local name
      name=$(basename "$rule_file")
      cp "$rule_file" "$roo_dir/$name"
      log_dim "    rules/$name"
    done
  fi

  # 2. Agent rules
  if [ -d "$project_dir/.tasuki/agents" ]; then
    for agent_file in "$project_dir/.tasuki/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file")
      [ "$name" = "onboard.md" ] && continue
      cp "$agent_file" "$roo_dir/agent-$name"
      log_dim "    rules/agent-$name"
    done
  fi

  # 3. .roomodes — define custom modes from agents
  local modes_file="$project_dir/.roomodes"
  {
    echo "{"
    echo "  \"customModes\": ["

    local first=true
    if [ -d "$project_dir/.tasuki/agents" ]; then
      for agent_file in "$project_dir/.tasuki/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        local name desc
        name=$(basename "$agent_file" .md)
        [ "$name" = "onboard" ] && continue
        desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' | sed 's/"/\\"/g' | cut -c1-100)

        $first || echo ","
        first=false
        echo "    {"
        echo "      \"slug\": \"$name\","
        echo "      \"name\": \"$(echo "$name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')\","
        echo "      \"instructions\": \"$desc\""
        echo -n "    }"
      done
    fi

    echo ""
    echo "  ]"
    echo "}"
  } > "$modes_file"

  log_dim "    .roomodes"
  log_success "  Roo Code: $(find "$roo_dir" -name "*.md" | wc -l) rules + .roomodes"
}

get_adapter_info() {
  echo "roocode|.roo/rules/ + .roomodes|Roo Code"
}
