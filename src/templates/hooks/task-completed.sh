#!/bin/bash
# Tasuki Hook — TaskCompleted
# Runs when a Claude Agent Teams task is being marked as completed.
# Validates that the task's acceptance criteria are actually met.
#
# Exit 0 = task completes (normal)
# Exit 2 + stderr = completion blocked, feedback sent to teammate

set +e

INPUT=$(cat)

# Extract task info from hook input
TASK_SUBJECT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('task_subject', ''))
except:
    print('')
" 2>/dev/null)

TEAMMATE_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('teammate_name', ''))
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

# Find project root
PROJECT_ROOT="$CWD"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -d "$PROJECT_ROOT/.tasuki" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done
[ ! -d "$PROJECT_ROOT/.tasuki" ] && exit 0

ISSUES=""

# Validate based on which teammate is completing
case "$TEAMMATE_NAME" in
  qa)
    # QA must have created test files that FAIL (TDD red phase)
    NEW_TESTS=$(find "$PROJECT_ROOT" -name "test_*.py" -o -name "*.test.ts" -o -name "*.spec.ts" -mmin -60 2>/dev/null | wc -l)
    if [ "$NEW_TESTS" -eq 0 ]; then
      ISSUES="No test files created. QA must write failing tests before completing."
    fi
    ;;

  db-architect)
    # DBA must have created migration files
    # Find migration directory by checking common locations (project-facts.md is markdown, not JSON)
    MIGRATIONS_DIR=""
    for dir in alembic/versions db/migrate database/migrations migrations prisma/migrations; do
      if [ -d "$PROJECT_ROOT/$dir" ]; then
        MIGRATIONS_DIR="$PROJECT_ROOT/$dir"
        break
      fi
    done

    if [ -n "$MIGRATIONS_DIR" ]; then
      NEW_MIGRATIONS=$(find "$MIGRATIONS_DIR" -type f -newer "$PROJECT_ROOT/.tasuki/config/pipeline-progress.json" 2>/dev/null | wc -l)
      if [ "$NEW_MIGRATIONS" -eq 0 ]; then
        # Fallback: check files modified in last 60 minutes
        NEW_MIGRATIONS=$(find "$MIGRATIONS_DIR" -type f -mmin -60 2>/dev/null | wc -l)
      fi
      if [ "$NEW_MIGRATIONS" -eq 0 ]; then
        ISSUES="No new migration files found in $MIGRATIONS_DIR. DB Architect should create migrations before completing."
      fi
    else
      ISSUES="No migration directory found. DB Architect should create migrations before completing."
    fi
    ;;

  backend-dev|frontend-dev)
    # Dev must have passing tests
    TEST_CMD=""
    if [ -f "$PROJECT_ROOT/package.json" ]; then
      TEST_CMD="npm test 2>&1"
    elif [ -f "$PROJECT_ROOT/pytest.ini" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
      TEST_CMD="python -m pytest --tb=short 2>&1"
    fi

    if [ -n "$TEST_CMD" ]; then
      TEST_OUTPUT=$(cd "$PROJECT_ROOT" && eval "$TEST_CMD" 2>&1 || true)
      TEST_EXIT=$?
      if [ "$TEST_EXIT" -ne 0 ]; then
        ISSUES="Tests are failing. Fix all tests before completing.\n\n$(echo "$TEST_OUTPUT" | tail -15)"
      fi
    fi
    ;;

  security)
    # Security must have written an audit report
    REPORT=$(find "$PROJECT_ROOT/tasuki-plans" -name "security-*.md" -mmin -60 2>/dev/null | head -1)
    if [ -z "$REPORT" ]; then
      ISSUES="No security audit report found in tasuki-plans/. Write your findings before completing."
    fi
    ;;

  reviewer)
    # Reviewer completing = final approval — verify no CRITICAL issues remain
    # Look for review file in tasuki-plans/ (newer files preferred)
    REVIEW_FILE=$(find "$PROJECT_ROOT/tasuki-plans" -name "review*.md" -mmin -120 2>/dev/null | head -1)
    if [ -z "$REVIEW_FILE" ]; then
      # Also check the hardcoded path for backwards compat
      [ -f "$PROJECT_ROOT/tasuki-plans/review-latest.md" ] && REVIEW_FILE="$PROJECT_ROOT/tasuki-plans/review-latest.md"
    fi

    if [ -z "$REVIEW_FILE" ]; then
      ISSUES="No review file found in tasuki-plans/. Write your verdict to tasuki-plans/review-latest.md before completing."
    else
      # Count lines that say "CRITICAL: N" where N >= 1 (e.g. "CRITICAL: 2")
      # Avoids false positives from markdown headings like "### CRITICAL (blocking)"
      # or summary lines like "CRITICAL: 0"
      ACTUAL_CRITICALS=$(grep -cP "^CRITICAL:\s*[1-9]" "$REVIEW_FILE" 2>/dev/null || echo "0")
      ACTUAL_CRITICALS=$(echo "$ACTUAL_CRITICALS" | tr -d '[:space:]')
      ACTUAL_CRITICALS="${ACTUAL_CRITICALS:-0}"
      if [ "$ACTUAL_CRITICALS" -gt 0 ] 2>/dev/null; then
        ISSUES="$ACTUAL_CRITICALS CRITICAL issue(s) in review report. Resolve all CRITICALs before approving."
      fi
    fi
    ;;
esac

# --- Decision ---
if [ -n "$ISSUES" ]; then
  echo -e "$ISSUES" >&2
  exit 2  # Block completion, send feedback
fi

exit 0
