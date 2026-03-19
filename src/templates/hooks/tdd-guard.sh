#!/bin/bash
# Tasuki Hook: TDD Guard
# PreToolUse hook for Edit|Write operations.
# Enforces TDD: blocks writing implementation code if corresponding tests don't exist.
# Exit 0 = allow, Exit 2 = block with message.
#
# How it works:
# 1. When you edit a source file (e.g., app/routers/users.py)
# 2. It checks if a test file exists (e.g., tests/test_users.py)
# 3. If no test file exists, it blocks and tells you to write tests first
#
# Exceptions:
# - Test files themselves (always allowed)
# - Config files (.json, .yaml, .yml, .toml, .ini, .cfg, .env)
# - Documentation (.md, .txt, .rst)
# - Migration files
# - Template/static files (.html, .css, .svg)
# - __init__.py files
# - Hook/skill/rule files (.tasuki/)

set +e
set +o pipefail

# The file being edited is passed via environment or stdin
# Claude Code passes tool input as JSON on stdin
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi
[ -z "$INPUT" ] && INPUT="${TOOL_INPUT:-}"

FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  [ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s\n' "$INPUT" | grep -oP '"tool_input".*"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
fi

# If we can't determine the file, allow
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Always allow these files ---

# Test files — this IS the test, allow it
if printf '%s\n' "$FILE_PATH" | grep -qE 'test_|_test\.|\.test\.|\.spec\.|/tests/|/test/|/spec/|/__tests__/|conftest'; then
  exit 0
fi

# Config files
if printf '%s\n' "$FILE_PATH" | grep -qE '\.(json|yaml|yml|toml|ini|cfg|env|lock)$'; then
  exit 0
fi

# Documentation
if printf '%s\n' "$FILE_PATH" | grep -qE '\.(md|txt|rst|adoc)$'; then
  exit 0
fi

# Static/template files
if printf '%s\n' "$FILE_PATH" | grep -qE '\.(html|css|scss|less|svg|png|jpg|ico)$'; then
  exit 0
fi

# Migration files
if printf '%s\n' "$FILE_PATH" | grep -qE 'migrat|alembic/versions|db/migrate|prisma/migrations'; then
  exit 0
fi

# Init files
if printf '%s\n' "$FILE_PATH" | grep -qE '__init__\.py$|\.gitkeep$'; then
  exit 0
fi

# Tasuki/Claude config files
if printf '%s\n' "$FILE_PATH" | grep -qE '\.tasuki/|CLAUDE\.md|\.mcp\.json'; then
  exit 0
fi

# Docker/CI files
if printf '%s\n' "$FILE_PATH" | grep -qE 'Dockerfile|docker-compose|compose\.|\.github/|\.gitlab|Jenkinsfile|Makefile'; then
  exit 0
fi

# --- Check if a corresponding test file exists ---

BASENAME=$(basename "$FILE_PATH")
DIRNAME=$(dirname "$FILE_PATH")
EXT="${BASENAME##*.}"
NAME="${BASENAME%.*}"

# Skip if file doesn't have a code extension
if ! printf '%s\n' "$EXT" | grep -qE '^(py|ts|tsx|js|jsx|go|rb|java|rs)$'; then
  exit 0
fi

# Determine the project root (look for .git or .claude)
PROJECT_ROOT="$DIRNAME"
while [ "$PROJECT_ROOT" != "/" ]; do
  if [ -d "$PROJECT_ROOT/.git" ] || [ -d "$PROJECT_ROOT/.claude" ]; then
    break
  fi
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

# Build possible test file patterns
FOUND_TEST=false

case "$EXT" in
  py)
    # Python: test_name.py or name_test.py
    for test_dir in tests test; do
      [ -f "$PROJECT_ROOT/$test_dir/test_${NAME}.py" ] && FOUND_TEST=true
      # Use find for glob patterns ([ -f ] doesn't expand wildcards)
      find "$PROJECT_ROOT/$test_dir" -maxdepth 1 -name "test_${NAME}_*.py" 2>/dev/null | head -1 | grep -q . && FOUND_TEST=true
    done
    # Also check alongside the source
    [ -f "$DIRNAME/test_${NAME}.py" ] && FOUND_TEST=true
    # Check if ANY test file mentions this module
    if grep -rlq "from.*${NAME}\|import.*${NAME}" "$PROJECT_ROOT/tests/" --include="*.py" 2>/dev/null; then
      FOUND_TEST=true
    fi
    ;;
  ts|tsx|js|jsx)
    # JS/TS: name.test.ts, name.spec.ts, __tests__/name.ts
    [ -f "$DIRNAME/${NAME}.test.${EXT}" ] && FOUND_TEST=true
    [ -f "$DIRNAME/${NAME}.spec.${EXT}" ] && FOUND_TEST=true
    [ -f "$DIRNAME/__tests__/${NAME}.${EXT}" ] && FOUND_TEST=true
    [ -f "$DIRNAME/${NAME}.test.ts" ] && FOUND_TEST=true
    [ -f "$DIRNAME/${NAME}.test.tsx" ] && FOUND_TEST=true
    [ -f "$DIRNAME/${NAME}.spec.ts" ] && FOUND_TEST=true
    # Check root test dirs
    for test_dir in tests test __tests__; do
      find "$PROJECT_ROOT/$test_dir" -name "${NAME}.test.*" -o -name "${NAME}.spec.*" 2>/dev/null | head -1 | grep -q . && FOUND_TEST=true
    done
    ;;
  go)
    # Go: name_test.go in same directory
    [ -f "$DIRNAME/${NAME}_test.go" ] && FOUND_TEST=true
    ;;
  rb)
    # Ruby: spec/name_spec.rb
    find "$PROJECT_ROOT/spec" -name "${NAME}_spec.rb" 2>/dev/null | head -1 | grep -q . && FOUND_TEST=true
    ;;
esac

if $FOUND_TEST; then
  # Tests exist — allow the edit
  exit 0
else
  # No tests found — block and enforce TDD
  echo "TDD GUARD: No tests found for '${BASENAME}'."
  echo ""
  echo "Write tests FIRST before implementing. This is a TDD-enforced project."
  echo ""
  echo "Expected test file(s):"
  case "$EXT" in
    py) echo "  tests/test_${NAME}.py" ;;
    ts|tsx) echo "  ${DIRNAME}/${NAME}.test.ts  or  ${DIRNAME}/${NAME}.spec.ts" ;;
    js|jsx) echo "  ${DIRNAME}/${NAME}.test.js  or  ${DIRNAME}/${NAME}.spec.js" ;;
    go) echo "  ${DIRNAME}/${NAME}_test.go" ;;
    rb) echo "  spec/${NAME}_spec.rb" ;;
  esac
  echo ""
  echo "Create the test file first, then come back to implement."

  # Log to activity
  ACTIVITY_FILE="$PROJECT_ROOT/.tasuki/config/activity-log.json"
  if [ -f "$ACTIVITY_FILE" ] && command -v python3 &>/dev/null; then
    logger=""
    for candidate in \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../src/engine/hook_logger.py" \
      "$(dirname "$(readlink -f "$(command -v tasuki)" 2>/dev/null)")/../src/engine/hook_logger.py"; do
      [ -f "$candidate" ] && logger="$candidate" && break
    done 2>/dev/null
    [ -n "$logger" ] && python3 "$logger" "$ACTIVITY_FILE" "$(date "+%Y-%m-%d %H:%M:%S")" "tdd-guard" "Blocked edit to $BASENAME — no tests exist"
  fi
  exit 2
fi
