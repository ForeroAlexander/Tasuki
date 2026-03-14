#!/bin/bash
# Tasuki Engine — Cleanup (User-Driven)
# Shows unused components and lets the user choose what to remove.
# Nothing is deleted automatically — the user decides.
#
# Usage: bash cleanup.sh [/path/to/project] [--all]
#   --all: remove all unused without asking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail
source "$SCRIPT_DIR/detect.sh"

cleanup_interactive() {
  local project_dir="${1:-.}"
  local auto_all="${2:-false}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  if [ ! -d "$claude_dir" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  # Run detection to know what's used
  run_detection "$project_dir" 2>/dev/null

  echo ""
  echo -e "${BOLD}Tasuki Cleanup${NC}"
  echo -e "${DIM}══════════════${NC}"
  echo ""

  # Collect all removable items
  local items=()
  local item_paths=()
  local item_types=()

  # Agents
  for agent_file in "$claude_dir/agents"/*.md; do
    [ -f "$agent_file" ] || continue
    local name
    name=$(basename "$agent_file" .md)
    case "$name" in planner|qa|security|reviewer|onboard|debugger) continue ;; esac

    local stack_req
    stack_req=$(grep "^stack_required:" "$agent_file" 2>/dev/null | head -1 | sed 's/^stack_required:\s*//' | tr -d ' ')
    [ -z "$stack_req" ] && continue

    local needed=true
    case "$stack_req" in
      backend)  [ "${DETECTED[backend_detected]}" != "true" ] && needed=false ;;
      frontend) [ "${DETECTED[frontend_detected]}" != "true" ] && needed=false ;;
      database) [ "${DETECTED[database_detected]}" != "true" ] && needed=false ;;
      docker)   [ "${DETECTED[infra_detected]}" != "true" ] && needed=false ;;
    esac

    if ! $needed; then
      items+=("$name agent ${DIM}(no $stack_req detected)${NC}")
      item_paths+=("$agent_file")
      item_types+=("file")
    fi
  done

  # Skills
  if [ "${DETECTED[frontend_detected]}" != "true" ]; then
    for skill in ui-design ui-ux-pro-max; do
      if [ -d "$claude_dir/skills/$skill" ]; then
        items+=("$skill skill ${DIM}(no frontend detected)${NC}")
        item_paths+=("$claude_dir/skills/$skill")
        item_types+=("dir")
      fi
    done
  fi
  if [ "${DETECTED[database_detected]}" != "true" ]; then
    if [ -d "$claude_dir/skills/db-migrate" ]; then
      items+=("db-migrate skill ${DIM}(no database detected)${NC}")
      item_paths+=("$claude_dir/skills/db-migrate")
      item_types+=("dir")
    fi
  fi
  if [ "${DETECTED[infra_detected]}" != "true" ]; then
    if [ -d "$claude_dir/skills/deploy-check" ]; then
      items+=("deploy-check skill ${DIM}(no infra detected)${NC}")
      item_paths+=("$claude_dir/skills/deploy-check")
      item_types+=("dir")
    fi
  fi

  # Rules
  if [ "${DETECTED[frontend_detected]}" != "true" ] && [ -f "$claude_dir/rules/frontend.md" ]; then
    items+=("frontend.md rule ${DIM}(no frontend detected)${NC}")
    item_paths+=("$claude_dir/rules/frontend.md")
    item_types+=("file")
  fi
  if [ "${DETECTED[backend_detected]}" != "true" ]; then
    for rule in backend.md models.md; do
      if [ -f "$claude_dir/rules/$rule" ]; then
        items+=("$rule rule ${DIM}(no backend detected)${NC}")
        item_paths+=("$claude_dir/rules/$rule")
        item_types+=("file")
      fi
    done
  fi
  if [ "${DETECTED[database_detected]}" != "true" ] && [ -f "$claude_dir/rules/migrations.md" ]; then
    items+=("migrations.md rule ${DIM}(no database detected)${NC}")
    item_paths+=("$claude_dir/rules/migrations.md")
    item_types+=("file")
  fi

  # Nothing to clean?
  if [ ${#items[@]} -eq 0 ]; then
    echo -e "  ${GREEN}Nothing to clean up — all components match your stack.${NC}"
    echo ""
    return 0
  fi

  # Show what can be removed
  echo -e "  ${BOLD}Components that don't match your current stack:${NC}"
  echo ""
  local i
  for i in $(seq 0 $((${#items[@]} - 1))); do
    echo -e "    ${YELLOW}$((i + 1)).${NC} ${items[$i]}"
  done
  echo ""

  if [ "$auto_all" = "true" ] || [ "$auto_all" = "--all" ]; then
    # Remove all without asking
    local removed=0
    for i in $(seq 0 $((${#items[@]} - 1))); do
      if [ "${item_types[$i]}" = "dir" ]; then
        rm -rf "${item_paths[$i]}"
      else
        rm -f "${item_paths[$i]}"
      fi
      removed=$((removed + 1))
    done
    log_success "Removed $removed components."
    echo ""
    echo -e "  Run ${CYAN}tasuki restore${NC} to bring anything back."
    echo ""
    return 0
  fi

  # Interactive: ask user
  echo -e "  ${BOLD}Options:${NC}"
  echo -e "    ${CYAN}all${NC}     — Remove all unused components"
  echo -e "    ${CYAN}1,3,5${NC}   — Remove specific items (comma-separated numbers)"
  echo -e "    ${CYAN}none${NC}    — Keep everything, exit"
  echo ""
  echo -en "  ${BOLD}Remove:${NC} "
  read -r choice

  case "$choice" in
    none|n|"")
      echo ""
      log_info "Nothing removed."
      ;;
    all|a)
      local removed=0
      for i in $(seq 0 $((${#items[@]} - 1))); do
        if [ "${item_types[$i]}" = "dir" ]; then
          rm -rf "${item_paths[$i]}"
        else
          rm -f "${item_paths[$i]}"
        fi
        removed=$((removed + 1))
      done
      echo ""
      log_success "Removed $removed components."
      ;;
    *)
      # Parse comma-separated numbers
      local removed=0
      IFS=',' read -ra selections <<< "$choice"
      for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | tr -d ' ')
        local idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#items[@]}" ]; then
          if [ "${item_types[$idx]}" = "dir" ]; then
            rm -rf "${item_paths[$idx]}"
          else
            rm -f "${item_paths[$idx]}"
          fi
          removed=$((removed + 1))
        fi
      done
      echo ""
      log_success "Removed $removed components."
      ;;
  esac

  echo ""
  echo -e "  Run ${CYAN}tasuki restore${NC} to bring anything back."
  echo ""
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cleanup_interactive "$@"
fi
