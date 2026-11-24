#!/bin/bash
# Tasuki Adapter — Base
# Defines the interface that all AI tool adapters must implement.
# Each adapter translates Tasuki's universal config into the target AI tool's format.
#
# Adapter registry:
#   claude     → .tasuki/ + TASUKI.md + .mcp.json
#   cursor     → .cursor/rules/ + .cursorrules
#   codex      → .codex/ + AGENTS.md
#   copilot    → .github/copilot-instructions.md + .github/instructions/
#   continue   → .continue/rules/
#   windsurf   → .windsurfrules
#   roocode    → .roo/ + .roomodes
#   gemini     → GEMINI.md
#   all        → generates for all supported targets

ADAPTERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of all supported targets
ALL_TARGETS=("claude" "cursor" "codex" "copilot" "continue" "windsurf" "roocode" "gemini")

# Get the output directory for a target
get_target_dir() {
  local target="$1"
  case "$target" in
    claude)   echo ".tasuki" ;;
    cursor)   echo ".cursor" ;;
    codex)    echo ".codex" ;;
    copilot)  echo ".github" ;;
    continue) echo ".continue" ;;
    windsurf) echo "" ;;  # uses root files
    roocode)  echo ".roo" ;;
    gemini)   echo "" ;;  # uses root files
  esac
}

# Check if a target is valid
is_valid_target() {
  local target="$1"
  for t in "${ALL_TARGETS[@]}"; do
    [ "$t" = "$target" ] && return 0
  done
  [ "$target" = "all" ] && return 0
  return 1
}

# Source "brain" file for non-Claude targets.
# TASUKI.md in a Claude project uses Agent Teams spawn syntax, which other tools
# cannot execute. Onboard also renders a role-switching copy; prefer it when present.
brain_file() {
  local project_dir="$1"
  local legacy="$project_dir/.tasuki/config/TASUKI-legacy.md"
  if [ -f "$legacy" ]; then
    echo "$legacy"
  else
    echo "$project_dir/TASUKI.md"
  fi
}

# Print one markdown bullet per agent with the model the target platform should use.
# Usage: list_agents_with_models <target> <project_dir> [desc_max_chars]
list_agents_with_models() {
  local target="$1" project_dir="$2" max="${3:-200}"
  local agent_file name desc tier model
  [ -d "$project_dir/.tasuki/agents" ] || return 0
  for agent_file in "$project_dir/.tasuki/agents"/*.md; do
    [ -f "$agent_file" ] || continue
    name=$(basename "$agent_file" .md)
    [ "$name" = "onboard" ] && continue
    desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:[[:space:]]*//' | cut -c1-"$max")
    tier=$(grep "^model:" "$agent_file" 2>/dev/null | head -1 | sed 's/^model:[[:space:]]*//' | tr -d ' ')
    model="$tier"
    if declare -F translate_model >/dev/null; then
      model=$(translate_model "$target" "${tier:-sonnet}")
    fi
    echo "- **$name** (model: ${model:-default}): $desc"
  done
}

# Run adapter for a specific target
# Translate .tasuki/ paths and Claude-specific references in generated content
# Called by adapters after copying agent/rule content to target format
translate_tasuki_paths() {
  local target="$1"
  local file="$2"

  [ -f "$file" ] || return

  local target_dir
  target_dir=$(get_target_dir "$target")

  # Translate .tasuki/agents/ references to the target's agent location
  # and .tasuki/ paths to the target's config directory
  case "$target" in
    cursor)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|.cursor/rules/\1.md|g' \
        -e 's|\.tasuki/rules/|.cursor/rules/stack-|g' \
        -e 's|\.tasuki/config/|.cursor/|g' \
        -e 's|CLAUDE\.md|.cursorrules|g' \
        -e 's|Claude Code|Cursor|g' \
        "$file"
      ;;
    codex)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|AGENTS.md (section: \1)|g' \
        -e 's|CLAUDE\.md|AGENTS.md|g' \
        -e 's|Claude Code|Codex|g' \
        "$file"
      ;;
    copilot)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|.github/instructions/\1.instructions.md|g' \
        -e 's|CLAUDE\.md|.github/copilot-instructions.md|g' \
        -e 's|Claude Code|GitHub Copilot|g' \
        "$file"
      ;;
    continue)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|.continue/rules/agent-\1.md|g' \
        -e 's|\.tasuki/rules/|.continue/rules/|g' \
        -e 's|Claude Code|Continue|g' \
        "$file"
      ;;
    windsurf)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|.windsurfrules (section: \1)|g' \
        -e 's|CLAUDE\.md|.windsurfrules|g' \
        -e 's|Claude Code|Windsurf|g' \
        "$file"
      ;;
    roocode)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|.roo/rules/agent-\1.md|g' \
        -e 's|\.tasuki/rules/|.roo/rules/|g' \
        -e 's|Claude Code|Roo Code|g' \
        "$file"
      ;;
    gemini)
      sed -i \
        -e 's|\.tasuki/agents/\([a-z-]*\)\.md|GEMINI.md (section: \1)|g' \
        -e 's|CLAUDE\.md|GEMINI.md|g' \
        -e 's|Claude Code|Gemini|g' \
        "$file"
      ;;
  esac

  # Universal: warn about hooks (only Claude enforces them mechanically)
  # Add a note if the file references hooks
  if grep -q '\.tasuki/hooks/' "$file" 2>/dev/null; then
    sed -i 's|\.tasuki/hooks/\([a-z-]*\)\.sh|.tasuki/hooks/\1.sh (Note: hooks only run in Claude Code)|g' "$file"
  fi
}

run_adapter() {
  local target="$1"
  local project_dir="$2"

  if [ "$target" = "all" ]; then
    for t in "${ALL_TARGETS[@]}"; do
      echo -e "${CYAN}[$t]${NC}"
      source "$ADAPTERS_DIR/${t}.sh"
      generate_config "$project_dir"
      echo ""
    done
  else
    source "$ADAPTERS_DIR/${target}.sh"
    generate_config "$project_dir"
  fi
}
