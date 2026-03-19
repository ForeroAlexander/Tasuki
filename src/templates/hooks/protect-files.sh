#!/bin/bash
# Tasuki Hook: protect-files
# PreToolUse — blocks edits to sensitive files.
# Reads patterns from .tasuki/config/protected-files.txt if it exists.

_log_block() {
  local hook="$1" detail="$2"
  local af="$PROJECT_ROOT/.tasuki/config/activity-log.json"
  if [ -f "$af" ] && command -v python3 &>/dev/null; then
    local logger=""
    for candidate in \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../src/engine/hook_logger.py" \
      "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/hook_logger.py"; do
      [ -f "$candidate" ] && logger="$candidate" && break
    done 2>/dev/null
    [ -n "$logger" ] && python3 "$logger" "$af" "$(date '+%Y-%m-%d %H:%M:%S')" "$hook" "$detail"
  fi
}

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract file_path — grep-based (works without jq)
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
fi

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
  # Check against default protected patterns
  # Use basename/dirname matching to avoid over-matching (e.g., .envrc is NOT .env)
  FILE_BASENAME=$(basename "$FILE_PATH")
  BLOCKED=false
  REASON=""

  case "$FILE_BASENAME" in
    .env|.env.*)          BLOCKED=true; REASON=".env file" ;;
    package-lock.json)    BLOCKED=true; REASON="lock file" ;;
    pnpm-lock.yaml)       BLOCKED=true; REASON="lock file" ;;
    yarn.lock)            BLOCKED=true; REASON="lock file" ;;
  esac

  # Path-based patterns
  if [ "$BLOCKED" = false ]; then
    case "$FILE_PATH" in
      */secrets/*)        BLOCKED=true; REASON="secrets directory" ;;
      */credentials/*)    BLOCKED=true; REASON="credentials directory" ;;
      */.git/*)           BLOCKED=true; REASON=".git directory" ;;
      */node_modules/*)   BLOCKED=true; REASON="node_modules" ;;
    esac
  fi

  if [ "$BLOCKED" = true ]; then
    echo "BLOCKED: Cannot edit protected file: $FILE_PATH ($REASON)" >&2
    _log_block "protect-files" "Blocked edit to protected file: $FILE_PATH"
    exit 2
  fi
fi

exit 0
