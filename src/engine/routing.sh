#!/bin/bash
# Tasuki Engine — Capability-Based Agent Routing
# Uses auto-discovery to match tasks to agents by CAPABILITY, not by name.
# Reads agent frontmatter (domains, triggers, priority, activation, stack_required)
# and builds the optimal pipeline for any given task.
#
# Usage: bash routing.sh "task description" [mode] [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +u
source "$SCRIPT_DIR/discover.sh"

# Route a task through the capability-based pipeline
route_task() {
  local description="$1"
  local mode="${2:-standard}"
  local project_dir="${3:-.}"

  # Auto-discover all installed agents
  discover_agents "$project_dir"

  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

  # Get mode skip list from registry (if exists)
  local skip_in_mode=""
  if [ -f "$TASUKI_REGISTRY" ]; then
    skip_in_mode=$(get_mode_skip "$mode")
  fi

  # Build the pipeline based on capability matching (global scope for print_routing)
  ROUTED_PIPELINE=()
  declare -gA AGENT_STATUS=()
  declare -gA AGENT_REASON=()

  # Get all agents sorted by priority
  local sorted_agents
  sorted_agents=$(for a in "${!AGENT_PRIORITY[@]}"; do
    echo "${AGENT_PRIORITY[$a]}:$a"
  done | sort -t: -k1 -n | cut -d: -f2)

  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    local status="active"
    local reason=""
    local activation="${AGENT_ACTIVATION[$agent]}"

    # 1. Check activation mode
    if [ "$activation" = "reactive" ]; then
      if echo "$desc_lower" | grep -qE "error|fail|crash|bug|broken|debug|slow|timeout|500"; then
        status="active"
        reason="triggered by error/failure keywords"
      else
        status="reactive"
        reason="on-demand only (activated on failure)"
      fi
    fi

    # 2. Check stack_required against detected project
    if [ "$status" = "active" ] && [ -n "${AGENT_STACK_REQ[$agent]}" ]; then
      local required="${AGENT_STACK_REQ[$agent]}"
      local satisfied=false

      # Check if detection results are available
      if [ -n "${DETECTED[backend_detected]:-}" ]; then
        case "$required" in
          backend)  [ "${DETECTED[backend_detected]}" = "true" ] && satisfied=true ;;
          frontend) [ "${DETECTED[frontend_detected]}" = "true" ] && satisfied=true ;;
          database) [ "${DETECTED[database_detected]}" = "true" ] && satisfied=true ;;
          docker)   [ "${DETECTED[infra_detected]}" = "true" ] && satisfied=true ;;
        esac
      else
        # No detection data — check by trigger/domain match instead
        satisfied=true
      fi

      if ! $satisfied; then
        status="skipped"
        reason="stack not detected ($required)"
      fi
    fi

    # 3. Check mode-level skips
    if [ "$status" = "active" ] && [ -n "$skip_in_mode" ]; then
      if echo "$skip_in_mode" | grep -qw "$agent"; then
        if [ "$activation" != "always" ]; then
          status="skipped"
          reason="skipped in $mode mode"
        fi
      fi
    fi

    # 4. Capability matching — skip conditional agents that don't match the task
    if [ "$status" = "active" ] && [ "$activation" = "conditional" ]; then
      local match_score=0

      IFS=',' read -ra trigger_list <<< "${AGENT_TRIGGERS[$agent]}"
      for trigger in "${trigger_list[@]}"; do
        trigger=$(echo "$trigger" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        [ -z "$trigger" ] && continue
        echo "$desc_lower" | grep -q "$trigger" && match_score=$((match_score + 1))
      done

      IFS=',' read -ra domain_list <<< "${AGENT_DOMAINS[$agent]}"
      for domain in "${domain_list[@]}"; do
        domain=$(echo "$domain" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        [ -z "$domain" ] && continue
        echo "$desc_lower" | grep -q "$domain" && match_score=$((match_score + 1))
      done

      if [ "$match_score" -eq 0 ]; then
        status="skipped"
        reason="no capability match for this task"
      else
        reason="matched $match_score capabilities"
      fi
    fi

    AGENT_STATUS[$agent]="$status"
    AGENT_REASON[$agent]="$reason"

    if [ "$status" = "active" ]; then
      ROUTED_PIPELINE+=("$agent")
    fi
  done <<< "$sorted_agents"
}

# Print the routed pipeline
print_routing() {
  local description="$1"
  local mode="${2:-standard}"

  echo ""
  echo -e "${BOLD}Agent Routing (Capability-Based)${NC}"
  echo -e "${DIM}════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Task:${NC} $description"
  echo -e "  ${BOLD}Mode:${NC} $mode"
  echo -e "  ${BOLD}Agents discovered:${NC} ${#AGENT_PRIORITY[@]}"
  echo ""

  echo -e "  ${BOLD}Pipeline:${NC}"
  local stage=1

  # Sort by priority
  local sorted_agents
  sorted_agents=$(for a in "${!AGENT_PRIORITY[@]}"; do
    echo "${AGENT_PRIORITY[$a]}:$a"
  done | sort -t: -k1 -n | cut -d: -f2)

  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    local status="${AGENT_STATUS[$agent]}"
    local reason="${AGENT_REASON[$agent]}"
    local domains="${AGENT_DOMAINS[$agent]}"

    case "$status" in
      active)
        echo -e "    ${GREEN}$stage.${NC} ${BOLD}$agent${NC} ${DIM}[$domains]${NC}"
        [ -n "$reason" ] && echo -e "       ${DIM}$reason${NC}"
        stage=$((stage + 1))
        ;;
      skipped)
        echo -e "    ${DIM}   $agent — skipped: $reason${NC}"
        ;;
      reactive)
        echo -e "    ${YELLOW}~${NC}  ${DIM}$agent — $reason${NC}"
        ;;
    esac
  done <<< "$sorted_agents"
  echo ""

  # Model overrides for mode
  if [ -f "$TASUKI_REGISTRY" ]; then
    local model_info
    model_info=$(get_mode_model "$mode")
    if [ -n "$model_info" ]; then
      echo -e "  ${BOLD}Models:${NC} $model_info"
      echo ""
    fi
  fi
}

# --- Registry helpers (for mode config) ---
get_mode_skip() {
  local mode="$1"
  local in_modes=false in_target=false
  while IFS= read -r line; do
    echo "$line" | grep -qE '^modes:' && in_modes=true && continue
    $in_modes && echo "$line" | grep -qE "^  ${mode}:" && in_target=true && continue
    $in_modes && $in_target && echo "$line" | grep -qE '^  [a-z].*:$' && break
    $in_target && echo "$line" | grep -qE '^\s+skip_agents:' && {
      echo "$line" | sed 's/.*skip_agents:\s*//' | sed 's/\[//;s/\]//' | tr -d '"'
      return
    }
  done < "$TASUKI_REGISTRY"
}

get_mode_model() {
  local mode="$1"
  local in_modes=false in_target=false in_model=false result=""
  while IFS= read -r line; do
    echo "$line" | grep -qE '^modes:' && in_modes=true && continue
    $in_modes && echo "$line" | grep -qE "^  ${mode}:" && in_target=true && continue
    $in_modes && $in_target && echo "$line" | grep -qE '^  [a-z].*:$' && break
    $in_target && echo "$line" | grep -qE '^\s+model_override:' && in_model=true && continue
    $in_target && $in_model && echo "$line" | grep -qE '^\s{6}' && {
      local key val
      key=$(echo "$line" | sed 's/^\s*//' | cut -d: -f1)
      val=$(echo "$line" | cut -d: -f2 | tr -d ' ')
      result="${result}${key}=${val} "
    }
    $in_target && $in_model && ! echo "$line" | grep -qE '^\s{6}' && break
  done < "$TASUKI_REGISTRY"
  echo "$result"
}

# --- Main ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ -z "${1:-}" ]; then
    echo "Usage: routing.sh \"task description\" [mode] [/path/to/project]"
    exit 1
  fi

  description="$1"
  mode="${2:-standard}"
  project="${3:-.}"

  # If project has detection data, load it
  if [ -d "$project/.tasuki" ]; then
    source "$SCRIPT_DIR/detect.sh"
    run_detection "$project" 2>/dev/null
    source "$SCRIPT_DIR/discover.sh"
    discover_agents "$project" 2>/dev/null
  fi

  route_task "$description" "$mode" "$project"
  print_routing "$description" "$mode"
fi
