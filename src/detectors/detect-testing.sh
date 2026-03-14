#!/bin/bash
# Tasuki Detector: Testing Stack
# Usage: detect-testing.sh /path/to/project

set -euo pipefail
PROJECT_DIR="${1:-.}"

backend_test=""
frontend_test=""
e2e=""
test_dir=""

# --- Python testing ---
# Search root + subdirs for pytest config
_pytest_found=false
for _td in "$PROJECT_DIR" "$PROJECT_DIR/app/backend" "$PROJECT_DIR/backend" "$PROJECT_DIR/app" "$PROJECT_DIR/src"; do
  if [ -f "$_td/pytest.ini" ] || [ -f "$_td/pyproject.toml" ] || [ -f "$_td/setup.cfg" ] || [ -f "$_td/conftest.py" ]; then
    if grep -rql "pytest\|\[tool.pytest\]" "$_td/pyproject.toml" "$_td/pytest.ini" "$_td/setup.cfg" 2>/dev/null; then
      backend_test="pytest"
      _pytest_found=true
      break
    fi
  fi
done
# Check requirements-dev.txt / requirements*.txt for pytest
if [ "$_pytest_found" = false ]; then
  if find "$PROJECT_DIR" -maxdepth 3 -name "requirements*.txt" -exec grep -ql "pytest" {} \; 2>/dev/null | head -1 | grep -q .; then
    backend_test="pytest"
    _pytest_found=true
  fi
fi
# Fallback: check for test_ files (implies pytest)
if [ "$_pytest_found" = false ] && find "$PROJECT_DIR" -maxdepth 5 -name "test_*.py" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -1 | grep -q .; then
  backend_test="pytest"
fi

# unittest (Python, only if no pytest found)
if [ -z "$backend_test" ] && grep -rql "import unittest\|from unittest" "$PROJECT_DIR" --include="*.py" -not -path "*/node_modules/*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  backend_test="unittest"
fi

# Go tests
if [ -z "$backend_test" ] && find "$PROJECT_DIR" -name "*_test.go" 2>/dev/null | head -1 | grep -q .; then
  backend_test="go-test"
fi

# RSpec (Ruby)
if [ -z "$backend_test" ] && [ -d "$PROJECT_DIR/spec" ]; then
  backend_test="rspec"
fi

# JUnit (Java)
if [ -z "$backend_test" ] && find "$PROJECT_DIR" -path "*/test/*" -name "*.java" 2>/dev/null | head -1 | grep -q .; then
  backend_test="junit"
fi

# --- Frontend testing ---
# Search all package.json files for test frameworks
pkg_content=""
for _tp in "$PROJECT_DIR" "$PROJECT_DIR/app/frontend" "$PROJECT_DIR/frontend" "$PROJECT_DIR/client" "$PROJECT_DIR/apps/web" "$PROJECT_DIR/packages/web"; do
  if [ -f "$_tp/package.json" ]; then
    pkg_content="$pkg_content $(cat "$_tp/package.json" 2>/dev/null || true)"
  fi
done

if echo "$pkg_content" | grep -q '"vitest"'; then
  frontend_test="vitest"
elif echo "$pkg_content" | grep -q '"jest"'; then
  frontend_test="jest"
elif echo "$pkg_content" | grep -q '"mocha"'; then
  frontend_test="mocha"
fi

# --- E2E testing ---
_e2e_found=false
for _ep in "$PROJECT_DIR" "$PROJECT_DIR/app/frontend" "$PROJECT_DIR/frontend"; do
  if [ -f "$_ep/playwright.config.ts" ] || [ -f "$_ep/playwright.config.js" ]; then
    e2e="playwright"; _e2e_found=true; break
  fi
  if [ -f "$_ep/cypress.config.ts" ] || [ -f "$_ep/cypress.config.js" ]; then
    e2e="cypress"; _e2e_found=true; break
  fi
done
if [ "$_e2e_found" = false ]; then
  if echo "$pkg_content" | grep -q '"@playwright/test"'; then
    e2e="playwright"
  elif echo "$pkg_content" | grep -q '"cypress"'; then
    e2e="cypress"
  fi
fi

# --- Count tests ---
backend_test_count=0
frontend_test_count=0

case "$backend_test" in
  pytest|unittest)
    backend_test_count=$(find "$PROJECT_DIR" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | wc -l)
    ;;
  go-test)
    backend_test_count=$(find "$PROJECT_DIR" -name "*_test.go" 2>/dev/null | wc -l)
    ;;
  rspec)
    backend_test_count=$(find "$PROJECT_DIR/spec" -name "*_spec.rb" 2>/dev/null | wc -l)
    ;;
esac

case "$frontend_test" in
  vitest|jest)
    frontend_test_count=$(find "$PROJECT_DIR" -name "*.test.ts" -o -name "*.test.tsx" -o -name "*.test.js" -o -name "*.test.jsx" -o -name "*.spec.ts" -o -name "*.spec.tsx" 2>/dev/null | grep -v node_modules | wc -l)
    ;;
esac

# --- Find test directory ---
for d in "tests" "test" "spec" "__tests__"; do
  found=$(find "$PROJECT_DIR" -maxdepth 3 -type d -name "$d" -not -path "*/node_modules/*" 2>/dev/null | head -1)
  if [ -n "$found" ]; then
    test_dir="$found"
    break
  fi
done

cat <<EOF
{
  "detected": $([ -n "$backend_test" ] || [ -n "$frontend_test" ] && echo "true" || echo "false"),
  "backend_test": "${backend_test:-none}",
  "frontend_test": "${frontend_test:-none}",
  "e2e": "${e2e:-none}",
  "test_dir": "${test_dir:-}",
  "counts": {
    "backend_tests": $backend_test_count,
    "frontend_tests": $frontend_test_count
  }
}
EOF
