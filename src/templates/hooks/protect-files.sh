#!/bin/bash
# Tasuki Hook: protect-files
# PreToolUse — blocks edits to sensitive files.
# Reads patterns from .tasuki/config/protected-files.txt if it exists.

_log_block() {
  local hook="$1" detail="$2"
  local af="$PROJECT_ROOT/.tasuki/config/activity-log.json"
  [ -f "$af" ] && command -v python3 &>/dev/null && python3 -c "
import json
try:
    with open('$af') as f: d=json.load(f)
    d['events'].append({'time':'$(date "+%Y-%m-%d %H:%M:%S")','type':'hook_blocked','agent':'$hook','detail':'$detail'})
    d['events']=d['events'][-100:]
    with open('$af','w') as f: json.dump(d,f,indent=2)
except: pass
" 2>/dev/null
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
CONFIG_FILE="$PROJECT_ROOT/.tasuki/config/protected-files.txt"

if [ -f "$CONFIG_FILE" ]; then
  while IFS= read -r pattern; do
    [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
    if [[ "$FILE_PATH" == *"$pattern"* ]]; then
      echo "BLOCKED: Cannot edit protected file: $FILE_PATH (pattern: $pattern)" >&2
      _log_block "protect-files" "Blocked edit to protected file: $FILE_PATH"
      exit 2
    fi
  done < "$CONFIG_FILE"
else
  PROTECTED=(
    ".env"
    ".env."
    "secrets/"
    "credentials"
    "package-lock.json"
    "pnpm-lock.yaml"
    "yarn.lock"
    ".git/"
    "node_modules/"
  )

  for pattern in "${PROTECTED[@]}"; do
    if [[ "$FILE_PATH" == *"$pattern"* ]]; then
      echo "BLOCKED: Cannot edit protected file: $FILE_PATH" >&2
      _log_block "protect-files" "Blocked edit to protected file: $FILE_PATH"
      exit 2
    fi
  done
fi

exit 0
