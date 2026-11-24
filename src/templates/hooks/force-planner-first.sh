#!/bin/bash
# Tasuki Hook: Force Planner First
# PreToolUse hook for Edit|Write — blocks code changes unless
# a plan exists in tasuki-plans/ for the current task.
# This ensures the Planner stage runs before any implementation.
#
# How it works:
# - Checks if any PRD or plan file exists in tasuki-plans/
# - If no plan exists and Claude tries to edit code, block with exit 2
# - If a plan exists, allow (Planner already ran)
# - Fast mode is exempt (skips Planner by design)
# - Config files, tests, docs are exempt

set +e
set +o pipefail

PROJECT_DIR="${PWD}"
PLANS_DIR="$PROJECT_DIR/tasuki-plans"
MODE_FILE="$PROJECT_DIR/.tasuki/config/mode"

# Only enforce if tasuki is set up
[ ! -d "$PROJECT_DIR/.tasuki" ] && exit 0

# Fast mode skips Planner — exempt
if [ -f "$MODE_FILE" ]; then
  MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "standard")
  [ "$MODE" = "fast" ] && exit 0
fi

# --- JSON field reader (same block in every hook — keep in sync) ---
# Reads JSON on stdin, prints a scalar field. Looks inside tool_input first, then top level.
# Uses python3 -I (isolated: ignores the project dir and user site-packages, so a
# planted json.py cannot hijack the hook) so escaped quotes and newlines are handled;
# falls back to POSIX sed when python3 is missing. No GNU-only grep -P.
json_field() {
  local key="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
inner = d.get("tool_input")
if isinstance(inner, str):
    try:
        inner = json.loads(inner)
    except Exception:
        inner = None
for src in (inner, d):
    if isinstance(src, dict) and isinstance(src.get(sys.argv[1]), (str, int, float)) and not isinstance(src.get(sys.argv[1]), bool):
        print(src[sys.argv[1]])
        break
' "$key" 2>/dev/null
  else
    # Capture a full JSON string (stops only at an unescaped quote), else a bare number.
    tr '\n' ' ' | sed -E -n \
      -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' \
      -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1
  fi
}
# --- end JSON field reader ---

# Read tool input from stdin
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract file path being edited
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH=$(printf '%s' "$INPUT" | json_field file_path)
fi

[ -z "$FILE_PATH" ] && exit 0

# --- Exemptions ---
case "$FILE_PATH" in
  # Tasuki files (planner creates these)
  *.tasuki/*|*tasuki-plans/*|*memory-vault/*|*CLAUDE.md|*TASUKI.md)
    exit 0 ;;
  # Config files
  *.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.env*|*.gitignore)
    exit 0 ;;
  # Documentation
  *.md|*.txt|*.rst)
    exit 0 ;;
  # Test files (QA writes these before implementation)
  *test_*|*_test.*|*.test.*|*.spec.*|*conftest*|*fixture*)
    exit 0 ;;
  # Migrations (DBA creates these)
  *migration*|*alembic*)
    exit 0 ;;
  # Docker/CI
  *Dockerfile*|*docker-compose*|*.github/*|*.gitlab-ci*)
    exit 0 ;;
  # Lock files
  *lock*|*Lock*)
    exit 0 ;;
esac

# --- Check if a plan exists for the CURRENT task ---
PLAN_EXISTS=false

PROGRESS_FILE="$PROJECT_DIR/.tasuki/config/pipeline-progress.json"
if [ -f "$PROGRESS_FILE" ]; then
  # Check if Planner stage ran in the current pipeline
  if grep -q '"Planner"' "$PROGRESS_FILE" 2>/dev/null; then
    PLAN_EXISTS=true
  fi

  # Also check: if current_stage > 1, Planner already passed
  CURRENT_STAGE=$(json_field current_stage < "$PROGRESS_FILE" 2>/dev/null)
  CURRENT_STAGE="${CURRENT_STAGE:-0}"
  [ "$CURRENT_STAGE" -gt 1 ] 2>/dev/null && PLAN_EXISTS=true
fi

# Fallback: check if a plan was modified in the last 2 hours (active work)
if [ "$PLAN_EXISTS" = false ] && [ -d "$PLANS_DIR" ]; then
  RECENT_PLAN=$(find "$PLANS_DIR" -name "prd.md" -mmin -120 2>/dev/null | head -1)
  [ -n "$RECENT_PLAN" ] && PLAN_EXISTS=true
fi

if [ "$PLAN_EXISTS" = false ]; then
  echo "BLOCKED: Planner must run before implementation."
  echo ""
  echo "No plan found in tasuki-plans/. The Planner agent must:"
  echo "  1. Analyze the task"
  echo "  2. Create a PRD in tasuki-plans/{feature}/prd.md"
  echo "  3. Get your confirmation before proceeding"
  echo ""
  echo "Read .tasuki/agents/planner.md first to start planning."
  echo "Or switch to fast mode: tasuki mode fast"

  # Log to activity
  ACTIVITY_FILE="$PROJECT_DIR/.tasuki/config/activity-log.json"
  if [ -f "$ACTIVITY_FILE" ] && command -v python3 &>/dev/null; then
    logger=""
    for candidate in \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../src/engine/hook_logger.py" \
      "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/hook_logger.py"; do
      [ -f "$candidate" ] && logger="$candidate" && break
    done 2>/dev/null
    [ -n "$logger" ] && python3 "$logger" "$ACTIVITY_FILE" "$(date "+%Y-%m-%d %H:%M:%S")" "force-planner-first" "Blocked edit — no plan exists yet"
  fi
  exit 2
fi

exit 0
