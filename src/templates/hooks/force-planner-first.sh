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

# Read tool input from stdin
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract file path being edited
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
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

# --- Check if a plan exists ---
PLAN_EXISTS=false

if [ -d "$PLANS_DIR" ]; then
  # Look for any prd.md, plan.md, or status.md in subdirectories
  PLAN_COUNT=$(find "$PLANS_DIR" -name "prd.md" -o -name "plan.md" -o -name "status.md" 2>/dev/null | head -1)
  if [ -n "$PLAN_COUNT" ]; then
    PLAN_EXISTS=true
  fi
fi

# Also check progress — if Planner stage is done, allow
PROGRESS_FILE="$PROJECT_DIR/.tasuki/config/pipeline-progress.json"
if [ -f "$PROGRESS_FILE" ]; then
  if grep -q '"Planner"' "$PROGRESS_FILE" 2>/dev/null; then
    PLAN_EXISTS=true
  fi
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
    python3 -c "
import json
try:
    with open('$ACTIVITY_FILE') as f: data = json.load(f)
    data['events'].append({'time':'$(date "+%Y-%m-%d %H:%M:%S")','type':'hook_blocked','agent':'force-planner-first','detail':'Blocked edit — no plan exists yet'})
    data['events'] = data['events'][-100:]
    with open('$ACTIVITY_FILE','w') as f: json.dump(data, f, indent=2)
except: pass
" 2>/dev/null
  fi
  exit 2
fi

exit 0
