#!/bin/bash
# Tasuki Hook: Pipeline Tracker (State Machine)
# PreToolUse hook for ALL tools — tracks pipeline stage, files touched,
# tests run, and results. Machine-readable state for session continuity.
# Never blocks — always exits 0.
#
# State file: .tasuki/config/pipeline-progress.json
# Format:
# {
#   "task": "add overdue loans",
#   "mode": "standard",
#   "started": "2026-03-15 21:25:00",
#   "status": "running",
#   "current_stage": 4,
#   "total_stages": 9,
#   "stages": {
#     "Planner": { "status": "done", "time": "21:25:49", "files_created": ["tasuki-plans/overdue/prd.md"], "files_read": ["agents/planner.md"] },
#     "QA": { "status": "done", "time": "21:29:22", "files_created": ["tests/test_overdue.py"], "tests_run": 3, "tests_passed": 0 },
#     "Backend-Dev": { "status": "running", "time": "21:33:43", "files_edited": ["app/views.py", "app/services.py"], "tests_run": 3, "tests_passed": 3 }
#   }
# }

set +e
set +o pipefail

PROJECT_DIR="${PWD}"
PROGRESS_FILE="$PROJECT_DIR/.tasuki/config/pipeline-progress.json"

# Only track if .tasuki exists
[ ! -d "$PROJECT_DIR/.tasuki" ] && exit 0

# Read tool input from stdin
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi
[ -z "$INPUT" ] && INPUT="${TOOL_INPUT:-}"

# Extract tool name and file path
TOOL_NAME=""
FILE_PATH=""
COMMAND=""

if [ -n "$INPUT" ]; then
  TOOL_NAME=$(printf '%s\n' "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  [ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"pattern"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  COMMAND=$(printf '%s\n' "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]*' 2>/dev/null || true)
fi

# --- Detect stage from agent file reads ---
STAGE_NUM=0
STAGE_NAME=""

case "$FILE_PATH" in
  *agents/planner.md*)    STAGE_NUM=1; STAGE_NAME="Planner" ;;
  *agents/qa.md*)         STAGE_NUM=2; STAGE_NAME="QA" ;;
  *agents/db-architect*)  STAGE_NUM=3; STAGE_NAME="DB-Architect" ;;
  *agents/backend-dev*)   STAGE_NUM=4; STAGE_NAME="Backend-Dev" ;;
  *agents/frontend-dev*)  STAGE_NUM=5; STAGE_NAME="Frontend-Dev" ;;
  *agents/debugger*)      STAGE_NUM=55; STAGE_NAME="Debugger" ;;
  *agents/security*)      STAGE_NUM=6; STAGE_NAME="Security" ;;
  *agents/reviewer*)      STAGE_NUM=7; STAGE_NAME="Reviewer" ;;
  *agents/devops*)        STAGE_NUM=8; STAGE_NAME="DevOps" ;;
  *tasuki-plans/*/prd*)   STAGE_NUM=1; STAGE_NAME="Planner" ;;
esac

# --- Write to tracker-debug.log for force-agent-read.sh ---
TRACKER_LOG="$PROJECT_DIR/.tasuki/config/tracker-debug.log"
if [ "$STAGE_NUM" -gt 0 ] && [ -n "$FILE_PATH" ]; then
  mkdir -p "$(dirname "$TRACKER_LOG")"
  echo "$(date '+%Y-%m-%d %H:%M:%S') READ $FILE_PATH [stage=$STAGE_NUM $STAGE_NAME]" >> "$TRACKER_LOG"

  # Rotate log if it exceeds 500 lines (prevent infinite growth)
  if [ -f "$TRACKER_LOG" ]; then
    LOG_LINES=$(wc -l < "$TRACKER_LOG" 2>/dev/null || echo "0")
    if [ "$LOG_LINES" -gt 500 ]; then
      tail -200 "$TRACKER_LOG" > "$TRACKER_LOG.tmp" && mv "$TRACKER_LOG.tmp" "$TRACKER_LOG"
    fi
  fi
fi

# --- RAG auto-sync on memory-vault writes ---
case "$FILE_PATH" in
  *memory-vault/*)
    TASUKI_BIN=$(command -v tasuki 2>/dev/null || echo "")
    if [ -n "$TASUKI_BIN" ]; then
      "$TASUKI_BIN" vault sync "$PROJECT_DIR" &>/dev/null &
    fi
    exit 0
    ;;
esac

# --- Detect test runs from Bash commands ---
IS_TEST_RUN=false
TEST_FRAMEWORK=""
if [ -n "$COMMAND" ]; then
  case "$COMMAND" in
    *pytest*|*py.test*)   IS_TEST_RUN=true; TEST_FRAMEWORK="pytest" ;;
    *jest*|*vitest*)      IS_TEST_RUN=true; TEST_FRAMEWORK="jest" ;;
    *mocha*)              IS_TEST_RUN=true; TEST_FRAMEWORK="mocha" ;;
    *go\ test*)           IS_TEST_RUN=true; TEST_FRAMEWORK="go" ;;
    *rspec*)              IS_TEST_RUN=true; TEST_FRAMEWORK="rspec" ;;
    *manage.py\ test*)    IS_TEST_RUN=true; TEST_FRAMEWORK="django" ;;
  esac
fi

# --- If no stage change and no test run and no file edit, skip ---
if [ "$STAGE_NUM" -eq 0 ] && [ "$IS_TEST_RUN" = false ] && [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- No progress file and no stage detected? Skip ---
if [ ! -f "$PROGRESS_FILE" ] && [ "$STAGE_NUM" -eq 0 ]; then
  exit 0
fi

# Initialize progress file if needed
if [ ! -f "$PROGRESS_FILE" ] && [ "$STAGE_NUM" -gt 0 ]; then
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  cat > "$PROGRESS_FILE" << EOF
{
  "task": "pipeline",
  "mode": "standard",
  "started": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "running",
  "current_stage": $STAGE_NUM,
  "total_stages": 9,
  "stages": {}
}
EOF
fi

# --- Update state with Python (atomic, reliable) ---
if [ -f "$PROGRESS_FILE" ] && command -v python3 &>/dev/null; then
  IS_TEST_PY=$( [ "$IS_TEST_RUN" = true ] && echo "True" || echo "False" )
  NOW_DATE=$(date "+%Y-%m-%d %H:%M:%S")
  NOW_TIME=$(date "+%H:%M:%S")
  NOW_SHORT=$(date "+%Y-%m-%d %H:%M")
  # Resolve pipeline_state.py location (works from installed or source)
  HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PIPELINE_STATE=""
  # Check relative to hook location (installed: .tasuki/hooks/ → engine is ../../src/engine/)
  for candidate in \
    "$HOOK_DIR/../../src/engine/pipeline_state.py" \
    "$(command -v tasuki 2>/dev/null | xargs readlink -f 2>/dev/null | xargs dirname 2>/dev/null)/../src/engine/pipeline_state.py" \
    "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/pipeline_state.py"; do
    [ -f "$candidate" ] && PIPELINE_STATE="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" && break
  done 2>/dev/null
  if [ -n "$PIPELINE_STATE" ]; then
    python3 "$PIPELINE_STATE" "$PROGRESS_FILE" "$STAGE_NUM" "$STAGE_NAME" "$FILE_PATH" "$TOOL_NAME" "$IS_TEST_PY" "$TEST_FRAMEWORK" "$PROJECT_DIR" "$NOW_DATE" "$NOW_TIME" "$NOW_SHORT"
  fi
fi

exit 0
