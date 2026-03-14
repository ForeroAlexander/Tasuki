#!/bin/bash
# Tasuki Hook: Pipeline Trigger
# UserPromptSubmit hook — runs when user sends a message.
# Activates the pipeline ONLY when the user says "tasuki" in their prompt.
# Simple, predictable, no false positives.
#
# Examples that trigger:
#   "tasuki: add a login endpoint"
#   "tasuki add payments"
#   "hey tasuki, fix the auth bug"
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
PROMPT=$(echo "$INPUT" | grep -oP '"prompt"\s*:\s*"\K[^"]*' 2>/dev/null || true)

[ -z "$PROMPT" ] && exit 0

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Only trigger on "tasuki" keyword
if ! echo "$LOWER" | grep -qE '(^|\s)tasuki(\s|:|$)'; then
  exit 0
fi

# Skip if user says "skip pipeline" or "no pipeline"
if echo "$LOWER" | grep -qE '(skip|no|don.t|without).*(pipeline|stages)'; then
  exit 0
fi

# Initialize progress with the task description
PROGRESS_FILE="${PWD}/.tasuki/config/pipeline-progress.json"
if [ -d "${PWD}/.tasuki" ]; then
  mkdir -p "$(dirname "$PROGRESS_FILE")"

  # Read mode
  MODE="standard"
  [ -f "${PWD}/.tasuki/config/mode" ] && MODE=$(cat "${PWD}/.tasuki/config/mode" 2>/dev/null || echo "standard")

  # Clean task name (remove "tasuki:" or "tasuki " prefix)
  TASK_NAME=$(echo "$PROMPT" | sed 's/^[[:space:]]*[Tt]asuki[: ]*//' | head -c 80)

  cat > "$PROGRESS_FILE" << PEOF
{
  "task": "$TASK_NAME",
  "mode": "$MODE",
  "started": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "running",
  "current_stage": 0,
  "total_stages": 9,
  "stages": {}
}
PEOF
fi

echo ""
echo "IMPORTANT: Follow the pipeline defined in TASUKI.md (or your AI tool's equivalent). Execute stages sequentially. Read each agent file at .tasuki/agents/{name}.md BEFORE executing that stage."
echo ""

exit 0
