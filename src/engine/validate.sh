#!/bin/bash
# Tasuki Engine — Validate
# Checks an existing .tasuki/ configuration for completeness and consistency.
# Usage: bash validate.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

validate_project() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  echo ""
  echo -e "${BOLD}Tasuki Validation Report${NC}"
  echo -e "${DIM}═══════════════════════${NC}"
  echo ""

  local errors=0
  local warnings=0

  # --- 1. Core structure ---
  echo -e "  ${BOLD}Structure:${NC}"

  check_exists "$project_dir/TASUKI.md" "TASUKI.md" || errors=$((errors + 1))
  check_exists "$claude_dir" ".tasuki/" || { log_error "    .tasuki/ directory missing. Run: tasuki onboard $project_dir"; exit 1; }
  check_exists "$claude_dir/settings.json" ".tasuki/settings.json" || errors=$((errors + 1))
  check_exists "$claude_dir/agents" ".tasuki/agents/" || errors=$((errors + 1))
  check_exists "$claude_dir/rules" ".tasuki/rules/" || warnings=$((warnings + 1))
  check_exists "$claude_dir/hooks" ".tasuki/hooks/" || warnings=$((warnings + 1))
  check_exists "$claude_dir/skills" ".tasuki/skills/" || warnings=$((warnings + 1))
  echo ""

  # --- 2. Agent files ---
  echo -e "  ${BOLD}Agents:${NC}"
  local agent_count=0
  if [ -d "$claude_dir/agents" ]; then
    for agent_file in "$claude_dir/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file" .md)
      agent_count=$((agent_count + 1))

      # Check frontmatter
      if ! head -1 "$agent_file" | grep -q '^---'; then
        log_warn "    $name: missing YAML frontmatter"
        warnings=$((warnings + 1))
      else
        # Check required fields
        local has_name has_desc has_tools
        has_name=$(grep -c '^name:' "$agent_file" 2>/dev/null || echo 0)
        has_desc=$(grep -c '^description:' "$agent_file" 2>/dev/null || echo 0)
        has_tools=$(grep -c '^tools:' "$agent_file" 2>/dev/null || echo 0)

        if [ "$has_name" -eq 0 ] || [ "$has_desc" -eq 0 ] || [ "$has_tools" -eq 0 ]; then
          log_warn "    $name: missing frontmatter fields (name/description/tools)"
          warnings=$((warnings + 1))
        else
          log_dim "    $name: OK"
        fi
      fi

      # Check for unresolved placeholders
      if grep -qE '\{\{[A-Z_]+\}\}' "$agent_file" 2>/dev/null; then
        log_error "    $name: has unresolved placeholders"
        errors=$((errors + 1))
      fi
    done
  fi
  echo -e "    ${DIM}$agent_count agents total${NC}"
  echo ""

  # --- 3. Rules ---
  echo -e "  ${BOLD}Rules:${NC}"
  local rule_count=0
  if [ -d "$claude_dir/rules" ]; then
    for rule_file in "$claude_dir/rules"/*.md; do
      [ -f "$rule_file" ] || continue
      local name
      name=$(basename "$rule_file" .md)
      rule_count=$((rule_count + 1))

      # Check paths in frontmatter
      if ! grep -q '^paths:' "$rule_file" 2>/dev/null; then
        log_warn "    $name: missing paths: in frontmatter"
        warnings=$((warnings + 1))
      else
        log_dim "    $name: OK"
      fi
    done
  fi
  echo -e "    ${DIM}$rule_count rules total${NC}"
  echo ""

  # --- 4. Hooks ---
  echo -e "  ${BOLD}Hooks:${NC}"
  if [ -d "$claude_dir/hooks" ]; then
    for hook_file in "$claude_dir/hooks"/*.sh; do
      [ -f "$hook_file" ] || continue
      local name
      name=$(basename "$hook_file")

      if [ ! -x "$hook_file" ]; then
        log_warn "    $name: not executable (run: chmod +x)"
        warnings=$((warnings + 1))
      else
        log_dim "    $name: OK"
      fi
    done
  fi
  echo ""

  # --- 5. Settings.json ---
  echo -e "  ${BOLD}Settings:${NC}"
  if [ -f "$claude_dir/settings.json" ]; then
    # Check valid JSON (basic)
    if python3 -c "import json; json.load(open('$claude_dir/settings.json'))" 2>/dev/null; then
      log_dim "    settings.json: valid JSON"
    elif node -e "JSON.parse(require('fs').readFileSync('$claude_dir/settings.json'))" 2>/dev/null; then
      log_dim "    settings.json: valid JSON"
    else
      log_error "    settings.json: invalid JSON"
      errors=$((errors + 1))
    fi

    # Check hook paths reference existing files
    local hook_refs
    hook_refs=$(grep -oE '"command":\s*"[^"]*"' "$claude_dir/settings.json" 2>/dev/null | grep -oE '"[^"]*\.sh"' | sed 's/"//g' || true)
    for ref in $hook_refs; do
      if [ ! -f "$ref" ] && [ ! -f "$project_dir/$ref" ]; then
        log_warn "    Hook path not found: $ref"
        warnings=$((warnings + 1))
      fi
    done
  fi
  echo ""

  # --- 6. MCP ---
  echo -e "  ${BOLD}MCP:${NC}"
  if [ -f "$project_dir/.mcp.json" ]; then
    if python3 -c "import json; json.load(open('$project_dir/.mcp.json'))" 2>/dev/null; then
      log_dim "    .mcp.json: valid JSON"
    elif node -e "JSON.parse(require('fs').readFileSync('$project_dir/.mcp.json'))" 2>/dev/null; then
      log_dim "    .mcp.json: valid JSON"
    else
      log_error "    .mcp.json: invalid JSON"
      errors=$((errors + 1))
    fi
  else
    log_dim "    .mcp.json: not found (optional)"
  fi
  echo ""

  # --- 7. TASUKI.md consistency ---
  echo -e "  ${BOLD}TASUKI.md:${NC}"
  if [ -f "$project_dir/TASUKI.md" ]; then
    if grep -qE '\{\{[A-Z_]+\}\}' "$project_dir/TASUKI.md" 2>/dev/null; then
      log_error "    Has unresolved placeholders:"
      grep -oE '\{\{[A-Z_]+\}\}' "$project_dir/TASUKI.md" 2>/dev/null | sort -u | while read -r ph; do
        log_dim "      $ph"
      done || true
      errors=$((errors + 1))
    else
      log_dim "    No unresolved placeholders"
    fi

    # Check agent references match actual files
    local refs_in_claude
    refs_in_claude=$(grep -oE '/[a-z-]+' "$project_dir/TASUKI.md" 2>/dev/null | sed 's|^/||' | sort -u || true)
    for ref in $refs_in_claude; do
      if [ -f "$claude_dir/agents/$ref.md" ]; then
        : # OK
      fi
    done
  fi
  echo ""

  # --- Summary ---
  echo -e "${DIM}───────────────────────${NC}"
  if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}PASS${NC} — Configuration is valid"
  elif [ "$errors" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}PASS${NC} with $warnings warning(s)"
  else
    echo -e "  ${RED}${BOLD}FAIL${NC} — $errors error(s), $warnings warning(s)"
  fi
  echo ""

  return $errors
}

check_exists() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    log_dim "    $label: exists"
    return 0
  else
    log_error "    $label: MISSING"
    return 1
  fi
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  validate_project "$@"
fi
