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

# Run adapter for a specific target
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
