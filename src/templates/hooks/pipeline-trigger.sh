#!/bin/bash
# Tasuki Hook: Pipeline Trigger (Orchestrator)
# UserPromptSubmit hook — runs when user sends a message.
# Activates the pipeline ONLY when the user says "tasuki" in their prompt.
#
# This is the orchestration layer. It:
# 1. Detects new tasks vs continuations
# 2. Reads the current pipeline stage
# 3. Outputs SPECIFIC instructions (which agent to read, what to do)
# 4. Adapts instructions to the current mode (fast/standard/serious)
#
# Examples that trigger:
#   "tasuki: add a login endpoint"   → new task, starts pipeline
#   "tasuki add payments"            → new task
#   "hey tasuki, fix the auth bug"   → new task
#   "tasuki: continue"               → continue existing pipeline
#   "tasuki: what's next?"           → show current stage
#
# Examples that DON'T trigger:
#   "add a login endpoint"
#   "fix the auth bug"
#   "what does this function do?"

set +e
set +o pipefail

# Read the user's prompt from stdin
if [ -t 0 ]; then
  exit 0
fi

INPUT=$(cat)
PROMPT=$(printf '%s\n' "$INPUT" | grep -oP '"prompt"\s*:\s*"\K[^"]*' 2>/dev/null || true)

[ -z "$PROMPT" ] && exit 0

LOWER=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Only trigger on "tasuki" keyword
if ! printf '%s\n' "$LOWER" | grep -qE '(^|\s)tasuki(\s|:|$)'; then
  exit 0
fi

# Skip if user says "skip pipeline" or "no pipeline"
if printf '%s\n' "$LOWER" | grep -qE '(skip|no|don.t|without).*(pipeline|stages)'; then
  exit 0
fi

# --- Project setup ---
[ ! -d "${PWD}/.tasuki" ] && exit 0

PROGRESS_FILE="${PWD}/.tasuki/config/pipeline-progress.json"
TRACKER_LOG="${PWD}/.tasuki/config/tracker-debug.log"
AGENTS_DIR="${PWD}/.tasuki/agents"
mkdir -p "${PWD}/.tasuki/config"

# Read mode
MODE="standard"
[ -f "${PWD}/.tasuki/config/mode" ] && MODE=$(cat "${PWD}/.tasuki/config/mode" 2>/dev/null || echo "standard")

# --- Define stage sequences per mode ---
# Each stage: number:agent_name:agent_file
case "$MODE" in
  fast)
    STAGES=(
      "2:QA:qa"
      "4:Backend Dev:backend-dev"
      "5:Frontend Dev:frontend-dev"
      "7:Reviewer:reviewer"
    )
    ;;
  serious)
    STAGES=(
      "1:Planner:planner"
      "2:QA:qa"
      "3:DB Architect:db-architect"
      "4:Backend Dev:backend-dev"
      "5:Frontend Dev:frontend-dev"
      "6:Security:security"
      "7:Reviewer:reviewer"
      "8:DevOps:devops"
    )
    ;;
  *)  # standard
    STAGES=(
      "1:Planner:planner"
      "2:QA:qa"
      "3:DB Architect:db-architect"
      "4:Backend Dev:backend-dev"
      "5:Frontend Dev:frontend-dev"
      "6:Security:security"
      "7:Reviewer:reviewer"
      "8:DevOps:devops"
    )
    ;;
esac

# Filter stages to only include agents that exist
ACTIVE_STAGES=()
for stage_entry in "${STAGES[@]}"; do
  IFS=':' read -r snum sname sfile <<< "$stage_entry"
  [ -f "$AGENTS_DIR/${sfile}.md" ] && ACTIVE_STAGES+=("$stage_entry")
done

# --- Detect: new task or continuation? ---
IS_CONTINUATION=false
CURRENT_STAGE=0
CURRENT_TASK=""

if [ -f "$PROGRESS_FILE" ]; then
  CURRENT_STAGE=$(grep -oP '"current_stage"\s*:\s*\K[0-9]+' "$PROGRESS_FILE" 2>/dev/null | head -1 || echo "0")
  CURRENT_STATUS=$(grep -oP '"status"\s*:\s*"\K[^"]*' "$PROGRESS_FILE" 2>/dev/null | head -1 || echo "")
  CURRENT_TASK=$(grep -oP '"task"\s*:\s*"\K[^"]*' "$PROGRESS_FILE" 2>/dev/null | head -1 || echo "")

  # Continuation if: pipeline is running AND user says continue/next/keep going
  if [ "$CURRENT_STATUS" = "running" ] && [ "$CURRENT_STAGE" -gt 0 ]; then
    if printf '%s\n' "$LOWER" | grep -qE 'continu|next|keep|go on|proceed|siguiente|sigue|avanza'; then
      IS_CONTINUATION=true
    fi
  fi
fi

# --- New task: initialize fresh state ---
if [ "$IS_CONTINUATION" = false ]; then
  # Clean task name (remove "tasuki:" or "tasuki " prefix)
  TASK_NAME=$(printf '%s\n' "$PROMPT" | sed 's/^[[:space:]]*[Tt]asuki[: ]*//' | head -c 80)
  # Escape quotes for JSON safety
  TASK_NAME=$(printf '%s\n' "$TASK_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')

  cat > "$PROGRESS_FILE" << PEOF
{
  "task": "$TASK_NAME",
  "mode": "$MODE",
  "started": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "running",
  "current_stage": 0,
  "total_stages": ${#ACTIVE_STAGES[@]},
  "stages": {}
}
PEOF

  # Clear tracker log — new task = fresh session
  : > "$TRACKER_LOG" 2>/dev/null

  CURRENT_STAGE=0
  CURRENT_TASK="$TASK_NAME"
fi

# --- Determine next stage ---
NEXT_STAGE=""
NEXT_NAME=""
NEXT_FILE=""
STAGES_DONE=""

for stage_entry in "${ACTIVE_STAGES[@]}"; do
  IFS=':' read -r snum sname sfile <<< "$stage_entry"
  if [ "$snum" -gt "$CURRENT_STAGE" ]; then
    if [ -z "$NEXT_STAGE" ]; then
      NEXT_STAGE="$snum"
      NEXT_NAME="$sname"
      NEXT_FILE="$sfile"
    fi
  else
    STAGES_DONE="${STAGES_DONE}${sname}, "
  fi
done

# --- Build output ---
echo ""

if [ "$IS_CONTINUATION" = true ]; then
  echo "PIPELINE CONTINUATION — Task: \"$CURRENT_TASK\" (mode: $MODE)"
else
  echo "PIPELINE ACTIVATED — Task: \"$CURRENT_TASK\" (mode: $MODE)"
fi
echo ""

# Show progress
if [ -n "$STAGES_DONE" ]; then
  echo "Completed: ${STAGES_DONE%, }"
fi

# Next stage instructions
if [ -n "$NEXT_STAGE" ]; then
  echo "NEXT STAGE: [$NEXT_STAGE] $NEXT_NAME"
  echo ""
  echo "ACTION REQUIRED:"
  echo "  1. Read the agent file: .tasuki/agents/${NEXT_FILE}.md"
  echo "  2. Follow all instructions in that agent file"
  echo "  3. Complete the stage before moving to the next one"
  echo ""

  # Stage-specific guidance
  case "$NEXT_FILE" in
    planner)
      echo "The Planner analyzes the task and creates a PRD in tasuki-plans/{feature}/prd.md."
      echo "Get user confirmation on the plan before proceeding to the next stage."
      ;;
    qa)
      echo "QA writes tests FIRST (TDD). Create failing tests that define the expected behavior."
      echo "Do NOT write implementation code yet — only tests."
      ;;
    db-architect)
      echo "DB Architect designs schema changes and writes migrations."
      echo "Use safe migration patterns (IF NOT EXISTS, CONCURRENTLY, rollback)."
      ;;
    backend-dev)
      echo "Backend Dev implements until all tests pass."
      echo "Run tests after implementation. All tests from QA stage must pass."
      ;;
    frontend-dev)
      echo "Frontend Dev implements the UI. Backend API must be complete before starting."
      ;;
    security)
      echo "Security runs a full audit on all changes made so far."
      echo "Check OWASP top 10, auth, injection, secrets, dependencies."
      ;;
    reviewer)
      REVIEWER_ROUNDS=2
      [ "$MODE" = "fast" ] && REVIEWER_ROUNDS=1
      [ "$MODE" = "serious" ] && REVIEWER_ROUNDS=3
      echo "Reviewer performs $REVIEWER_ROUNDS review round(s)."
      echo "Check correctness, conventions, test coverage, and documentation."
      ;;
    devops)
      echo "DevOps handles Docker, CI/CD, deployment configuration."
      ;;
  esac

  # Show remaining pipeline
  REMAINING=""
  PAST_NEXT=false
  for stage_entry in "${ACTIVE_STAGES[@]}"; do
    IFS=':' read -r snum sname sfile <<< "$stage_entry"
    if [ "$PAST_NEXT" = true ]; then
      REMAINING="${REMAINING} → [$snum] $sname"
    fi
    [ "$snum" = "$NEXT_STAGE" ] && PAST_NEXT=true
  done
  if [ -n "$REMAINING" ]; then
    echo ""
    echo "After this stage:${REMAINING}"
  fi
else
  echo "ALL STAGES COMPLETE. Pipeline finished."
  echo ""
  echo "Final steps:"
  echo "  1. Write a memory node in memory-vault/ summarizing what was built"
  echo "  2. Update tasuki-plans/{feature}/status.md to 'completed'"
fi

echo ""
exit 0
