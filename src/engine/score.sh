#!/bin/bash
# Tasuki Engine — Complexity Scoring
# Analyzes a task description or git diff to determine complexity (1-10).
# Used by auto mode to pick fast (1-3), standard (4-6), or serious (7-10).
# Usage: source this file, then call score_task "description" [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Score a task and return: score, recommended mode, reasoning
score_task() {
  local description="$1"
  local project_dir="${2:-.}"
  local score=0
  local reasons=()

  # Lowercase for matching
  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

  # --- Keyword scoring ---

  # High complexity indicators (+3 each)
  local high_keywords=("architecture" "refactor" "redesign" "migration" "multi-tenant" "microservice" "new module" "new service" "auth system" "security" "compliance" "breaking change" "rewrite" "payment" "billing" "subscription" "stripe" "oauth" "sso" "real-time" "notification system" "file upload" "search engine" "permissions" "role-based")
  for kw in "${high_keywords[@]}"; do
    if echo "$desc_lower" | grep -q "$kw"; then
      score=$((score + 3))
      reasons+=("'$kw' detected (+3)")
    fi
  done

  # Medium complexity indicators (+2 each)
  local med_keywords=("new feature" "new endpoint" "new page" "crud" "integration" "api" "database" "schema" "component" "state management" "websocket" "background job" "caching" "pagination" "add" "implement" "create" "build" "authentication" "authorization" "processing" "dashboard" "report" "export" "import" "webhook" "email" "queue" "celery" "redis")
  for kw in "${med_keywords[@]}"; do
    if echo "$desc_lower" | grep -q "$kw"; then
      score=$((score + 2))
      reasons+=("'$kw' detected (+2)")
    fi
  done

  # Low complexity indicators (+1 each)
  local low_keywords=("fix" "bug" "typo" "rename" "update" "change" "tweak" "style" "css" "text" "label" "comment" "docs" "readme" "log" "config")
  for kw in "${low_keywords[@]}"; do
    if echo "$desc_lower" | grep -q "$kw"; then
      score=$((score + 1))
      reasons+=("'$kw' detected (+1)")
    fi
  done

  # --- Scope scoring (from git diff if available) ---
  if [ -d "$project_dir/.git" ]; then
    local files_changed=0
    local lines_changed=0

    # Check staged or unstaged changes
    files_changed=$(cd "$project_dir" && git diff --name-only HEAD 2>/dev/null | wc -l || echo "0")
    lines_changed=$(cd "$project_dir" && git diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null || echo "0")

    if [ "$files_changed" -gt 15 ]; then
      score=$((score + 3))
      reasons+=("$files_changed files changed (+3)")
    elif [ "$files_changed" -gt 5 ]; then
      score=$((score + 2))
      reasons+=("$files_changed files changed (+2)")
    elif [ "$files_changed" -gt 0 ]; then
      score=$((score + 1))
      reasons+=("$files_changed files changed (+1)")
    fi
  fi

  # --- Multi-area detection ---
  local areas=0
  echo "$desc_lower" | grep -qE "backend|api|server|endpoint" && areas=$((areas + 1))
  echo "$desc_lower" | grep -qE "frontend|ui|page|component" && areas=$((areas + 1))
  echo "$desc_lower" | grep -qE "database|schema|migration|table" && areas=$((areas + 1))
  echo "$desc_lower" | grep -qE "docker|deploy|ci|infra" && areas=$((areas + 1))

  if [ "$areas" -ge 3 ]; then
    score=$((score + 3))
    reasons+=("touches $areas areas (+3)")
  elif [ "$areas" -ge 2 ]; then
    score=$((score + 2))
    reasons+=("touches $areas areas (+2)")
  fi

  # Cap at 10
  [ "$score" -gt 10 ] && score=10

  # Minimum 1
  [ "$score" -lt 1 ] && score=1

  # Determine mode
  local mode
  if [ "$score" -le 3 ]; then
    mode="fast"
  elif [ "$score" -le 6 ]; then
    mode="standard"
  else
    mode="serious"
  fi

  # Store results in globals
  TASK_SCORE="$score"
  TASK_MODE="$mode"
  TASK_REASONS=("${reasons[@]}")
}

# Print a nicely formatted score report
print_score() {
  local description="$1"

  echo ""
  echo -e "${BOLD}Complexity Analysis${NC}"
  echo -e "${DIM}═══════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Task:${NC}  $description"
  echo ""

  # Score bar visualization
  local bar=""
  local i
  for i in $(seq 1 10); do
    if [ "$i" -le "$TASK_SCORE" ]; then
      if [ "$TASK_SCORE" -le 3 ]; then
        bar+="${GREEN}█${NC}"
      elif [ "$TASK_SCORE" -le 6 ]; then
        bar+="${YELLOW}█${NC}"
      else
        bar+="${RED}█${NC}"
      fi
    else
      bar+="${DIM}░${NC}"
    fi
  done

  echo -e "  ${BOLD}Score:${NC} $bar ${BOLD}$TASK_SCORE${NC}/10"
  echo -e "  ${BOLD}Mode:${NC}  ${TASK_MODE}"
  echo ""

  if [ ${#TASK_REASONS[@]} -gt 0 ]; then
    echo -e "  ${BOLD}Reasoning:${NC}"
    for reason in "${TASK_REASONS[@]}"; do
      echo -e "    ${DIM}- $reason${NC}"
    done
    echo ""
  fi

  # Mode description
  case "$TASK_MODE" in
    fast)
      echo -e "  ${GREEN}Fast mode:${NC} Skip planner, lightweight security, 1 reviewer round."
      ;;
    standard)
      echo -e "  ${YELLOW}Standard mode:${NC} Full pipeline, TDD enforced, 2 reviewer rounds."
      ;;
    serious)
      echo -e "  ${RED}Serious mode:${NC} Full pipeline + Opus everywhere, 3 reviewer rounds, full security audit."
      ;;
  esac
  echo ""
}

# Quick one-liner: score and print
analyze_task() {
  local description="$1"
  local project_dir="${2:-.}"

  score_task "$description" "$project_dir"
  print_score "$description"
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ -z "${1:-}" ]; then
    echo "Usage: score.sh \"task description\" [/path/to/project]"
    exit 1
  fi
  source "$SCRIPT_DIR/common.sh"
  analyze_task "$1" "${2:-.}"
fi
