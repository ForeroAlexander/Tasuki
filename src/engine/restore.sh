#!/bin/bash
# Tasuki Engine — Restore
# Brings back agents, skills, or rules that were removed.
# Re-copies from Tasuki templates.
#
# Usage: bash restore.sh [/path/to/project] [--all]
#   --all: restore everything without asking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

restore_interactive() {
  local project_dir="${1:-.}"
  local auto_all="${2:-false}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  if [ ! -d "$claude_dir" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki Restore${NC}"
  echo -e "${DIM}══════════════${NC}"
  echo ""

  # Find what's missing compared to templates
  local items=()
  local item_types=()   # "agent" | "skill" | "rule"
  local item_names=()

  # Check agents
  for template in "$TASUKI_TEMPLATES/agents"/*.md; do
    [ -f "$template" ] || continue
    local name
    name=$(basename "$template" .md)
    [ "$name" = "onboard" ] && continue
    if [ ! -f "$claude_dir/agents/$name.md" ]; then
      items+=("$name ${DIM}(agent)${NC}")
      item_types+=("agent")
      item_names+=("$name")
    fi
  done

  # Check skills
  for template_dir in "$TASUKI_TEMPLATES/skills"/*/; do
    [ -d "$template_dir" ] || continue
    local name
    name=$(basename "$template_dir")
    if [ ! -d "$claude_dir/skills/$name" ]; then
      items+=("$name ${DIM}(skill)${NC}")
      item_types+=("skill")
      item_names+=("$name")
    fi
  done

  # Check rules
  for template in "$TASUKI_TEMPLATES/rules"/*.md; do
    [ -f "$template" ] || continue
    local name
    name=$(basename "$template")
    if [ ! -f "$claude_dir/rules/$name" ]; then
      items+=("$name ${DIM}(rule)${NC}")
      item_types+=("rule")
      item_names+=("$name")
    fi
  done

  if [ ${#items[@]} -eq 0 ]; then
    echo -e "  ${GREEN}Nothing to restore — all components are installed.${NC}"
    echo ""
    return 0
  fi

  echo -e "  ${BOLD}Components available to restore:${NC}"
  echo ""
  local i
  for i in $(seq 0 $((${#items[@]} - 1))); do
    echo -e "    ${CYAN}$((i + 1)).${NC} ${items[$i]}"
  done
  echo ""

  if [ "$auto_all" = "true" ] || [ "$auto_all" = "--all" ]; then
    local restored=0
    for i in $(seq 0 $((${#items[@]} - 1))); do
      do_restore "${item_types[$i]}" "${item_names[$i]}" "$claude_dir"
      restored=$((restored + 1))
    done
    echo ""
    log_success "Restored $restored components."
    echo ""
    return 0
  fi

  echo -e "  ${BOLD}Options:${NC}"
  echo -e "    ${CYAN}all${NC}     — Restore everything"
  echo -e "    ${CYAN}1,3,5${NC}   — Restore specific items (comma-separated)"
  echo -e "    ${CYAN}none${NC}    — Cancel"
  echo ""
  echo -en "  ${BOLD}Restore:${NC} "
  read -r choice

  case "$choice" in
    none|n|"")
      echo ""
      log_info "Nothing restored."
      ;;
    all|a)
      local restored=0
      for i in $(seq 0 $((${#items[@]} - 1))); do
        do_restore "${item_types[$i]}" "${item_names[$i]}" "$claude_dir"
        restored=$((restored + 1))
      done
      echo ""
      log_success "Restored $restored components."
      ;;
    *)
      local restored=0
      IFS=',' read -ra selections <<< "$choice"
      for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        local idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#items[@]}" ]; then
          do_restore "${item_types[$idx]}" "${item_names[$idx]}" "$claude_dir"
          restored=$((restored + 1))
        fi
      done
      echo ""
      log_success "Restored $restored components."
      ;;
  esac
  echo ""
}

do_restore() {
  local type="$1" name="$2" claude_dir="$3"

  case "$type" in
    agent)
      if [ -f "$TASUKI_TEMPLATES/agents/$name.md" ]; then
        cp "$TASUKI_TEMPLATES/agents/$name.md" "$claude_dir/agents/$name.md"
        log_dim "  restored agent: $name"
      fi
      ;;
    skill)
      if [ -d "$TASUKI_TEMPLATES/skills/$name" ]; then
        mkdir -p "$claude_dir/skills/$name"
        cp "$TASUKI_TEMPLATES/skills/$name/SKILL.md" "$claude_dir/skills/$name/SKILL.md"
        log_dim "  restored skill: $name"
      fi
      ;;
    rule)
      if [ -f "$TASUKI_TEMPLATES/rules/$name" ]; then
        cp "$TASUKI_TEMPLATES/rules/$name" "$claude_dir/rules/$name"
        log_dim "  restored rule: $name"
      fi
      ;;
  esac
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  restore_interactive "$@"
fi
