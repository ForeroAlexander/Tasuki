#!/bin/bash
# Tasuki Engine — Cost Estimator
# Estimates token usage and cost before running the pipeline.
# Based on: mode, agents, file sizes, task complexity.
# Usage: bash cost.sh "task description" [mode] [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail
source "$SCRIPT_DIR/discover.sh"
source "$SCRIPT_DIR/score.sh"

estimate_cost() {
  local description="$1"
  local mode="${2:-standard}"
  local project_dir="${3:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  # Score the task
  score_task "$description" "$project_dir" 2>/dev/null

  # Auto-mode resolution
  if [ "$mode" = "auto" ]; then
    mode="$TASK_MODE"
  fi

  # Discover agents
  if [ -d "$project_dir/.tasuki/agents" ]; then
    discover_agents "$project_dir"
  fi

  # Estimate pipeline
  local pipeline
  pipeline=$(match_pipeline_for_task "$description" 2>/dev/null)
  local agent_count=0
  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    agent_count=$((agent_count + 1))
  done <<< "$pipeline"

  # Estimate context size (source files)
  local source_tokens=0
  local source_files=0
  for ext in py ts js tsx jsx go rb java php svelte vue; do
    local count
    count=$(find "$project_dir" -name "*.$ext" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/__pycache__/*" 2>/dev/null | wc -l)
    source_files=$((source_files + count))
  done
  # Rough estimate: avg 100 lines per file, 4 tokens per line
  source_tokens=$((source_files * 100 * 4))

  # Estimate tokens per agent
  local agent_template_tokens=800     # avg agent template size
  local context_per_agent=2000        # context loaded per agent
  local output_per_agent=1500         # avg output per agent

  case "$mode" in
    fast)
      context_per_agent=1000
      output_per_agent=800
      ;;
    standard)
      context_per_agent=2000
      output_per_agent=1500
      ;;
    serious)
      context_per_agent=4000
      output_per_agent=3000
      ;;
  esac

  # Calculate totals
  local input_tokens=$((agent_count * (agent_template_tokens + context_per_agent)))
  local output_tokens=$((agent_count * output_per_agent))
  local total_tokens=$((input_tokens + output_tokens))

  # Cost per model (per 1M tokens, approximate)
  # Opus: $15 input, $75 output
  # Sonnet: $3 input, $15 output
  # Haiku: $0.25 input, $1.25 output

  local thinking_agents=0
  local execution_agents=0

  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    local model="${AGENT_PRIORITY[$agent]:-50}"  # use as proxy
    case "$agent" in
      planner|security|reviewer) thinking_agents=$((thinking_agents + 1)) ;;
      *) execution_agents=$((execution_agents + 1)) ;;
    esac
  done <<< "$pipeline"

  # Cost estimate
  local opus_input_cost=$(( (thinking_agents * context_per_agent * 15) / 1000000 ))
  local opus_output_cost=$(( (thinking_agents * output_per_agent * 75) / 1000000 ))
  local sonnet_input_cost=$(( (execution_agents * context_per_agent * 3) / 1000000 ))
  local sonnet_output_cost=$(( (execution_agents * output_per_agent * 15) / 1000000 ))

  # Use bc for decimal math, fallback to rough estimate
  local total_cost_cents=0
  if command -v bc &>/dev/null; then
    total_cost_cents=$(echo "scale=2; ($thinking_agents * ($context_per_agent * 0.015 + $output_per_agent * 0.075) + $execution_agents * ($context_per_agent * 0.003 + $output_per_agent * 0.015)) / 1000" | bc 2>/dev/null || echo "0.05")
  else
    # Rough estimate: $0.01-0.10 per agent
    total_cost_cents="~0.$(printf '%02d' $((agent_count * 3)))"
  fi

  # Display
  echo ""
  echo -e "${BOLD}Cost Estimate${NC}"
  echo -e "${DIM}═════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Task:${NC}       $description"
  echo -e "  ${BOLD}Score:${NC}      $TASK_SCORE/10"
  echo -e "  ${BOLD}Mode:${NC}       $mode"
  echo ""
  echo -e "  ${BOLD}Pipeline:${NC}   $agent_count agents"
  echo -e "    ${CYAN}Opus${NC}  (thinking):  $thinking_agents agents (planner, security, reviewer)"
  echo -e "    ${GREEN}Sonnet${NC} (execution): $execution_agents agents"
  echo ""
  echo -e "  ${BOLD}Tokens (estimated):${NC}"
  echo -e "    Input:  ~$((input_tokens / 1000))K tokens"
  echo -e "    Output: ~$((output_tokens / 1000))K tokens"
  echo -e "    Total:  ~$((total_tokens / 1000))K tokens"
  echo ""
  echo -e "  ${BOLD}Cost (estimated):${NC} ${GREEN}\$$total_cost_cents${NC}"
  echo ""
  echo -e "  ${DIM}Note: Actual cost depends on context window usage and output length.${NC}"
  echo -e "  ${DIM}Estimates assume compressed context loading.${NC}"
  echo ""

  # Cost comparison by mode
  echo -e "  ${BOLD}Mode comparison for this task:${NC}"
  echo -e "    fast:     ~$((agent_count > 2 ? agent_count - 1 : 2)) agents, ~\$0.$(printf '%02d' $((agent_count * 1)))"
  echo -e "    standard: ~$agent_count agents, ~\$$total_cost_cents"
  echo -e "    serious:  ~$agent_count agents, ~\$0.$(printf '%02d' $((agent_count * 8)))"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  estimate_cost "${1:-add new feature}" "${2:-standard}" "${3:-.}"
fi
