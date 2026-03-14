#!/bin/bash
# Tasuki Hook: Force Agent Read
# PreToolUse hook for Edit|Write — blocks code changes unless
# the appropriate agent file was read first.
# This ensures agents ALWAYS load their memory, heuristics, and graph expansion.
#
# How it works:
# - pipeline-tracker.sh logs which agent files Claude reads to tracker-debug.log
# - This hook checks if any agent was read before allowing edits
# - If no agent was read, it returns exit code 2 (BLOCK) with a message
# - Config files, tests, docs, and non-code files are exempt

set +e
set +o pipefail

PROJECT_DIR="${PWD}"
TRACKER_LOG="$PROJECT_DIR/.tasuki/config/tracker-debug.log"
AGENTS_DIR="$PROJECT_DIR/.tasuki/agents"

# Only enforce if tasuki is set up
[ ! -d "$PROJECT_DIR/.tasuki" ] && exit 0
[ ! -d "$AGENTS_DIR" ] && exit 0

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

# --- Exemptions: files that don't need an agent read ---
case "$FILE_PATH" in
  # Tasuki config files
  *.tasuki/*|*tasuki-plans/*|*memory-vault/*|*CLAUDE.md|*TASUKI.md)
    exit 0 ;;
  # Config files
  *.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.env*|*.gitignore)
    exit 0 ;;
  # Documentation
  *.md|*.txt|*.rst)
    exit 0 ;;
  # Test files (QA writes these)
  *test_*|*_test.*|*.test.*|*.spec.*|*conftest*|*fixture*)
    exit 0 ;;
  # Migrations
  *migration*|*alembic*)
    exit 0 ;;
  # Docker/CI
  *Dockerfile*|*docker-compose*|*.github/*|*.gitlab-ci*)
    exit 0 ;;
  # Lock files
  *lock*|*Lock*)
    exit 0 ;;
esac

# --- Check if any agent file was read in this session ---
# The tracker logs every Read of an agent file
AGENT_READ=false

if [ -f "$TRACKER_LOG" ]; then
  # Check if any .tasuki/agents/*.md appears in the tracker log
  if grep -q "agents/.*\.md" "$TRACKER_LOG" 2>/dev/null; then
    AGENT_READ=true
  fi
fi

# Also check the progress file — if a stage is running, an agent was read
PROGRESS_FILE="$PROJECT_DIR/.tasuki/config/pipeline-progress.json"
if [ -f "$PROGRESS_FILE" ]; then
  if grep -q '"running"' "$PROGRESS_FILE" 2>/dev/null; then
    AGENT_READ=true
  fi
fi

if [ "$AGENT_READ" = false ]; then
  echo "BLOCKED: Read an agent file first before editing code."
  echo ""
  echo "Tasuki requires you to load agent context before making changes."
  echo "Run: Read .tasuki/agents/backend-dev.md (or the appropriate agent)"
  echo ""
  echo "This ensures you load memory, heuristics, and project context."
  echo "Exempt: config files, docs, tests, migrations, Docker files."

  # Log to activity
  ACTIVITY_FILE="$PROJECT_DIR/.tasuki/config/activity-log.json"
  if [ -f "$ACTIVITY_FILE" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json
try:
    with open('$ACTIVITY_FILE') as f: data = json.load(f)
    data['events'].append({'time':'$(date "+%Y-%m-%d %H:%M:%S")','type':'hook_blocked','agent':'force-agent-read','detail':'Blocked edit — no agent file read yet'})
    data['events'] = data['events'][-100:]
    with open('$ACTIVITY_FILE','w') as f: json.dump(data, f, indent=2)
except: pass
" 2>/dev/null
  fi
  exit 2
fi

exit 0
