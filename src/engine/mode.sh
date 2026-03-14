#!/bin/bash
# Tasuki Engine — Mode Switch
# Changes the execution mode in a project's TASUKI.md.
# Usage: bash mode.sh [fast|standard|serious|auto] [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

switch_mode() {
  local mode="${1:-}"
  local project_dir="${2:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_md="$project_dir/TASUKI.md"

  # Validate mode
  case "$mode" in
    fast|standard|serious|auto) ;;
    "")
      log_error "Usage: tasuki mode <fast|standard|serious|auto>"
      echo ""
      echo "  fast     — Bug fixes, small tweaks. Skip planner, lightweight security."
      echo "  standard — Medium features. Full pipeline with TDD. (default)"
      echo "  serious  — Architecture changes. All agents at full power, 3 reviewer rounds."
      echo "  auto     — System decides based on task complexity."
      exit 1
      ;;
    *)
      log_error "Invalid mode: $mode"
      log_error "Valid modes: fast, standard, serious, auto"
      exit 1
      ;;
  esac

  # Check if onboarded
  if [ ! -f "$claude_md" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  # Define mode behavior descriptions
  local mode_behavior=""
  case "$mode" in
    fast)
      mode_behavior="Quick mode: Skip planner, lightweight security scan, single reviewer pass. Best for bug fixes and small tweaks."
      ;;
    standard)
      mode_behavior="Full pipeline with TDD enforcement. Sonnet for implementation, Opus for planning and review."
      ;;
    serious)
      mode_behavior="Full pipeline at maximum rigor. All agents use Opus. Full OWASP audit with tools. 3 reviewer rounds. Best for architecture changes and security-sensitive features."
      ;;
    auto)
      mode_behavior="Auto mode: The system will analyze each task's complexity and choose fast (score 1-3), standard (4-6), or serious (7-10) automatically."
      ;;
  esac

  # Update the Execution Mode line in TASUKI.md
  if grep -q "### Execution Mode:" "$claude_md" 2>/dev/null; then
    sed -i "s|### Execution Mode:.*|### Execution Mode: $mode|" "$claude_md"
  elif grep -q "Execution Mode:" "$claude_md" 2>/dev/null; then
    sed -i "s|Execution Mode:.*|Execution Mode: $mode|" "$claude_md"
  else
    log_warn "Could not find 'Execution Mode' section in TASUKI.md. Adding it."
    # Insert after the "Agent Orchestration Pipeline" header
    sed -i "/## Agent Orchestration Pipeline/a\\\\n### Execution Mode: $mode" "$claude_md"
  fi

  # Update the mode behavior description
  # Find the line after "Execution Mode:" and replace the next non-empty line
  local temp_file
  temp_file=$(mktemp)
  local found_mode=false
  local replaced=false

  while IFS= read -r line; do
    echo "$line" >> "$temp_file"
    if echo "$line" | grep -q "Execution Mode:"; then
      found_mode=true
      replaced=false
      continue
    fi
    if $found_mode && ! $replaced; then
      if [ -n "$line" ] && ! echo "$line" | grep -qE '^#'; then
        # Replace this line with the new behavior description
        sed -i "$ s|.*|$mode_behavior|" "$temp_file"
        replaced=true
        found_mode=false
      fi
    fi
  done < "$claude_md"

  mv "$temp_file" "$claude_md"

  # Persist mode for other tools (vault expand, dashboard, etc.)
  mkdir -p "$project_dir/.tasuki/config"
  echo "$mode" > "$project_dir/.tasuki/config/mode"

  echo ""
  log_success "Mode switched to: ${BOLD}$mode${NC}"
  echo ""
  echo -e "  $mode_behavior"
  echo ""
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  switch_mode "$@"
fi
