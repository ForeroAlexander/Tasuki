#!/bin/bash
# Tasuki Engine — Doctor
# Diagnoses common issues with the Tasuki setup.
# Checks: dependencies, hooks, permissions, config integrity, staleness.
# Usage: bash doctor.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

doctor() {
  local project_dir="${1:-.}"
  local auto_fix="${2:-false}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  echo ""
  echo -e "${BOLD}Tasuki Doctor${NC}"
  echo -e "${DIM}═════════════${NC}"
  echo ""

  local issues=0
  local warnings=0

  # 1. System dependencies
  echo -e "  ${BOLD}System Dependencies:${NC}"
  check_cmd "bash" "Required" || issues=$((issues + 1))
  check_cmd "git" "Required for version control" || issues=$((issues + 1))
  check_cmd "curl" "Required for MCP and catalog updates" || issues=$((issues + 1))
  check_cmd "awk" "Required for template rendering" || issues=$((issues + 1))
  check_cmd "python3" "Optional: JSON validation, MCP cleanup" true || warnings=$((warnings + 1))
  check_cmd "node" "Optional: npm MCPs, frontend tools" true || warnings=$((warnings + 1))
  check_cmd "npx" "Optional: MCP server execution" true || warnings=$((warnings + 1))
  check_cmd "jq" "Optional: JSON manipulation" true || warnings=$((warnings + 1))
  echo ""

  # 2. Tasuki installation
  echo -e "  ${BOLD}Tasuki Installation:${NC}"
  if [ -f "$TASUKI_ROOT/bin/tasuki" ]; then
    log_dim "    tasuki binary: OK ($TASUKI_ROOT/bin/tasuki)"
  else
    log_error "    tasuki binary: NOT FOUND"
    issues=$((issues + 1))
  fi

  if [ -d "$TASUKI_SRC/engine" ]; then
    local engine_count
    engine_count=$(find "$TASUKI_SRC/engine" -name "*.sh" | wc -l)
    log_dim "    engine scripts: $engine_count found"
  else
    log_error "    engine directory: MISSING"
    issues=$((issues + 1))
  fi

  local profile_count
  profile_count=$(find "$TASUKI_SRC/profiles" -name "*.yaml" 2>/dev/null | wc -l)
  log_dim "    profiles: $profile_count available"

  local template_count
  template_count=$(find "$TASUKI_SRC/templates/agents" -name "*.md" 2>/dev/null | wc -l)
  log_dim "    agent templates: $template_count available"
  echo ""

  # 3. Project setup (if onboarded)
  if [ -d "$claude_dir" ]; then
    echo -e "  ${BOLD}Project Setup:${NC}"

    # TASUKI.md
    if [ -f "$project_dir/TASUKI.md" ]; then
      log_dim "    TASUKI.md: exists"
    else
      log_error "    TASUKI.md: MISSING (run tasuki onboard)"
      issues=$((issues + 1))
    fi

    # settings.json validity
    if [ -f "$claude_dir/settings.json" ]; then
      if python3 -c "import json; json.load(open('$claude_dir/settings.json'))" 2>/dev/null || \
         node -e "JSON.parse(require('fs').readFileSync('$claude_dir/settings.json'))" 2>/dev/null; then
        log_dim "    settings.json: valid JSON"
      else
        log_error "    settings.json: INVALID JSON — hooks won't work"
        issues=$((issues + 1))
      fi
    else
      log_error "    settings.json: MISSING"
      issues=$((issues + 1))
    fi

    # .mcp.json validity
    if [ -f "$project_dir/.mcp.json" ]; then
      if python3 -c "import json; json.load(open('$project_dir/.mcp.json'))" 2>/dev/null || \
         node -e "JSON.parse(require('fs').readFileSync('$project_dir/.mcp.json'))" 2>/dev/null; then
        log_dim "    .mcp.json: valid JSON"
      else
        log_error "    .mcp.json: INVALID JSON — MCPs won't load"
        issues=$((issues + 1))
      fi
    fi

    # --- Hooks: existence, executability, and registration ---
    echo ""
    echo -e "  ${BOLD}Hooks (7 expected):${NC}"
    local expected_hooks=("protect-files.sh" "security-check.sh" "tdd-guard.sh" "pipeline-tracker.sh" "pipeline-trigger.sh" "force-agent-read.sh" "force-planner-first.sh")
    local hooks_found=0
    local hooks_broken=0

    for hook_name in "${expected_hooks[@]}"; do
      local hook_file="$claude_dir/hooks/$hook_name"
      if [ ! -f "$hook_file" ]; then
        log_error "    $hook_name: MISSING"
        issues=$((issues + 1))
        hooks_broken=$((hooks_broken + 1))
      elif [ ! -x "$hook_file" ]; then
        log_warn "    $hook_name: exists but NOT executable"
        warnings=$((warnings + 1))
        hooks_broken=$((hooks_broken + 1))
      else
        # Test that the hook doesn't crash on empty input
        local exit_code=0
        echo '{}' | timeout 5 bash "$hook_file" > /dev/null 2>&1 || exit_code=$?
        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 2 ]; then
          log_dim "    $hook_name: OK"
          hooks_found=$((hooks_found + 1))
        else
          log_error "    $hook_name: CRASHES (exit $exit_code)"
          issues=$((issues + 1))
          hooks_broken=$((hooks_broken + 1))
        fi
      fi
    done

    if [ "$hooks_broken" -eq 0 ]; then
      log_dim "    All $hooks_found/7 hooks healthy"
    fi

    # --- Hook registration in .claude/settings.local.json ---
    echo ""
    echo -e "  ${BOLD}Hook Registration:${NC}"
    local claude_settings="$project_dir/.claude/settings.local.json"
    if [ -f "$claude_settings" ]; then
      local registered=0
      for hook_name in "${expected_hooks[@]}"; do
        if grep -q "$hook_name" "$claude_settings" 2>/dev/null; then
          registered=$((registered + 1))
        else
          log_warn "    $hook_name: NOT registered in .claude/settings.local.json"
          warnings=$((warnings + 1))
        fi
      done
      if [ "$registered" -eq 7 ]; then
        log_dim "    All 7 hooks registered in .claude/settings.local.json"
      else
        log_warn "    Only $registered/7 hooks registered — run: tasuki onboard"
      fi
    else
      log_warn "    .claude/settings.local.json: MISSING — hooks won't fire in Claude Code"
      warnings=$((warnings + 1))
    fi

    # --- Hook paths in .tasuki/settings.json match real files ---
    if [ -f "$claude_dir/settings.json" ]; then
      grep -oE '"command":\s*"[^"]*\.sh"' "$claude_dir/settings.json" 2>/dev/null | grep -oE '"[^"]*\.sh"' | sed 's/"//g' | while read -r hook_path; do
        if [ ! -f "$hook_path" ]; then
          log_warn "    broken path in settings.json: $hook_path"
          echo "warn" >> /tmp/tasuki_doctor_warns 2>/dev/null
        fi
      done
      if [ -f /tmp/tasuki_doctor_warns ]; then
        warnings=$((warnings + $(wc -l < /tmp/tasuki_doctor_warns)))
        rm -f /tmp/tasuki_doctor_warns
      fi
    fi
    echo ""

    # --- Agent files ---
    echo -e "  ${BOLD}Agent Files:${NC}"
    local agents_ok=0
    local agents_total=0
    for agent_file in "$claude_dir/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      agents_total=$((agents_total + 1))
      local agent_name
      agent_name=$(basename "$agent_file" .md)

      # Check if agent has "Before You Act" section
      if grep -q "Before You Act" "$agent_file" 2>/dev/null; then
        # Check if it has vault expand
        if grep -q "vault expand" "$agent_file" 2>/dev/null; then
          agents_ok=$((agents_ok + 1))
        else
          log_warn "    $agent_name: missing vault expand in Before You Act"
          warnings=$((warnings + 1))
        fi
      else
        log_warn "    $agent_name: missing Before You Act section"
        warnings=$((warnings + 1))
      fi
    done
    if [ "$agents_ok" -eq "$agents_total" ] && [ "$agents_total" -gt 0 ]; then
      log_dim "    All $agents_total agents have Before You Act + vault expand"
    fi
    echo ""

    # --- Mode ---
    echo -e "  ${BOLD}Mode:${NC}"
    local mode_file="$claude_dir/config/mode"
    if [ -f "$mode_file" ]; then
      local mode
      mode=$(cat "$mode_file" 2>/dev/null || echo "unknown")
      log_dim "    Current mode: $mode"
      case "$mode" in
        fast)    log_dim "    Graph depth: 0, Confidence: high only, Pipeline: shortened" ;;
        standard) log_dim "    Graph depth: 1, Confidence: high+experimental, Pipeline: full" ;;
        serious) log_dim "    Graph depth: 2, Confidence: all, Pipeline: full + 3 reviewer rounds" ;;
        *) log_warn "    Unknown mode: $mode"; warnings=$((warnings + 1)) ;;
      esac
    else
      log_dim "    Mode: standard (default, no config file)"
    fi
    echo ""

    # --- Memory vault ---
    echo -e "  ${BOLD}Memory Vault:${NC}"
    if [ -d "$project_dir/memory-vault" ]; then
      local node_count
      node_count=$(find "$project_dir/memory-vault" -name "*.md" -not -path "*/archive/*" 2>/dev/null | wc -l)
      log_dim "    Nodes: $node_count"

      # Count by confidence
      if command -v python3 &>/dev/null; then
        python3 -c "
import os, re
vault = '$project_dir/memory-vault'
counts = {'high': 0, 'experimental': 0, 'deprecated': 0, 'no-metadata': 0}
for root, dirs, files in os.walk(vault):
    if 'archive' in root: continue
    for f in files:
        if not f.endswith('.md') or f == 'index.md': continue
        try:
            with open(os.path.join(root, f)) as fh:
                content = fh.read()
            m = re.search(r'Confidence:\s*(\w+)', content)
            if m:
                c = m.group(1).lower()
                counts[c] = counts.get(c, 0) + 1
            else:
                counts['no-metadata'] += 1
        except: pass
for k, v in counts.items():
    if v > 0:
        print(f'    {k}: {v}')
" 2>/dev/null
      fi

      # Check for archived memories
      local archived_count=0
      if [ -d "$project_dir/memory-vault/archive" ]; then
        archived_count=$(find "$project_dir/memory-vault/archive" -name "*.md" 2>/dev/null | wc -l)
        if [ "$archived_count" -gt 0 ]; then
          log_dim "    Archived: $archived_count"
        fi
      fi

      # RAG sync status
      if [ -f "$claude_dir/config/rag-sync-batch.jsonl" ]; then
        local rag_entries
        rag_entries=$(wc -l < "$claude_dir/config/rag-sync-batch.jsonl" 2>/dev/null || echo "0")
        log_dim "    RAG entries: $rag_entries"
      else
        log_warn "    RAG not synced (run: tasuki vault sync)"
        warnings=$((warnings + 1))
      fi
    else
      log_warn "    Memory vault: NOT initialized (run: tasuki vault init)"
      warnings=$((warnings + 1))
    fi
    echo ""

    # --- Capability map ---
    echo -e "  ${BOLD}Discovery:${NC}"
    if [ -f "$claude_dir/config/capability-map.yaml" ]; then
      log_dim "    Capability map: exists"
    else
      log_warn "    Capability map: MISSING (run: tasuki discover)"
      warnings=$((warnings + 1))
    fi

    # --- Plans ---
    if [ -d "$project_dir/tasuki-plans" ]; then
      local plan_count
      plan_count=$(find "$project_dir/tasuki-plans" -name "prd.md" -o -name "plan.md" 2>/dev/null | wc -l)
      log_dim "    Plans: $plan_count features planned"
    else
      log_warn "    tasuki-plans: MISSING"
      warnings=$((warnings + 1))
    fi

    # --- Gitignore ---
    if [ -f "$project_dir/.gitignore" ]; then
      if grep -q ".tasuki" "$project_dir/.gitignore" 2>/dev/null; then
        log_dim "    .gitignore: .tasuki/ excluded"
      else
        log_warn "    .gitignore: .tasuki/ NOT excluded — config may be committed"
        warnings=$((warnings + 1))
      fi
    fi
    echo ""

    # 4. Staleness check
    echo -e "  ${BOLD}Staleness:${NC}"
    check_staleness "$project_dir" "$claude_dir"
    echo ""

    # 5. MCP connectivity
    echo -e "  ${BOLD}MCP Servers:${NC}"
    check_mcp_deps "$project_dir"
    echo ""

  else
    echo -e "  ${YELLOW}Project not onboarded.${NC} Run: tasuki onboard $project_dir"
    echo ""
  fi

  # Summary + auto-fix
  echo -e "${DIM}─────────────────${NC}"
  if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}HEALTHY${NC} — No issues found"
  elif [ "$issues" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}OK${NC} with $warnings warning(s)"
  else
    echo -e "  ${RED}${BOLD}ISSUES${NC} — $issues error(s), $warnings warning(s)"
  fi

  # Auto-fix if --fix flag or offer to fix
  if [ "$auto_fix" = "true" ] && [ "$issues" -gt 0 ] || [ "$warnings" -gt 0 ]; then
    echo ""
    log_step "Auto-fixing..."
    auto_fix_issues "$project_dir" "$claude_dir"
  elif [ "$issues" -gt 0 ] || [ "$warnings" -gt 0 ]; then
    echo ""
    echo -e "  Run ${CYAN}tasuki doctor --fix${NC} to auto-repair what's possible."
  fi
  echo ""
}

auto_fix_issues() {
  local project_dir="$1"
  local claude_dir="$2"
  local fixed=0

  # Fix: missing hooks → copy from templates
  local expected_hooks=("protect-files.sh" "security-check.sh" "tdd-guard.sh" "pipeline-tracker.sh" "pipeline-trigger.sh" "force-agent-read.sh" "force-planner-first.sh")
  mkdir -p "$claude_dir/hooks"
  for hook_name in "${expected_hooks[@]}"; do
    local hook_file="$claude_dir/hooks/$hook_name"
    local template_file="$TASUKI_TEMPLATES/hooks/$hook_name"
    if [ ! -f "$hook_file" ] && [ -f "$template_file" ]; then
      cp "$template_file" "$hook_file"
      chmod +x "$hook_file"
      log_success "  Fixed: $hook_name → copied from templates"
      fixed=$((fixed + 1))
    fi
  done

  # Fix: hooks not executable
  if [ -d "$claude_dir/hooks" ]; then
    for hook in "$claude_dir/hooks"/*.sh; do
      [ -f "$hook" ] || continue
      if [ ! -x "$hook" ]; then
        chmod +x "$hook"
        log_success "  Fixed: $(basename "$hook") → made executable"
        fixed=$((fixed + 1))
      fi
    done
  fi

  # Fix: missing TASUKI.md → re-onboard
  if [ ! -f "$project_dir/TASUKI.md" ] && [ -d "$claude_dir" ]; then
    log_info "  TASUKI.md missing → running onboard..."
    bash "$SCRIPT_DIR/onboard.sh" "$project_dir" 2>/dev/null
    fixed=$((fixed + 1))
  fi

  # Fix: missing capability map → run discover
  if [ ! -f "$claude_dir/config/capability-map.yaml" ] && [ -d "$claude_dir/agents" ]; then
    source "$SCRIPT_DIR/discover.sh"
    discover_agents "$project_dir" 2>/dev/null
    generate_capability_map "$project_dir" 2>/dev/null
    log_success "  Fixed: capability map regenerated"
    fixed=$((fixed + 1))
  fi

  # Fix: missing memory vault → init
  if [ ! -d "$project_dir/memory-vault" ]; then
    source "$SCRIPT_DIR/vault.sh"
    vault_init "$project_dir" 2>/dev/null
    log_success "  Fixed: memory vault initialized"
    fixed=$((fixed + 1))
  fi

  # Fix: missing project facts → generate
  if [ ! -f "$claude_dir/config/project-facts.md" ]; then
    source "$SCRIPT_DIR/facts.sh"
    generate_facts "$project_dir" 2>/dev/null
    log_success "  Fixed: project facts generated"
    fixed=$((fixed + 1))
  fi

  # Fix: missing tasuki-plans → create
  if [ ! -d "$project_dir/tasuki-plans" ]; then
    mkdir -p "$project_dir/tasuki-plans"
    echo "# Tasuki Plans" > "$project_dir/tasuki-plans/index.md"
    log_success "  Fixed: tasuki-plans/ created"
    fixed=$((fixed + 1))
  fi

  # Fix: memories without confidence metadata → add it
  if [ -d "$project_dir/memory-vault" ] && command -v python3 &>/dev/null; then
    local metadata_fixed=0
    metadata_fixed=$(python3 -c "
import os, re
vault = '$project_dir/memory-vault'
fixed = 0
today = '$(date "+%Y-%m-%d")'
for root, dirs, files in os.walk(vault):
    if 'archive' in root: continue
    for f in files:
        if not f.endswith('.md') or f == 'index.md': continue
        fpath = os.path.join(root, f)
        try:
            with open(fpath) as fh:
                content = fh.read()
        except: continue
        if 'Confidence:' not in content and 'Type:' in content:
            content = content.replace('Type:', f'Confidence: high\nLast-Validated: {today}\nApplied-Count: 0\nType:', 1)
            with open(fpath, 'w') as fh:
                fh.write(content)
            fixed += 1
print(fixed)
" 2>/dev/null || echo "0")
    if [ "$metadata_fixed" -gt 0 ]; then
      log_success "  Fixed: added confidence metadata to $metadata_fixed memories"
      fixed=$((fixed + metadata_fixed))
    fi
  fi

  # Fix: RAG not synced
  if [ -d "$project_dir/memory-vault" ] && [ ! -f "$claude_dir/config/rag-sync-batch.jsonl" ]; then
    source "$SCRIPT_DIR/vault.sh"
    vault_rag_sync "$project_dir" 2>/dev/null
    log_success "  Fixed: RAG synced"
    fixed=$((fixed + 1))
  fi

  # Fix: .gitignore missing .tasuki
  if [ -f "$project_dir/.gitignore" ]; then
    if ! grep -q ".tasuki" "$project_dir/.gitignore" 2>/dev/null; then
      echo -e "\n# Tasuki\n.tasuki/\nmemory-vault/\ntasuki-plans/" >> "$project_dir/.gitignore"
      log_success "  Fixed: added .tasuki/ to .gitignore"
      fixed=$((fixed + 1))
    fi
  fi

  # Fix: stale config → suggest re-onboard
  local changed_files=0
  if [ -f "$project_dir/TASUKI.md" ]; then
    for ext in py ts js tsx jsx go rb java php svelte vue; do
      local count
      count=$(find "$project_dir" -name "*.$ext" -not -path "*/.tasuki/*" -not -path "*/node_modules/*" -newer "$project_dir/TASUKI.md" 2>/dev/null | wc -l)
      changed_files=$((changed_files + count))
    done
    if [ "$changed_files" -gt 0 ]; then
      log_warn "  Stale: $changed_files files changed since last onboard"
      log_dim "    Run: tasuki facts . && tasuki discover ."
    fi
  fi

  echo ""
  if [ "$fixed" -gt 0 ]; then
    log_success "Auto-fixed $fixed issue(s)"
  else
    log_dim "  Nothing to auto-fix"
  fi

  # Run memory decay check
  if [ -d "$project_dir/memory-vault" ]; then
    echo ""
    log_step "Memory health:"
    source "$SCRIPT_DIR/vault.sh"
    vault_decay "$project_dir"
  fi
}

check_cmd() {
  local cmd="$1" desc="$2" optional="${3:-false}"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 | cut -c1-40 || echo "installed")
    log_dim "    $cmd: $version"
    return 0
  else
    if [ "$optional" = "true" ]; then
      log_warn "    $cmd: not found — $desc"
    else
      log_error "    $cmd: not found — $desc"
    fi
    return 1
  fi
}

check_staleness() {
  local project_dir="$1" claude_dir="$2"

  # Compare TASUKI.md timestamp vs latest source file change
  if [ -f "$project_dir/TASUKI.md" ]; then
    local claude_age
    claude_age=$(stat -c %Y "$project_dir/TASUKI.md" 2>/dev/null || stat -f %m "$project_dir/TASUKI.md" 2>/dev/null || echo "0")

    # Find newest source file
    local newest_source=0
    for ext in py ts js go rb java php svelte vue; do
      local newest
      newest=$(find "$project_dir" -name "*.$ext" -not -path "*/.tasuki/*" -not -path "*/node_modules/*" -not -path "*/__pycache__/*" -newer "$project_dir/TASUKI.md" 2>/dev/null | head -1)
      if [ -n "$newest" ]; then
        log_warn "    Source files changed since last onboard"
        log_dim "      Example: $newest"
        log_dim "      Run: tasuki diff  or  tasuki onboard"
        return
      fi
    done

    log_dim "    Config is up to date"
  fi
}

check_mcp_deps() {
  local project_dir="$1"

  if [ ! -f "$project_dir/.mcp.json" ]; then
    log_dim "    No .mcp.json"
    return
  fi

  # Check if npx is available for stdio MCPs
  grep -oE '"command":\s*"[^"]*"' "$project_dir/.mcp.json" 2>/dev/null | sed 's/"command":\s*"//;s/"//' | sort -u | while read -r cmd; do
    [ -z "$cmd" ] && continue
    if command -v "$cmd" &>/dev/null; then
      log_dim "    $cmd: available"
    else
      log_warn "    $cmd: not found (needed by MCP server)"
    fi
  done
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  doctor "$@"
fi
