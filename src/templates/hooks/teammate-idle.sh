#!/bin/bash
# Tasuki Hook — TeammateIdle
# Runs when a Claude Agent Teams teammate is about to go idle.
# Quality gate: validates tests pass and no security issues before allowing idle.
#
# Exit 0 = teammate goes idle (normal)
# Exit 2 + stderr = teammate receives feedback and continues working

set +e

INPUT=$(cat)

# Extract teammate info from hook input
TEAMMATE_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('teammate_name', ''))
except:
    print('')
" 2>/dev/null)

TEAM_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('team_name', ''))
except:
    print('')
" 2>/dev/null)

CWD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('cwd', ''))
except:
    print('')
" 2>/dev/null)

[ -z "$CWD" ] && exit 0

# Skip validation for planner — it doesn't write code
case "$TEAMMATE_NAME" in
  planner) exit 0 ;;
esac

# Find project root (look for .tasuki/)
PROJECT_ROOT="$CWD"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.tasuki" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done
[ ! -d "$PROJECT_ROOT/.tasuki" ] && exit 0

# --- Quality Gates ---

ISSUES=""

# Gate 1: Run tests if test command is configured
TEST_CMD=$(grep -oP '"test_command":\s*"\K[^"]*' "$PROJECT_ROOT/.tasuki/config/project-facts.md" 2>/dev/null || true)
if [ -z "$TEST_CMD" ]; then
  # Fallback: try common test runners
  if [ -f "$PROJECT_ROOT/package.json" ]; then
    TEST_CMD="npm test 2>&1"
  elif [ -f "$PROJECT_ROOT/pytest.ini" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    TEST_CMD="python -m pytest --tb=short 2>&1"
  fi
fi

if [ -n "$TEST_CMD" ]; then
  TEST_OUTPUT=$(cd "$PROJECT_ROOT" && eval "$TEST_CMD" 2>&1 || true)
  TEST_EXIT=$?
  if [ "$TEST_EXIT" -ne 0 ]; then
    ISSUES="Tests are failing. Fix them before marking your work complete.\n\nTest output (last 20 lines):\n$(echo "$TEST_OUTPUT" | tail -20)"
  fi
fi

# Gate 2: Check for security anti-patterns in recently modified files
RECENT_FILES=$(find "$PROJECT_ROOT" -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -mmin -10 2>/dev/null | head -20)
if [ -n "$RECENT_FILES" ]; then
  SECURITY_HITS=""
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    # Check for hardcoded secrets
    if grep -nP '(password|secret|api_key|token)\s*=\s*["\x27][^"\x27]{8,}' "$file" 2>/dev/null | grep -v "test\|example\|placeholder" | head -3; then
      SECURITY_HITS="$SECURITY_HITS\n  - Possible hardcoded secret in $file"
    fi
  done <<< "$RECENT_FILES"

  if [ -n "$SECURITY_HITS" ]; then
    ISSUES="$ISSUES\n\nSecurity issues found:$SECURITY_HITS\nRemove hardcoded secrets and use environment variables instead."
  fi
fi

# Gate 3: Verify teammate completed their specific scope
case "$TEAMMATE_NAME" in
  qa)
    # QA should have created test files
    NEW_TESTS=$(find "$PROJECT_ROOT" -name "test_*.py" -o -name "*.test.ts" -o -name "*.spec.ts" -mmin -30 2>/dev/null | wc -l)
    if [ "$NEW_TESTS" -eq 0 ]; then
      ISSUES="$ISSUES\n\nNo new test files found. QA teammate should create test files before going idle."
    fi
    ;;
  backend-dev|frontend-dev)
    # Devs should have passing tests
    # Already covered by Gate 1
    ;;
  security)
    # Security should have produced a report
    REPORT=$(find "$PROJECT_ROOT/tasuki-plans" -name "security-*.md" -mmin -30 2>/dev/null | head -1)
    if [ -z "$REPORT" ]; then
      ISSUES="$ISSUES\n\nNo security audit report found. Write findings to tasuki-plans/ before going idle."
    fi
    ;;
esac

# --- Decision ---
if [ -n "$ISSUES" ]; then
  echo -e "$ISSUES" >&2
  exit 2  # Teammate continues working
fi

exit 0
