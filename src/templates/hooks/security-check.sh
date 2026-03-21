#!/bin/bash
# Tasuki Hook: security-check
# PreToolUse — detects security anti-patterns at write-time.
# Multi-stack: Python, JavaScript/TypeScript, Go, Ruby, Docker.

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Extract fields
TOOL_NAME=""
FILE_PATH=""
CONTENT=""
if [ -n "$INPUT" ]; then
  TOOL_NAME=$(printf '%s\n' "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  # Extract content to scan: new_string (Edit) or content (Write)
  # Use python3 for reliable JSON extraction (grep stops at first quote)
  if command -v python3 &>/dev/null; then
    CONTENT=$(printf '%s\n' "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', data)
    if isinstance(inp, str): inp = json.loads(inp)
    print(inp.get('new_string', inp.get('content', '')))
except:
    print('')
" 2>/dev/null)
  else
    # Fallback: scan full input (may over-match on old_string but better than missing threats)
    CONTENT="$INPUT"
  fi
  # If python3 extraction returned empty but we have input, use input as fallback
  if [[ -z "$CONTENT" && -n "$INPUT" ]]; then
    CONTENT="$INPUT"
  fi
fi

# Only exit 0 if we know for certain it's NOT an edit/write tool
# If TOOL_NAME is empty (parse failure), don't silently bypass — scan anyway
if [[ -n "$TOOL_NAME" && "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi
# If TOOL_NAME is empty and no content to scan, allow
if [[ -z "$FILE_PATH" && -z "$CONTENT" ]]; then
  exit 0
fi

ISSUES=()

# --- Python checks ---
if [[ "$FILE_PATH" == *.py ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pn '\.execute\s*\(\s*f["\x27]' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: f-string inside .execute(). Use parameterized queries.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'text\s*\(\s*f["\x27]' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: f-string inside text(). Use parameterized queries.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'pickle\.loads?\s*\(' > /dev/null 2>&1; then
    ISSUES+=("DESERIALIZATION: pickle.loads() is unsafe. Use JSON.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'os\.system\s*\(' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: os.system() is unsafe. Use subprocess.run() with a list.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'subprocess\.\w+\s*\(.*shell\s*=\s*True' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: subprocess with shell=True. Pass arguments as a list.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'eval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous. Use ast.literal_eval() for data parsing.")
  fi
fi

# --- JavaScript / TypeScript checks ---
if [[ "$FILE_PATH" == *.js || "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx || "$FILE_PATH" == *.jsx ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pn '\beval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous. Find an alternative.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'innerHTML\s*=' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: innerHTML assignment. Use textContent or sanitize with DOMPurify.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'child_process\.exec\s*\(' > /dev/null 2>&1; then
    if printf '%s\n' "$CONTENT" | grep -Pn 'child_process\.exec\s*\(.*\$\{' > /dev/null 2>&1; then
      ISSUES+=("SHELL INJECTION: child_process.exec with interpolation. Use execFile() with args array.")
    fi
  fi
fi

# --- Svelte checks ---
if [[ "$FILE_PATH" == *.svelte ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pn '\{@html\b' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: {@html} renders raw HTML. Sanitize with DOMPurify.")
  fi
fi

# --- Go checks ---
if [[ "$FILE_PATH" == *.go ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pn 'fmt\.Sprintf\s*\(.*(SELECT|INSERT|UPDATE|DELETE)' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: fmt.Sprintf used for SQL query. Use parameterized queries.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'exec\.Command\s*\(.*\+' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: String concatenation in exec.Command. Use separate args.")
  fi
fi

# --- Ruby checks ---
if [[ "$FILE_PATH" == *.rb ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pn '\.html_safe' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: .html_safe bypasses escaping. Ensure content is sanitized.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn 'system\s*\(' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: system() with user input. Use Open3 with separate args.")
  fi
  if printf '%s\n' "$CONTENT" | grep -Pn '\beval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous in Ruby.")
  fi
fi

# --- Dockerfile checks ---
if [[ "$FILE_PATH" == *Dockerfile* ]]; then
  if printf '%s\n' "$CONTENT" | grep -Pq '^\s*FROM\s+'; then
    if ! printf '%s\n' "$CONTENT" | grep -Pq '^\s*USER\s+'; then
      ISSUES+=("DOCKER ROOT: Container runs as root. Add a USER directive.")
    fi
  fi
fi

# --- Universal: Hardcoded secrets ---
if printf '%s\n' "$CONTENT" | grep -Pn '(?i)(api_key|secret_key|password|api_secret|auth_token|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}["\x27]' > /dev/null 2>&1; then
  MATCHED=$(printf '%s\n' "$CONTENT" | grep -Pin '(?i)(api_key|secret_key|password|api_secret|auth_token|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}["\x27]' | head -1)
  if ! printf '%s\n' "$MATCHED" | grep -Piq '(os\.getenv|environ|\.get\(|config\[|settings\.|process\.env|change-me|placeholder|example|REPLACE_ME|TODO|test|mock|fake|dummy)'; then
    ISSUES+=("HARDCODED SECRET: Possible hardcoded credential. Use environment variables.")
  fi
fi

# --- Report ---
if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "SECURITY CHECK FAILED for: $FILE_PATH" >&2
  echo "---" >&2
  for issue in "${ISSUES[@]}"; do
    echo "  - $issue" >&2
  done
  echo "---" >&2
  echo "Fix the issues above or add a comment explaining why the pattern is safe." >&2

  # Log to activity
  PROJECT_ROOT="$(pwd)"
  ACTIVITY_FILE="$PROJECT_ROOT/.tasuki/config/activity-log.json"
  ISSUE_SUMMARY=$(printf '%s; ' "${ISSUES[@]}" | head -c 120)
  if [ -f "$ACTIVITY_FILE" ] && command -v python3 &>/dev/null; then
    logger=""
    for candidate in \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../src/engine/hook_logger.py" \
      "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/hook_logger.py"; do
      [ -f "$candidate" ] && logger="$candidate" && break
    done 2>/dev/null
    [ -n "$logger" ] && python3 "$logger" "$ACTIVITY_FILE" "$(date '+%Y-%m-%d %H:%M:%S')" "security-check" "Blocked: $ISSUE_SUMMARY"
  fi
  exit 2
fi

exit 0
