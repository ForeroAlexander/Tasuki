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

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract file_path — grep-based (works without jq)
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH=$(printf '%s' "$INPUT" | json_field file_path)
fi

if [ -z "$FILE_PATH" ]; then
  # Fail closed: input arrived but no path could be read from it. If the raw
  # payload mentions a protected pattern, block rather than guess.
  if [ -n "$INPUT" ]; then
    _RAW_CONFIG="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/.tasuki/config/protected-files.txt"
    if [ -f "$_RAW_CONFIG" ]; then
      while IFS= read -r pattern; do
        [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
        if [[ "$INPUT" == *"$pattern"* ]]; then
          echo "BLOCKED: could not read the target path, and the request mentions protected pattern: $pattern" >&2
          exit 2
        fi
      done < "$_RAW_CONFIG"
    elif [[ "$INPUT" == *".env"* || "$INPUT" == *"package-lock.json"* || "$INPUT" == *"pnpm-lock.yaml"* || "$INPUT" == *"yarn.lock"* ]]; then
      echo "BLOCKED: could not read the target path, and the request mentions a protected file" >&2
      exit 2
    fi
  fi
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
