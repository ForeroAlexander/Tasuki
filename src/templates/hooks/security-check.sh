#!/bin/bash
# Tasuki Hook: security-check
# PreToolUse — detects security anti-patterns at write-time.
# Multi-stack: Python, JavaScript/TypeScript, Go, Ruby, Docker.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$TOOL_NAME" == "Edit" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
else
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
fi

ISSUES=()

# --- Python checks ---
if [[ "$FILE_PATH" == *.py ]]; then
  if echo "$CONTENT" | grep -Pn '\.execute\s*\(\s*f["\x27]' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: f-string inside .execute(). Use parameterized queries.")
  fi
  if echo "$CONTENT" | grep -Pn 'text\s*\(\s*f["\x27]' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: f-string inside text(). Use parameterized queries.")
  fi
  if echo "$CONTENT" | grep -Pn 'pickle\.loads?\s*\(' > /dev/null 2>&1; then
    ISSUES+=("DESERIALIZATION: pickle.loads() is unsafe. Use JSON.")
  fi
  if echo "$CONTENT" | grep -Pn 'os\.system\s*\(' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: os.system() is unsafe. Use subprocess.run() with a list.")
  fi
  if echo "$CONTENT" | grep -Pn 'subprocess\.\w+\s*\(.*shell\s*=\s*True' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: subprocess with shell=True. Pass arguments as a list.")
  fi
  if echo "$CONTENT" | grep -Pn 'eval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous. Use ast.literal_eval() for data parsing.")
  fi
fi

# --- JavaScript / TypeScript checks ---
if [[ "$FILE_PATH" == *.js || "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx || "$FILE_PATH" == *.jsx ]]; then
  if echo "$CONTENT" | grep -Pn '\beval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous. Find an alternative.")
  fi
  if echo "$CONTENT" | grep -Pn 'innerHTML\s*=' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: innerHTML assignment. Use textContent or sanitize with DOMPurify.")
  fi
  if echo "$CONTENT" | grep -Pn 'child_process\.exec\s*\(' > /dev/null 2>&1; then
    if echo "$CONTENT" | grep -Pn 'child_process\.exec\s*\(.*\$\{' > /dev/null 2>&1; then
      ISSUES+=("SHELL INJECTION: child_process.exec with interpolation. Use execFile() with args array.")
    fi
  fi
fi

# --- Svelte checks ---
if [[ "$FILE_PATH" == *.svelte ]]; then
  if echo "$CONTENT" | grep -Pn '\{@html\b' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: {@html} renders raw HTML. Sanitize with DOMPurify.")
  fi
fi

# --- Go checks ---
if [[ "$FILE_PATH" == *.go ]]; then
  if echo "$CONTENT" | grep -Pn 'fmt\.Sprintf\s*\(.*SELECT\|fmt\.Sprintf\s*\(.*INSERT\|fmt\.Sprintf\s*\(.*UPDATE\|fmt\.Sprintf\s*\(.*DELETE' > /dev/null 2>&1; then
    ISSUES+=("SQL INJECTION: fmt.Sprintf used for SQL query. Use parameterized queries.")
  fi
  if echo "$CONTENT" | grep -Pn 'exec\.Command\s*\(.*\+' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: String concatenation in exec.Command. Use separate args.")
  fi
fi

# --- Ruby checks ---
if [[ "$FILE_PATH" == *.rb ]]; then
  if echo "$CONTENT" | grep -Pn '\.html_safe' > /dev/null 2>&1; then
    ISSUES+=("XSS RISK: .html_safe bypasses escaping. Ensure content is sanitized.")
  fi
  if echo "$CONTENT" | grep -Pn 'system\s*\(' > /dev/null 2>&1; then
    ISSUES+=("SHELL INJECTION: system() with user input. Use Open3 with separate args.")
  fi
  if echo "$CONTENT" | grep -Pn '\beval\s*\(' > /dev/null 2>&1; then
    ISSUES+=("CODE INJECTION: eval() is dangerous in Ruby.")
  fi
fi

# --- Dockerfile checks ---
if [[ "$FILE_PATH" == *Dockerfile* ]]; then
  if echo "$CONTENT" | grep -Pq '^\s*FROM\s+'; then
    if ! echo "$CONTENT" | grep -Pq '^\s*USER\s+'; then
      ISSUES+=("DOCKER ROOT: Container runs as root. Add a USER directive.")
    fi
  fi
fi

# --- Universal: Hardcoded secrets ---
if echo "$CONTENT" | grep -Pn '(?i)(api_key|secret_key|password|api_secret|auth_token|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}["\x27]' > /dev/null 2>&1; then
  MATCHED=$(echo "$CONTENT" | grep -Pin '(?i)(api_key|secret_key|password|api_secret|auth_token|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}["\x27]' | head -1)
  if ! echo "$MATCHED" | grep -Piq '(os\.getenv|environ|\.get\(|config\[|settings\.|process\.env|change-me|placeholder|example|REPLACE_ME|TODO|test|mock|fake|dummy)'; then
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
    python3 -c "
import json
try:
    with open('$ACTIVITY_FILE') as f: data = json.load(f)
    data['events'].append({'time':'$(date "+%Y-%m-%d %H:%M:%S")','type':'hook_blocked','agent':'security-check','detail':'Blocked: $ISSUE_SUMMARY'})
    data['events'] = data['events'][-100:]
    with open('$ACTIVITY_FILE','w') as f: json.dump(data, f, indent=2)
except: pass
" 2>/dev/null
  fi
  exit 2
fi

exit 0
