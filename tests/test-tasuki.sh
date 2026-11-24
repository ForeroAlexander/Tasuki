#!/bin/bash
# Tasuki Self-Tests
# Verifies that core functionality works correctly.
# Usage: bash tests/test-tasuki.sh

set -uo pipefail
# Note: NOT set -e because test assertions use exit codes

TASUKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASUKI="$TASUKI_ROOT/bin/tasuki"
TEST_DIR=$(mktemp -d)
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
echo -e "${BOLD}Tasuki Self-Tests${NC}"
echo -e "${DIM}══════════════════${NC}"
echo ""

# --- CLI ---
echo -e "${BOLD}CLI:${NC}"

$TASUKI version >/dev/null 2>&1
assert "tasuki version" $?

$TASUKI help >/dev/null 2>&1
assert "tasuki help" $?

# --- Detectors ---
echo ""
echo -e "${BOLD}Detectors:${NC}"

# Create mock Python project
MOCK="$TEST_DIR/mock-python"
mkdir -p "$MOCK/app/routers" "$MOCK/app/models" "$MOCK/tests" "$MOCK/alembic/versions"
echo "fastapi==0.115.0" > "$MOCK/requirements.txt"
echo "sqlalchemy==2.0.36" >> "$MOCK/requirements.txt"
echo "from fastapi import FastAPI" > "$MOCK/app/main.py"
echo "from sqlalchemy import Column" > "$MOCK/app/models/user.py"
cat > "$MOCK/docker-compose.yml" << 'EOF'
services:
  api:
    build: .
  db:
    image: postgres:16
EOF
cd "$MOCK" && git init -q 2>/dev/null

# Test backend detector
result=$(bash "$TASUKI_ROOT/src/detectors/detect-backend.sh" "$MOCK" 2>/dev/null)
echo "$result" | grep -q '"detected": true' 2>/dev/null
assert "detect-backend finds Python" $?

echo "$result" | grep -q '"framework": "fastapi"' 2>/dev/null
assert "detect-backend finds FastAPI" $?

# Test database detector
result=$(bash "$TASUKI_ROOT/src/detectors/detect-database.sh" "$MOCK" 2>/dev/null)
echo "$result" | grep -q '"orm": "sqlalchemy"' 2>/dev/null
assert "detect-database finds SQLAlchemy" $?

# Test infra detector
result=$(bash "$TASUKI_ROOT/src/detectors/detect-infra.sh" "$MOCK" 2>/dev/null)
echo "$result" | grep -qE '"detected": true|"compose_file"' 2>/dev/null
assert "detect-infra finds docker/CI" $?

# --- Onboard ---
echo ""
echo -e "${BOLD}Onboard:${NC}"

$TASUKI onboard "$MOCK" >/dev/null 2>&1
assert "onboard completes without error" $?

[ -f "$MOCK/TASUKI.md" ]
assert "TASUKI.md generated" $?

[ -d "$MOCK/.tasuki/agents" ]
assert ".tasuki/agents/ exists" $?

[ -f "$MOCK/.tasuki/settings.json" ]
assert "settings.json generated" $?

[ -f "$MOCK/.mcp.json" ]
assert ".mcp.json generated" $?

[ -d "$MOCK/memory-vault" ]
assert "memory-vault/ initialized" $?

[ -f "$MOCK/.tasuki/config/project-facts.md" ]
assert "project-facts.md generated" $?

[ -f "$MOCK/.tasuki/config/capability-map.yaml" ]
assert "capability-map.yaml generated" $?

[ -d "$MOCK/tasuki-plans" ]
assert "tasuki-plans/ created" $?

# --- Facts verification ---
echo ""
echo -e "${BOLD}Facts:${NC}"

grep -q "FastAPI" "$MOCK/.tasuki/config/project-facts.md" 2>/dev/null
assert "facts detected FastAPI" $?

grep -q "app/" "$MOCK/.tasuki/config/project-facts.md" 2>/dev/null
assert "facts verified app/ path" $?

# --- Agents ---
echo ""
echo -e "${BOLD}Agents:${NC}"

agent_count=$(find "$MOCK/.tasuki/agents" -name "*.md" | wc -l)
[ "$agent_count" -gt 5 ]
assert "generated $agent_count agents (>5)" $?

grep -q "Before You Act" "$MOCK/.tasuki/agents/backend-dev.md" 2>/dev/null
assert "agents have Before You Act section" $?

grep -q "Handoff" "$MOCK/.tasuki/agents/backend-dev.md" 2>/dev/null
assert "agents have Handoff section" $?

grep -q "Position in the Pipeline" "$MOCK/.tasuki/agents/backend-dev.md" 2>/dev/null
assert "agents have Pipeline Position" $?

# --- Hooks ---
echo ""
echo -e "${BOLD}Hooks:${NC}"

[ -x "$MOCK/.tasuki/hooks/tdd-guard.sh" ]
assert "tdd-guard.sh is executable" $?

[ -x "$MOCK/.tasuki/hooks/security-check.sh" ]
assert "security-check.sh is executable" $?

[ -x "$MOCK/.tasuki/hooks/protect-files.sh" ]
assert "protect-files.sh is executable" $?

# --- TDD Guard ---
echo ""
echo -e "${BOLD}TDD Guard:${NC}"

# Should block: no test exists
export TOOL_INPUT='{"file_path": "'$MOCK'/app/routers/orders.py"}'
bash "$MOCK/.tasuki/hooks/tdd-guard.sh" >/dev/null 2>&1
[ $? -eq 2 ]
assert "blocks edit without tests (exit 2)" $?

# Should allow: test exists
echo "def test_orders(): pass" > "$MOCK/tests/test_orders.py"
bash "$MOCK/.tasuki/hooks/tdd-guard.sh" >/dev/null 2>&1
assert "allows edit with tests (exit 0)" $?

# Should allow: config files always pass
export TOOL_INPUT='{"file_path": "'$MOCK'/docker-compose.yml"}'
bash "$MOCK/.tasuki/hooks/tdd-guard.sh" >/dev/null 2>&1
assert "allows config file edit" $?

# --- Vault ---
echo ""
echo -e "${BOLD}Vault:${NC}"

vault_nodes=$(find "$MOCK/memory-vault" -name "*.md" | wc -l)
[ "$vault_nodes" -gt 10 ]
assert "vault has $vault_nodes nodes (>10)" $?

grep -rq "\[\[backend-dev\]\]" "$MOCK/memory-vault/" 2>/dev/null
assert "vault has wikilinks" $?

# --- Score ---
echo ""
echo -e "${BOLD}Score:${NC}"

result=$($TASUKI score "fix typo in readme" "$MOCK" 2>/dev/null)
echo "$result" | grep -q "fast" 2>/dev/null
assert "scores typo fix as fast" $?

result=$($TASUKI score "add new database schema with api endpoints and frontend page" "$MOCK" 2>/dev/null)
echo "$result" | grep -q "serious\|standard" 2>/dev/null
assert "scores full feature as standard/serious" $?

# --- Validate ---
echo ""
echo -e "${BOLD}Validate:${NC}"

result=$($TASUKI validate "$MOCK" 2>/dev/null)
echo "$result" | grep -q "PASS" 2>/dev/null
assert "validate passes on valid config" $?

# --- Adapters ---
echo ""
echo -e "${BOLD}Adapters:${NC}"

$TASUKI adapt cursor "$MOCK" >/dev/null 2>&1
[ -d "$MOCK/.cursor/rules" ]
assert "cursor adapter generates .cursor/rules/" $?

$TASUKI adapt codex "$MOCK" >/dev/null 2>&1
[ -f "$MOCK/AGENTS.md" ]
assert "codex adapter generates AGENTS.md" $?

$TASUKI adapt gemini "$MOCK" >/dev/null 2>&1
[ -f "$MOCK/GEMINI.md" ]
assert "gemini adapter generates GEMINI.md" $?

# --- Init (scaffolding) ---
echo ""
echo -e "${BOLD}Init:${NC}"

$TASUKI init landing test-site "$TEST_DIR" >/dev/null 2>&1
[ -f "$TEST_DIR/test-site/index.html" ] 2>/dev/null
assert "init landing creates index.html" $?

# --- Doctor ---
echo ""
echo -e "${BOLD}Doctor:${NC}"

result=$($TASUKI doctor "$MOCK" 2>/dev/null)
echo "$result" | grep -qE "HEALTHY|OK" 2>/dev/null
assert "doctor reports healthy on valid project" $?

$TASUKI doctor "$MOCK" --fix >/dev/null 2>&1
assert "doctor --fix runs without error" $?

# --- Export/Import ---
echo ""
echo -e "${BOLD}Export/Import:${NC}"

$TASUKI export "$MOCK" >/dev/null 2>&1
exported=$(find "$MOCK" -name "*tasuki-config*" -name "*.tar.gz" 2>/dev/null | head -1)
[ -f "$exported" ] 2>/dev/null
assert "export creates .tar.gz" $?

# --- Dashboard ---
echo ""
echo -e "${BOLD}Dashboard:${NC}"

TASUKI_GENERATE_ONLY=1 $TASUKI dashboard "$MOCK" >/dev/null 2>&1
[ -f "$MOCK/.tasuki/dashboard.html" ]
assert "dashboard generates HTML" $?

grep -q "Knowledge Graph" "$MOCK/.tasuki/dashboard.html" 2>/dev/null
assert "dashboard has graph section" $?

grep -q "Pipeline Status" "$MOCK/.tasuki/dashboard.html" 2>/dev/null
assert "dashboard has progress panel" $?

# --- Cleanup/Restore ---
echo ""
echo -e "${BOLD}Cleanup/Restore:${NC}"

# Install frontend-dev to test cleanup
cp "$TASUKI_ROOT/src/templates/agents/frontend-dev.md" "$MOCK/.tasuki/agents/frontend-dev.md" 2>/dev/null
$TASUKI cleanup "$MOCK" --all >/dev/null 2>&1
[ ! -f "$MOCK/.tasuki/agents/frontend-dev.md" ]
assert "cleanup removes frontend-dev (no frontend)" $?

$TASUKI restore "$MOCK" --all >/dev/null 2>&1
[ -f "$MOCK/.tasuki/agents/frontend-dev.md" ]
assert "restore brings back frontend-dev" $?

# --- Model Translation ---
echo ""
echo -e "${BOLD}Model Translation:${NC}"

$TASUKI adapt codex "$MOCK" >/dev/null 2>&1
grep -q "o3\|o4-mini" "$MOCK/AGENTS.md" 2>/dev/null
assert "codex uses o3/o4-mini models" $?

$TASUKI adapt gemini "$MOCK" >/dev/null 2>&1
grep -q "gemini-2.5" "$MOCK/GEMINI.md" 2>/dev/null
assert "gemini uses gemini-2.5 models" $?

grep -q "Agent(" "$MOCK/AGENTS.md" 2>/dev/null
[ $? -ne 0 ]
assert "codex output has no Claude-only Agent() spawn syntax" $?

# --- Regression: refactor leftovers ---
echo ""
echo -e "${BOLD}Generated Context:${NC}"

[ -s "$MOCK/.tasuki/config/context-summary.md" ]
assert "onboard generates context-summary.md" $?

missing=0
while IFS= read -r rel; do
  [ -e "$MOCK/$rel" ] || missing=$((missing + 1))
done < <(sed -n '/^## Paths/,/^## /p' "$MOCK/.tasuki/config/context-summary.md" 2>/dev/null | sed -n 's/.*`\([^`]*\)`.*/\1/p')
[ "$missing" -eq 0 ]
assert "context-summary.md lists only paths that exist" $?

grep -q "/routers/\|/services/" "$MOCK/.tasuki/agents/planner.md" 2>/dev/null
[ $? -ne 0 ]
assert "planner.md does not assume routers/ or services/ directories" $?

# frontend-dev.md is excluded: the cleanup test above copies the raw template in by hand
unrendered=$(grep -l "{{[A-Z_]*}}" "$MOCK/.tasuki/agents/"*.md "$MOCK/TASUKI.md" 2>/dev/null | grep -v "frontend-dev.md" | wc -l)
[ "$unrendered" -eq 0 ]
assert "no unrendered {{PLACEHOLDER}} in agents or TASUKI.md" $?

pkg_version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$TASUKI_ROOT/package.json" | head -1)
cli_version=$($TASUKI --version 2>/dev/null | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p' | head -1)
plugin_version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$TASUKI_ROOT/.claude-plugin/manifest.json" | head -1)
[ -n "$pkg_version" ] && [ "$pkg_version" = "$cli_version" ] && [ "$pkg_version" = "$plugin_version" ]
assert "package.json, CLI and plugin manifest report the same version ($pkg_version)" $?

# --- Hook input parsing ---
echo ""
echo -e "${BOLD}Hook Input Parsing:${NC}"

HOOKS_SRC="$TASUKI_ROOT/src/templates/hooks"
! grep -l "grep -oP" "$HOOKS_SRC"/*.sh >/dev/null 2>&1
assert "hooks do not parse JSON with GNU-only grep -oP" $?

HP=$(mktemp -d); mkdir -p "$HP/.tasuki/config" "$HP/app"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$HP"'/app/we\"ird.py","content":"x = 1"}}' \
  | (cd "$HP" && bash "$HOOKS_SRC/tdd-guard.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "tdd-guard still blocks when the path contains an escaped quote" $?

echo ".env" > "$HP/.tasuki/config/protected-files.txt"
printf '%s' '{"tool_name":"Edit","tool_input":{"old_string":"a \"b\"","file_path":"'"$HP"'/.env","new_string":"c"}}' \
  | (cd "$HP" && bash "$HOOKS_SRC/protect-files.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "protect-files blocks a protected file with quoted content before the path" $?

python3 -c 'import json;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"/x/app/db.py","content":"q = \"a\"\ncur.execute(f\"select {x}\")\n"}}))' \
  | (cd "$HP" && bash "$HOOKS_SRC/security-check.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "security-check scans multi-line content with quotes" $?
mkdir -p "$HP/evil" && echo 'raise SystemExit(0)' > "$HP/json.py"
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$HP"'/.env","new_string":"c"}}' \
  | (cd "$HP" && bash "$HOOKS_SRC/protect-files.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "a json.py planted in the project cannot disable protect-files" $?
rm -f "$HP/json.py"

printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$HP"'/.env"' \
  | (cd "$HP" && bash "$HOOKS_SRC/protect-files.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "protect-files fails closed on unparseable input naming a protected file" $?

fallback=$(printf '%s' '{"tool_input":{"file_path":"/a/b, c/we\"ird.py"},"current_stage": 3}' | tr '\n' ' ' | sed -E -n \
  -e 's/.*"file_path"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -1)
[ "$fallback" = '/a/b, c/we\"ird.py' ]
assert "sed fallback keeps commas and escaped quotes in paths" $?

NOPY=$(mktemp -d)
for tool in bash cat tr sed head git basename dirname grep; do
  ln -s "$(command -v $tool)" "$NOPY/$tool" 2>/dev/null
done
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$HP"'/\u002eenv"}}' \
  | (cd "$HP" && PATH="$NOPY" bash "$HOOKS_SRC/protect-files.sh" >/dev/null 2>&1)
[ $? -eq 2 ]
assert "protect-files fails closed on an escaped path when python3 is missing" $?
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$HP"'/app/ok.py"}}' \
  | (cd "$HP" && PATH="$NOPY" bash "$HOOKS_SRC/protect-files.sh" >/dev/null 2>&1)
[ $? -eq 0 ]
assert "protect-files still allows a plain path when python3 is missing" $?
rm -rf "$NOPY"

rm -rf "$HP"

# --- Error Memory ---
echo ""
echo -e "${BOLD}Error Memory:${NC}"

$TASUKI error "Used print instead of logger" --agent backend-dev "$MOCK" >/dev/null 2>&1
[ -f "$MOCK/memory-vault/errors/used-print-instead-of-logger.md" ] 2>/dev/null
assert "error creates vault node" $?

result=$(bash "$TASUKI_ROOT/src/engine/errors.sh" list "$MOCK" 2>/dev/null)
echo "$result" | grep -q "print" 2>/dev/null
assert "errors list shows recorded error" $?

# --- Cleanup ---
rm -rf "$TEST_DIR"

# --- Summary ---
echo ""
echo -e "${DIM}──────────────────${NC}"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}ALL $TOTAL TESTS PASSED${NC}"
else
  echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL"
fi
echo ""

exit $FAIL
