#!/bin/bash
# Tasuki Engine — Agent Auto-Discovery
# Scans .tasuki/agents/ directory, reads frontmatter from each agent,
# and builds a capability map. The planner and routing engine use this
# map to select agents by CAPABILITY, not by name.
#
# Usage: source this file, then call discover_agents /path/to/project
#   or:  bash discover.sh /path/to/project  (prints the map)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Global: discovered agents and their capabilities
declare -A AGENT_DOMAINS=()      # agent -> "domain1,domain2,..."
declare -A AGENT_TRIGGERS=()     # agent -> "trigger1,trigger2,..."
declare -A AGENT_PRIORITY=()     # agent -> number (pipeline order)
declare -A AGENT_ACTIVATION=()   # agent -> "always|conditional|reactive"
declare -A AGENT_STACK_REQ=()    # agent -> "backend|frontend|database|docker" or ""
declare -A AGENT_DESCRIPTION=()  # agent -> short description

# Reverse index: domain -> agents that handle it
declare -A DOMAIN_TO_AGENTS=()   # domain -> "agent1,agent2"

# Scan all agent .md files and extract frontmatter metadata
discover_agents() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local agents_dir="$project_dir/.tasuki/agents"

  if [ ! -d "$agents_dir" ]; then
    log_error "No agents directory: $agents_dir"
    return 1
  fi

  # Clear previous discovery
  AGENT_DOMAINS=()
  AGENT_TRIGGERS=()
  AGENT_PRIORITY=()
  AGENT_ACTIVATION=()
  AGENT_STACK_REQ=()
  AGENT_DESCRIPTION=()
  DOMAIN_TO_AGENTS=()

  for agent_file in "$agents_dir"/*.md; do
    [ -f "$agent_file" ] || continue
    local name
    name=$(basename "$agent_file" .md)

    # Skip onboard — it's a meta-agent, not a pipeline agent
    [ "$name" = "onboard" ] && continue

    # Parse YAML frontmatter (between --- markers)
    local in_frontmatter=false
    local domains="" triggers="" priority="50" activation="conditional" stack_req="" description=""

    while IFS= read -r line; do
      if [ "$line" = "---" ]; then
        if $in_frontmatter; then
          break  # End of frontmatter
        else
          in_frontmatter=true
          continue
        fi
      fi

      if $in_frontmatter; then
        # Extract fields
        case "$line" in
          domains:*)
            domains=$(echo "$line" | sed 's/^domains:\s*//' | sed 's/\[//;s/\]//' | tr -d '"' | tr -d "'")
            ;;
          triggers:*)
            triggers=$(echo "$line" | sed 's/^triggers:\s*//' | sed 's/\[//;s/\]//' | tr -d '"' | tr -d "'")
            ;;
          priority:*)
            priority=$(echo "$line" | sed 's/^priority:\s*//' | tr -d ' ')
            ;;
          activation:*)
            activation=$(echo "$line" | sed 's/^activation:\s*//' | tr -d ' ')
            ;;
          stack_required:*)
            stack_req=$(echo "$line" | sed 's/^stack_required:\s*//' | tr -d ' ')
            ;;
          description:*)
            description=$(echo "$line" | sed 's/^description:\s*//' | cut -c1-80)
            ;;
        esac
      fi
    done < "$agent_file"

    # Store discovered data
    AGENT_DOMAINS[$name]="$domains"
    AGENT_TRIGGERS[$name]="$triggers"
    AGENT_PRIORITY[$name]="$priority"
    AGENT_ACTIVATION[$name]="$activation"
    AGENT_STACK_REQ[$name]="$stack_req"
    AGENT_DESCRIPTION[$name]="$description"

    # Build reverse index: domain → agents
    IFS=',' read -ra domain_list <<< "$domains"
    for domain in "${domain_list[@]}"; do
      domain=$(echo "$domain" | tr -d ' ')
      [ -z "$domain" ] && continue
      if [ -n "${DOMAIN_TO_AGENTS[$domain]:-}" ]; then
        DOMAIN_TO_AGENTS[$domain]="${DOMAIN_TO_AGENTS[$domain]},$name"
      else
        DOMAIN_TO_AGENTS[$domain]="$name"
      fi
    done
  done
}

# Find the best agent for a given task description
# Returns: agent name (or empty if no match)
match_agent_for_task() {
  local task_desc="$1"
  local task_lower
  task_lower=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')

  # Score each agent by how many triggers match the task
  local best_agent=""
  local best_score=0

  for agent in "${!AGENT_TRIGGERS[@]}"; do
    local score=0
    IFS=',' read -ra trigger_list <<< "${AGENT_TRIGGERS[$agent]}"
    for trigger in "${trigger_list[@]}"; do
      trigger=$(echo "$trigger" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
      [ -z "$trigger" ] && continue
      if echo "$task_lower" | grep -q "$trigger"; then
        score=$((score + 1))
      fi
    done

    # Also check domain keywords
    IFS=',' read -ra domain_list <<< "${AGENT_DOMAINS[$agent]}"
    for domain in "${domain_list[@]}"; do
      domain=$(echo "$domain" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
      [ -z "$domain" ] && continue
      if echo "$task_lower" | grep -q "$domain"; then
        score=$((score + 1))
      fi
    done

    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      best_agent=$agent
    fi
  done

  echo "$best_agent"
}

# Find ALL agents relevant to a task (sorted by priority)
match_pipeline_for_task() {
  local task_desc="$1"
  local task_lower
  task_lower=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')

  local matched=()

  for agent in "${!AGENT_TRIGGERS[@]}"; do
    local activation="${AGENT_ACTIVATION[$agent]}"

    # Always-active agents are always included
    if [ "$activation" = "always" ]; then
      matched+=("${AGENT_PRIORITY[$agent]}:$agent")
      continue
    fi

    # Reactive agents only if task mentions failure/error
    if [ "$activation" = "reactive" ]; then
      if echo "$task_lower" | grep -qE "error|fail|crash|bug|broken|debug|slow|timeout"; then
        matched+=("${AGENT_PRIORITY[$agent]}:$agent")
      fi
      continue
    fi

    # Conditional agents: check triggers and domains
    local score=0
    IFS=',' read -ra trigger_list <<< "${AGENT_TRIGGERS[$agent]}"
    for trigger in "${trigger_list[@]}"; do
      trigger=$(echo "$trigger" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
      [ -z "$trigger" ] && continue
      echo "$task_lower" | grep -q "$trigger" && score=$((score + 1))
    done

    IFS=',' read -ra domain_list <<< "${AGENT_DOMAINS[$agent]}"
    for domain in "${domain_list[@]}"; do
      domain=$(echo "$domain" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
      [ -z "$domain" ] && continue
      echo "$task_lower" | grep -q "$domain" && score=$((score + 1))
    done

    if [ "$score" -gt 0 ]; then
      matched+=("${AGENT_PRIORITY[$agent]}:$agent")
    fi
  done

  # Sort by priority and return agent names
  printf '%s\n' "${matched[@]}" | sort -t: -k1 -n | cut -d: -f2
}

# Generate the capability map file (.tasuki/config/capability-map.yaml)
generate_capability_map() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local map_file="$project_dir/.tasuki/config/capability-map.yaml"

  mkdir -p "$(dirname "$map_file")"

  {
    echo "# Tasuki Capability Map — Auto-generated by discover.sh"
    echo "# Do not edit manually. Run: tasuki discover"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "agents:"

    # Sort agents by priority
    for agent in $(for a in "${!AGENT_PRIORITY[@]}"; do echo "${AGENT_PRIORITY[$a]}:$a"; done | sort -t: -k1 -n | cut -d: -f2); do
      echo "  $agent:"
      echo "    domains: [${AGENT_DOMAINS[$agent]}]"
      echo "    triggers: [${AGENT_TRIGGERS[$agent]}]"
      echo "    priority: ${AGENT_PRIORITY[$agent]}"
      echo "    activation: ${AGENT_ACTIVATION[$agent]}"
      [ -n "${AGENT_STACK_REQ[$agent]}" ] && echo "    stack_required: ${AGENT_STACK_REQ[$agent]}"
      echo ""
    done

    echo "domain_index:"
    for domain in $(echo "${!DOMAIN_TO_AGENTS[@]}" | tr ' ' '\n' | sort); do
      echo "  $domain: [${DOMAIN_TO_AGENTS[$domain]}]"
    done

  } > "$map_file"

  echo "$map_file"
}

# Print a formatted capability map to stdout
print_capability_map() {
  local project_dir="${1:-.}"

  echo ""
  echo -e "${BOLD}Tasuki Capability Map${NC}"
  echo -e "${DIM}═════════════════════${NC}"
  echo ""

  # Agents sorted by priority
  echo -e "${BOLD}Agents (by pipeline order):${NC}"
  echo ""

  for agent in $(for a in "${!AGENT_PRIORITY[@]}"; do echo "${AGENT_PRIORITY[$a]}:$a"; done | sort -t: -k1 -n | cut -d: -f2); do
    local activation="${AGENT_ACTIVATION[$agent]}"
    local icon=""
    case "$activation" in
      always)      icon="${GREEN}●${NC}" ;;
      conditional) icon="${YELLOW}◐${NC}" ;;
      reactive)    icon="${BLUE}○${NC}" ;;
    esac

    local stack=""
    [ -n "${AGENT_STACK_REQ[$agent]}" ] && stack=" ${DIM}[requires: ${AGENT_STACK_REQ[$agent]}]${NC}"

    echo -e "  $icon ${BOLD}$agent${NC} (priority ${AGENT_PRIORITY[$agent]})$stack"

    # Domains
    local domains="${AGENT_DOMAINS[$agent]}"
    if [ -n "$domains" ]; then
      echo -e "    ${DIM}domains: $domains${NC}"
    fi

    # Triggers
    local triggers="${AGENT_TRIGGERS[$agent]}"
    if [ -n "$triggers" ]; then
      echo -e "    ${DIM}triggers: $triggers${NC}"
    fi
    echo ""
  done

  # Domain index
  echo -e "${BOLD}Domain Index (domain → agent):${NC}"
  echo ""
  for domain in $(echo "${!DOMAIN_TO_AGENTS[@]}" | tr ' ' '\n' | sort); do
    echo -e "  ${CYAN}$domain${NC} → ${DOMAIN_TO_AGENTS[$domain]}"
  done
  echo ""

  # Legend
  echo -e "${DIM}Legend: ${GREEN}●${NC}${DIM} always  ${YELLOW}◐${NC}${DIM} conditional  ${BLUE}○${NC}${DIM} reactive${NC}"
  echo ""
}

# Test routing: show which agents would handle a given task
test_routing() {
  local task="$1"

  echo ""
  echo -e "${BOLD}Capability Routing Test${NC}"
  echo -e "  ${BOLD}Task:${NC} $task"
  echo ""

  echo -e "  ${BOLD}Best single agent:${NC}"
  local best
  best=$(match_agent_for_task "$task")
  if [ -n "$best" ]; then
    echo -e "    ${GREEN}→${NC} $best"
  else
    echo -e "    ${DIM}(no match)${NC}"
  fi
  echo ""

  echo -e "  ${BOLD}Full pipeline:${NC}"
  local pipeline
  pipeline=$(match_pipeline_for_task "$task")
  local stage=1
  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    local activation="${AGENT_ACTIVATION[$agent]}"
    if [ "$activation" = "reactive" ]; then
      echo -e "    ${YELLOW}~${NC} $agent ${DIM}(reactive)${NC}"
    else
      echo -e "    ${GREEN}$stage.${NC} $agent"
      stage=$((stage + 1))
    fi
  done <<< "$pipeline"
  echo ""
}

# --- Main: run directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  project="${1:-.}"

  if [ ! -d "$project/.tasuki/agents" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project"
    exit 1
  fi

  discover_agents "$project"

  case "${2:-}" in
    --test)
      # Test mode: discover + route a task
      if [ -z "${3:-}" ]; then
        echo "Usage: discover.sh /path --test \"task description\""
        exit 1
      fi
      print_capability_map "$project"
      test_routing "$3"
      ;;
    --generate)
      # Generate capability-map.yaml
      local map_file
      map_file=$(generate_capability_map "$project")
      log_success "Capability map generated: $map_file"
      ;;
    *)
      # Default: print the map
      print_capability_map "$project"
      ;;
  esac
fi
