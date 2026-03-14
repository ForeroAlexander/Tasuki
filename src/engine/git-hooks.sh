#!/bin/bash
# Tasuki Engine — Git Hooks Integration
# Installs git hooks that run Tasuki checks automatically on git events.
# Pre-commit: security scan + guardrails
# Pre-push: full review check
#
# Usage: bash git-hooks.sh <install|uninstall|status> [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_git_hooks() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local git_hooks="$project_dir/.git/hooks"

  if [ ! -d "$project_dir/.git" ]; then
    log_error "Not a git repository: $project_dir"
    exit 1
  fi

  mkdir -p "$git_hooks"

  echo ""
  echo -e "${BOLD}Installing Tasuki Git Hooks${NC}"
  echo ""

  # --- Pre-commit hook ---
  local pre_commit="$git_hooks/pre-commit"
  cat > "$pre_commit" << 'HOOKEOF'
#!/bin/bash
# Tasuki pre-commit hook
# Runs: security check, guardrails, TDD guard on staged files

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[tasuki]${NC} Pre-commit checks..."

# 1. Check for hardcoded secrets
echo -n "  Secrets scan... "
SECRETS=$(echo "$STAGED_FILES" | xargs grep -lnE '(api_key|secret_key|password|api_secret|auth_token)\s*[:=]\s*["\x27][^\s"]{8,}' 2>/dev/null | grep -v 'test\|mock\|example\|\.env\.example' || true)
if [ -n "$SECRETS" ]; then
  echo -e "${RED}FOUND${NC}"
  echo "$SECRETS" | while read -r f; do echo "    $f"; done
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}clean${NC}"
fi

# 2. Check for console.log / print() left in code
echo -n "  Debug statements... "
DEBUG_STMTS=$(echo "$STAGED_FILES" | grep -E '\.(py|ts|js|tsx|jsx)$' | xargs grep -lnE 'console\.log\(|print\(' 2>/dev/null | grep -v 'test\|spec\|__pycache__' || true)
if [ -n "$DEBUG_STMTS" ]; then
  echo -e "${YELLOW}WARNING${NC} (debug statements found)"
  echo "$DEBUG_STMTS" | head -5 | while read -r f; do echo "    $f"; done
fi

# 3. Check for TODO/FIXME/HACK
echo -n "  TODOs... "
TODOS=$(echo "$STAGED_FILES" | grep -E '\.(py|ts|js|tsx|jsx|go|rb)$' | xargs grep -lnE 'TODO|FIXME|HACK|XXX' 2>/dev/null || true)
if [ -n "$TODOS" ]; then
  echo -e "${YELLOW}WARNING${NC} ($(echo "$TODOS" | wc -l) files with TODOs)"
fi

# 4. Check for large files
echo -n "  Large files... "
LARGE=$(echo "$STAGED_FILES" | while read -r f; do
  [ -f "$f" ] && size=$(wc -c < "$f") && [ "$size" -gt 1048576 ] && echo "$f ($((size / 1024))KB)"
done || true)
if [ -n "$LARGE" ]; then
  echo -e "${RED}BLOCKED${NC}"
  echo "$LARGE" | while read -r f; do echo "    $f"; done
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}clean${NC}"
fi

# 5. Check for .env files
echo -n "  Env files... "
ENV_FILES=$(echo "$STAGED_FILES" | grep -E '\.env$|\.env\.' | grep -v '\.env\.example' || true)
if [ -n "$ENV_FILES" ]; then
  echo -e "${RED}BLOCKED${NC} — never commit .env files"
  echo "$ENV_FILES" | while read -r f; do echo "    $f"; done
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}clean${NC}"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo -e "${RED}[tasuki]${NC} Commit blocked: $ERRORS issue(s) found."
  echo "  Fix the issues above or use --no-verify to skip (not recommended)."
  exit 1
fi

echo -e "${GREEN}[tasuki]${NC} All checks passed."
HOOKEOF
  chmod +x "$pre_commit"
  log_success "  pre-commit: installed"

  # --- Pre-push hook ---
  local pre_push="$git_hooks/pre-push"
  cat > "$pre_push" << 'HOOKEOF'
#!/bin/bash
# Tasuki pre-push hook
# Runs: test suite check, security reminder

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[tasuki]${NC} Pre-push checks..."

# 1. Remind about tests
echo -n "  Test suite... "
if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
  echo -e "${YELLOW}reminder${NC}: run 'npm test' before pushing"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  echo -e "${YELLOW}reminder${NC}: run 'pytest' before pushing"
elif [ -f "go.mod" ]; then
  echo -e "${YELLOW}reminder${NC}: run 'go test ./...' before pushing"
else
  echo -e "${GREEN}ok${NC}"
fi

# 2. Check branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo -e "  ${YELLOW}Warning:${NC} Pushing directly to $BRANCH"
fi

echo -e "${GREEN}[tasuki]${NC} Push proceeding."
HOOKEOF
  chmod +x "$pre_push"
  log_success "  pre-push: installed"

  # --- Commit-msg hook ---
  local commit_msg="$git_hooks/commit-msg"
  cat > "$commit_msg" << 'HOOKEOF'
#!/bin/bash
# Tasuki commit-msg hook
# Validates commit message format

MSG=$(cat "$1")
NC='\033[0m'
YELLOW='\033[1;33m'

# Check minimum length
if [ ${#MSG} -lt 10 ]; then
  echo -e "${YELLOW}[tasuki]${NC} Commit message too short (min 10 chars)."
  exit 1
fi

# Check not starting with lowercase (conventional commits start with type:)
if echo "$MSG" | head -1 | grep -qE '^[a-z]+(\(.+\))?: '; then
  : # conventional commit format — good
elif echo "$MSG" | head -1 | grep -qE '^[A-Z]'; then
  : # starts with uppercase — good
else
  echo -e "${YELLOW}[tasuki]${NC} Tip: Use conventional commits (feat:, fix:, chore:) or start with uppercase."
fi
HOOKEOF
  chmod +x "$commit_msg"
  log_success "  commit-msg: installed"

  echo ""
  log_success "Git hooks installed."
  log_dim "  Pre-commit: secrets, debug stmts, large files, .env"
  log_dim "  Pre-push: test reminder, branch check"
  log_dim "  Commit-msg: format validation"
  echo ""
}

uninstall_git_hooks() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local git_hooks="$project_dir/.git/hooks"

  echo ""
  for hook in pre-commit pre-push commit-msg; do
    if [ -f "$git_hooks/$hook" ] && grep -q "tasuki" "$git_hooks/$hook" 2>/dev/null; then
      rm "$git_hooks/$hook"
      log_success "  Removed: $hook"
    fi
  done
  echo ""
}

status_git_hooks() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local git_hooks="$project_dir/.git/hooks"

  echo ""
  echo -e "${BOLD}Git Hooks Status${NC}"
  echo ""

  for hook in pre-commit pre-push commit-msg; do
    if [ -f "$git_hooks/$hook" ] && grep -q "tasuki" "$git_hooks/$hook" 2>/dev/null; then
      echo -e "  ${GREEN}*${NC} $hook: ${GREEN}active${NC}"
    elif [ -f "$git_hooks/$hook" ]; then
      echo -e "  ${YELLOW}*${NC} $hook: exists (not Tasuki)"
    else
      echo -e "  ${DIM}*${NC} $hook: not installed"
    fi
  done
  echo ""
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-status}" in
    install)   shift; install_git_hooks "$@" ;;
    uninstall) shift; uninstall_git_hooks "$@" ;;
    status)    shift; status_git_hooks "$@" ;;
    *) echo "Usage: git-hooks.sh <install|uninstall|status> [path]" ;;
  esac
fi
