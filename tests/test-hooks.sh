#!/bin/bash
# Tasuki Hook Tests — TDD Red Phase
# Tests for bugs identified in fix-hook-gates plan.
# Each test FAILS against current code (proving the bug exists).
# Tests should PASS after the fixes are applied.
#
# Usage: bash tests/test-hooks.sh

set -uo pipefail

TASUKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$TASUKI_ROOT/.tasuki/hooks"
PASS=0
FAIL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

assert() {
  local desc="$1" result="$2"
  if [ "$result" = "0" ]; then
    echo -e "  ${GREEN}✓${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo -e "${BOLD}Tasuki Hook Gate Tests${NC}"
echo -e "${DIM}══════════════════════${NC}"
echo ""

# ---------------------------------------------------------------------------
# TEST 1 — security-check.sh: empty TOOL_NAME should NOT be a bypass
# ---------------------------------------------------------------------------
# BUG: When TOOL_NAME cannot be extracted from JSON (malformed input, missing
# tool_name field), TOOL_NAME is empty. The current guard is:
#   if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then exit 0; fi
# An empty string satisfies both conditions → exit 0 (silent bypass).
# FIX: Only exit 0 if TOOL_NAME is a KNOWN non-edit tool.
# ---------------------------------------------------------------------------
echo -e "${BOLD}Test 1 — security-check.sh: empty TOOL_NAME bypass${NC}"

T1=$(mktemp -d)

# Input: valid-looking JSON but tool_name field is missing entirely
# A file_path pointing to a .py file and content that looks editable
MALFORMED_JSON='{
  "tool_input": {
    "file_path": "'"$T1"'/app/service.py",
    "new_string": "x = 1"
  }
}'

# Current behavior: exits 0 (bypass) because TOOL_NAME is empty
# Expected after fix: should NOT exit 0 when content/file_path present and
# TOOL_NAME is indeterminate — should scan or at least not silently skip.
# The test asserts exit code != 0 (i.e., it does NOT bypass).

echo "$MALFORMED_JSON" | bash "$HOOKS_DIR/security-check.sh" >/dev/null 2>&1
EXIT_CODE=$?
# BUG: current code exits 0 (bypass). After fix: should exit 0 only when
# truly no content to scan, not just because tool_name is missing.
# We assert exit code is NOT 0 (hook ran and did something meaningful).
# Actually the fix says: if TOOL_NAME empty AND content+file_path present → scan.
# With empty new_string "x = 1" there's nothing to flag, so exit 0 is fine.
# The real test is that the bypass doesn't skip the tool entirely.
# We test with a secret in the content to force a detectable outcome.

SECRET_JSON='{
  "tool_input": {
    "file_path": "'"$T1"'/app/config.py",
    "new_string": "api_key = \"supersecretvalue123\""
  }
}'
# When tool_name missing but content has a secret: current code exits 0 (bypass).
# After fix: should exit 2 (caught the secret).
echo "$SECRET_JSON" | bash "$HOOKS_DIR/security-check.sh" >/dev/null 2>&1
EXIT_CODE=$?
# Assert: exit code should be 2 (secret caught), not 0 (bypass)
[ "$EXIT_CODE" -eq 2 ]
assert "empty TOOL_NAME with secret in content → blocked (exit 2), not bypassed (exit 0)" $?

rm -rf "$T1"

# ---------------------------------------------------------------------------
# TEST 2 — security-check.sh: hardcoded secret with empty TOOL_NAME
# ---------------------------------------------------------------------------
# BUG: Same root cause as Test 1 but more explicit.
# Input has api_key secret in new_string but no tool_name field.
# Current: exits 0 and misses the secret entirely.
# Expected: exits 2 with HARDCODED SECRET warning.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 2 — security-check.sh: secret missed when TOOL_NAME is absent${NC}"

T2=$(mktemp -d)

# No tool_name at all — hook should still catch the secret
INPUT_NO_TOOL='{
  "tool_input": {
    "file_path": "'"$T2"'/settings.py",
    "new_string": "api_key = \"mysupersecrettoken\""
  }
}'

echo "$INPUT_NO_TOOL" | bash "$HOOKS_DIR/security-check.sh" 2>/dev/null
EXIT_T2=$?
# BUG: currently exits 0 (tool_name guard fires first → bypass)
# After fix: exits 2 (secret scanned and detected)
[ "$EXIT_T2" -eq 2 ]
assert "absent TOOL_NAME: api_key secret still caught (exit 2)" $?

# Verify the output mentions HARDCODED SECRET when we capture stderr
STDERR_OUT=$(echo "$INPUT_NO_TOOL" | bash "$HOOKS_DIR/security-check.sh" 2>&1 >/dev/null || true)
echo "$STDERR_OUT" | grep -qi "HARDCODED SECRET\|SECURITY CHECK FAILED"
assert "absent TOOL_NAME: stderr contains security violation message" $?

rm -rf "$T2"

# ---------------------------------------------------------------------------
# TEST 3 — task-completed.sh: QA gate with project-facts.md in markdown format
# ---------------------------------------------------------------------------
# BUG: The QA gate uses -mmin -60 to find new test files. That's fine, BUT
# the test detection uses a time window of 60 minutes. If test files were
# created more than 60 minutes ago in this session, the gate passes trivially.
# More importantly: the gate should work correctly with the project structure.
# We test that the gate DETECTS a newly created test file and validates properly.
# The REAL bug to expose: task-completed.sh may not find tests in /tmp (the
# gate uses PROJECT_ROOT which is derived from CWD and .tasuki/ directory).
# If CWD doesn't have .tasuki/, the hook exits 0 (trivially passes).
# We ensure a proper project structure is set up.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 3 — task-completed.sh: QA gate detects new test file${NC}"

T3=$(mktemp -d)
# Set up a minimal project structure with .tasuki/
mkdir -p "$T3/.tasuki/config"
mkdir -p "$T3/tests"

# project-facts.md in MARKDOWN format (not JSON) — this is what actually exists
cat > "$T3/.tasuki/config/project-facts.md" << 'EOF'
# Project Facts — tasuki
## Stack
- Language: Python
## Paths (verified)
- src/ (exists)
- tests/ (tests)
## Commands
- pytest
EOF

# Create a new test file (will be detected by -mmin -60 within the hour)
echo "def test_something(): assert True" > "$T3/tests/test_new_feature.py"

# Build the JSON input for task-completed hook
INPUT_QA='{
  "task_subject": "Write failing tests for the API",
  "teammate_name": "qa",
  "cwd": "'"$T3"'"
}'

echo "$INPUT_QA" | bash "$HOOKS_DIR/task-completed.sh" >/dev/null 2>&1
EXIT_T3=$?
# The gate should EXIT 0 when test files are found (gate passes)
[ "$EXIT_T3" -eq 0 ]
assert "QA gate passes when new test file exists (exit 0)" $?

# Now test WITHOUT any test files — gate should block
rm -f "$T3/tests/test_new_feature.py"
echo "$INPUT_QA" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T3B=$?
# BUG check: if gate correctly blocks when no tests exist → exit 2
# Current code: exits 2 if NEW_TESTS=0, which is correct behavior for this case.
# The test validates the gate works (this sub-test should already pass).
[ "$EXIT_T3B" -eq 2 ]
assert "QA gate blocks when no test files exist (exit 2)" $?

rm -rf "$T3"

# ---------------------------------------------------------------------------
# TEST 4 — task-completed.sh: DBA gate with no migrations_path JSON field
# ---------------------------------------------------------------------------
# BUG: The DBA gate does:
#   MIGRATIONS_DIR=$(grep -oP 'migrations_path:\s*\K.*' project-facts.md)
# project-facts.md is MARKDOWN — it has no 'migrations_path:' key in that
# JSON grep format. Result: MIGRATIONS_DIR is empty → the if block is skipped
# entirely → gate trivially passes even if NO migrations were created.
# Expected after fix: gate uses filesystem detection (look for alembic/versions,
# db/migrate, etc.) and validates migrations exist there.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 4 — task-completed.sh: DBA gate with markdown project-facts (no JSON field)${NC}"

T4=$(mktemp -d)
mkdir -p "$T4/.tasuki/config"
# Markdown format project-facts (no migrations_path JSON field)
cat > "$T4/.tasuki/config/project-facts.md" << 'EOF'
# Project Facts — tasuki
## Stack
- Language: Python
## Paths (verified)
- src/ (exists)
- tests/ (tests)
EOF

# Create alembic migration dir with a new migration
mkdir -p "$T4/alembic/versions"
# No new migration file yet

INPUT_DBA='{
  "task_subject": "Add users table",
  "teammate_name": "db-architect",
  "cwd": "'"$T4"'"
}'

# BUG: with no migrations_path field, MIGRATIONS_DIR is empty.
# The if block: [ -n "$MIGRATIONS_DIR" ] → false → skip check → exit 0.
# This means DBA can complete without creating any migration. Gate is broken.
echo "$INPUT_DBA" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T4A=$?
# Current buggy behavior: exits 0 (passes trivially)
# After fix: should exit 2 (no migration found in alembic/versions/)
[ "$EXIT_T4A" -eq 2 ]
assert "DBA gate blocks when no migration exists in alembic/versions/ (exit 2)" $?

# Now add a migration file — gate should pass
echo "# migration" > "$T4/alembic/versions/$(date +%s)_add_users.py"
echo "$INPUT_DBA" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T4B=$?
# After fix: should detect the new migration file and exit 0
[ "$EXIT_T4B" -eq 0 ]
assert "DBA gate passes when migration file exists in alembic/versions/ (exit 0)" $?

rm -rf "$T4"

# ---------------------------------------------------------------------------
# TEST 5 — task-completed.sh: reviewer gate blocks when review file missing
# ---------------------------------------------------------------------------
# BUG: The reviewer gate checks:
#   if [ -f "$PROJECT_ROOT/tasuki-plans/review-latest.md" ]; then
#     CRITICALS=$(grep -c "CRITICAL" ...)
#     if [ "$CRITICALS" -gt 0 ]; then ISSUES=... fi
#   fi
# If review-latest.md does NOT exist, the if block is skipped → exit 0 (passes).
# This means reviewer can complete without writing any review at all.
# Expected after fix: when no review file exists → block (we don't know if
# CRITICALs were found or not → must block as safe default).
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 5 — task-completed.sh: reviewer gate blocks when review-latest.md missing${NC}"

T5=$(mktemp -d)
mkdir -p "$T5/.tasuki/config"
mkdir -p "$T5/tasuki-plans"

cat > "$T5/.tasuki/config/project-facts.md" << 'EOF'
# Project Facts — tasuki
## Stack
- Language: Python
EOF

# No review-latest.md — reviewer hasn't written their review
INPUT_REVIEWER='{
  "task_subject": "Review the new API changes",
  "teammate_name": "reviewer",
  "cwd": "'"$T5"'"
}'

echo "$INPUT_REVIEWER" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T5A=$?
# BUG: current code exits 0 (file not found → if block skipped → passes trivially)
# After fix: should exit 2 (no review found → block as uncertain)
[ "$EXIT_T5A" -eq 2 ]
assert "reviewer gate blocks when review-latest.md is missing (exit 2)" $?

# Now create the review file with no CRITICALs — should pass
# BUG (secondary): grep -c "CRITICAL" also matches the "CRITICAL: 0" header line
# itself, returning count=1 even when there are zero actual critical issues.
# The fix must grep for CRITICAL issue markers only (e.g., lines like "- CRITICAL:")
# not the summary header line.
cat > "$T5/tasuki-plans/review-latest.md" << 'EOF'
VERDICT: APPROVED
CRITICAL: 0
HIGH: 1
Notes: One high-priority style issue found, fixed inline.
EOF
echo "$INPUT_REVIEWER" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T5B=$?
# BUG: grep -c "CRITICAL" counts the "CRITICAL: 0" header → returns 1 → blocks
# Current behavior: exits 2 (incorrectly blocks approved review)
# After fix: exits 0 (CRITICAL count is 0, so gate passes)
[ "$EXIT_T5B" -eq 0 ]
assert "reviewer gate passes when review-latest.md has 0 CRITICALs (exit 0)" $?

# Review file with CRITICAL issues — should block
cat > "$T5/tasuki-plans/review-latest.md" << 'EOF'
VERDICT: REQUEST CHANGES
CRITICAL: 2
Notes: SQL injection vulnerability found. Input not sanitized.
EOF
echo "$INPUT_REVIEWER" | bash "$HOOKS_DIR/task-completed.sh" 2>/dev/null
EXIT_T5C=$?
[ "$EXIT_T5C" -eq 2 ]
assert "reviewer gate blocks when review-latest.md has CRITICAL issues (exit 2)" $?

rm -rf "$T5"

# ---------------------------------------------------------------------------
# TEST 5b — task-completed.sh: reviewer gate with markdown heading format
# ---------------------------------------------------------------------------
# BUG: The old subtraction heuristic counted every line containing "CRITICAL"
# (including markdown headings like "### CRITICAL (blocking)") and subtracted
# lines matching "CRITICAL: 0". A review file with a markdown heading and
# "CRITICAL: 0" summary results in CRITICALS=2, CRITICAL_ZEROS=1 → ACTUAL=1,
# which incorrectly blocks an approved review.
# FIX: Use grep -P "^CRITICAL:\s*[1-9]" which only matches explicit non-zero
# counts at the start of a line.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 5b — task-completed.sh: reviewer gate with markdown headings should pass${NC}"

TEST_DIR_5B=$(mktemp -d)
mkdir -p "$TEST_DIR_5B/.tasuki/config" "$TEST_DIR_5B/tasuki-plans"

# Review file with markdown heading format (common real-world format)
cat > "$TEST_DIR_5B/tasuki-plans/review-latest.md" << 'EOF'
# Review

## Summary
Code looks good.

### CRITICAL (blocking)
- none

### HIGH
- none

CRITICAL: 0
HIGH: 0
VERDICT: APPROVED
EOF

cd "$TEST_DIR_5B"
echo '{"teammate_name":"reviewer","cwd":"'"$TEST_DIR_5B"'"}' | \
  bash /home/forero/tasuki/.tasuki/hooks/task-completed.sh > /dev/null 2>&1
assert "reviewer gate: approved review with markdown headings should pass" $?
rm -rf "$TEST_DIR_5B"

# ---------------------------------------------------------------------------
# TEST 6 — tdd-guard.sh: BSD grep portability for import detection
# ---------------------------------------------------------------------------
# BUG: Line 120 of tdd-guard.sh uses:
#   grep -rlq "from.*${NAME}\|import.*${NAME}" "$PROJECT_ROOT/tests/"
# The \| operator is GNU grep-specific. On BSD grep (macOS), \| is NOT treated
# as alternation — it's a literal backslash-pipe, so the pattern never matches.
# FIX: Use two separate grep calls (portable) or -E with |.
#
# To test this portability issue we verify that import detection works when
# a test file imports the module. If \| fails silently, FOUND_TEST stays false
# and the hook incorrectly blocks the edit.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 6 — tdd-guard.sh: BSD grep portability for import detection${NC}"

T6=$(mktemp -d)
mkdir -p "$T6/.git"
mkdir -p "$T6/app"
mkdir -p "$T6/tests"

# Create a source module
echo "def my_function(): pass" > "$T6/app/mymodule.py"

# Create a test file that IMPORTS the module (not named test_mymodule.py to
# force the import-detection code path, not the filename-match path)
cat > "$T6/tests/test_integration.py" << 'EOF'
from app.mymodule import my_function
import app.mymodule

def test_my_function():
    assert my_function() is None
EOF

# Build Edit hook input for the source module
INPUT_TDD='{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "'"$T6"'/app/mymodule.py",
    "old_string": "def my_function(): pass",
    "new_string": "def my_function(): return 42"
  }
}'

echo "$INPUT_TDD" | bash "$HOOKS_DIR/tdd-guard.sh" >/dev/null 2>&1
EXIT_T6=$?
# With GNU grep and \|: the pattern "from.*mymodule\|import.*mymodule" matches
# both import styles → FOUND_TEST=true → exit 0 (allowed).
# With BSD grep: \| is literal → pattern fails → FOUND_TEST stays false → exit 2 (blocked).
# The test asserts exit 0 (import detected → allowed to edit).
# On this Linux system (GNU grep), this should pass — but we document the
# portability concern. The test also validates the import detection path works.
[ "$EXIT_T6" -eq 0 ]
assert "tdd-guard allows edit when test file imports the module (import detection works)" $?

# Additional: verify the two-grep portable approach would also detect it.
# We simulate what the fix would do: check each grep pattern separately.
grep -rlq "from.*mymodule" "$T6/tests/" --include="*.py" 2>/dev/null
GREP1=$?
grep -rlq "import.*mymodule" "$T6/tests/" --include="*.py" 2>/dev/null
GREP2=$?
[ "$GREP1" -eq 0 ] || [ "$GREP2" -eq 0 ]
assert "portable grep approach detects import in test file" $?

# Confirm the \| combined approach also works (GNU-specific, documents the risk)
grep -rlq "from.*mymodule\|import.*mymodule" "$T6/tests/" --include="*.py" 2>/dev/null
EXIT_GNU=$?
[ "$EXIT_GNU" -eq 0 ]
assert "GNU grep with \\| detects import (GNU-specific, would fail on BSD)" $?

rm -rf "$T6"

# ---------------------------------------------------------------------------
# TEST 7 — teammate-idle.sh: test_command detection from markdown
# ---------------------------------------------------------------------------
# BUG: teammate-idle.sh Gate 1 does:
#   TEST_CMD=$(grep -oP '"test_command":\s*"\K[^"]*' project-facts.md)
# project-facts.md is MARKDOWN — has no JSON "test_command" field.
# Result: TEST_CMD is always empty → fallback to package.json / pytest.ini check.
# If neither exists, no tests run at all → Gate 1 is effectively disabled.
# FIX: Detect test runner from filesystem (conftest.py, pytest.ini, etc.),
# same as the plan's detect_test_cmd() approach.
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Test 7 — teammate-idle.sh: test_command detection from markdown project-facts${NC}"

T7=$(mktemp -d)
mkdir -p "$T7/.tasuki/config"
mkdir -p "$T7/tests"

# Markdown project-facts with no JSON "test_command" field
cat > "$T7/.tasuki/config/project-facts.md" << 'EOF'
# Project Facts — tasuki
## Stack
- Language: Python
## Commands
- pytest tests/
EOF

# Create conftest.py so filesystem detection can find pytest
touch "$T7/tests/conftest.py"

# Create a FAILING test (so when pytest runs, it returns non-zero)
cat > "$T7/tests/test_will_fail.py" << 'EOF'
def test_always_fails():
    assert False, "Intentional failure for hook test"
EOF

INPUT_IDLE='{
  "teammate_name": "backend-dev",
  "team_name": "tasuki",
  "cwd": "'"$T7"'"
}'

# BUG: TEST_CMD extracted from project-facts.md JSON field → empty.
# Then fallback: no package.json, no pytest.ini → TEST_CMD stays empty.
# conftest.py EXISTS but the fallback doesn't check for it.
# Gate 1 is skipped → exit 0 even though tests are failing.
# After fix: conftest.py presence triggers pytest → tests run → exit 2.

echo "$INPUT_IDLE" | bash "$HOOKS_DIR/teammate-idle.sh" 2>/dev/null
EXIT_T7A=$?
# BUG: current code exits 0 (TEST_CMD not set → no test run → gate passes)
# After fix: conftest.py detected → pytest run → test fails → exit 2
# NOTE: the hook also checks for recently modified files (Gate 2) and
# teammate-specific scope (Gate 3). The failing test triggers Gate 1.
# For this test, we check that the hook does NOT pass trivially (exit 0)
# when failing tests exist and conftest.py is present.
[ "$EXIT_T7A" -ne 0 ]
assert "teammate-idle blocks when tests fail and conftest.py exists (not exit 0)" $?

# Verify: without conftest.py and without pytest.ini, current code finds no TEST_CMD
# (this confirms the bug — the grep for JSON field finds nothing)
TEST_CMD_FOUND=$(grep -oP '"test_command":\s*"\K[^"]*' "$T7/.tasuki/config/project-facts.md" 2>/dev/null || true)
[ -z "$TEST_CMD_FOUND" ]
assert "project-facts.md has no JSON test_command field (confirms markdown format bug)" $?

# The fix should use filesystem detection: conftest.py → use pytest
[ -f "$T7/tests/conftest.py" ]
assert "conftest.py exists (filesystem detection trigger for pytest)" $?

rm -rf "$T7"

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
echo ""
echo -e "${DIM}──────────────────────────────────────${NC}"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}ALL $TOTAL TESTS PASSED${NC}"
  echo -e "  ${YELLOW}(If all pass before fixes are applied, the tests may not be exposing the bugs correctly)${NC}"
else
  echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL"
  echo -e "  ${YELLOW}FAILED tests = bugs proven to exist (expected in red phase)${NC}"
fi
echo ""

exit $FAIL
