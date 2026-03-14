#!/bin/bash
# Tasuki Engine — Onboard Orchestrator
# Runs the full onboarding pipeline: detect → profile → render → verify
# Usage: bash onboard.sh /path/to/project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/detect.sh"
source "$SCRIPT_DIR/profile.sh"
source "$SCRIPT_DIR/render.sh"

onboard_project() {
  local project_dir="${1:-.}"
  local dry_run="${2:-false}"
  local target="${3:-claude}"  # target AI tool

  # Resolve to absolute path
  if [ ! -d "$project_dir" ]; then
    log_error "Directory not found: $project_dir"
    exit 1
  fi
  project_dir="$(cd "$project_dir" && pwd)"

  echo ""
  if [ "$dry_run" = "true" ]; then
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║    Tasuki — Onboard (DRY RUN)        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  else
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       Tasuki — Project Onboard       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  fi
  echo ""

  # Phase 1: Detection
  run_detection "$project_dir"

  # Check if anything was detected
  if [ "${DETECTED[backend_detected]}" != "true" ] && \
     [ "${DETECTED[frontend_detected]}" != "true" ] && \
     [ "${DETECTED[database_detected]}" != "true" ]; then
    log_warn "No stack detected. Proceeding with generic profile."
    log_warn "Tip: Make sure you're pointing at a project with code, not an empty directory."
    echo ""
  fi

  # Phase 1.5: Interview — ask about business context (skippable)
  if [ "$dry_run" != "true" ] && [ -t 0 ]; then
    # Only run interview if we have a terminal (interactive mode)
    source "$SCRIPT_DIR/interview.sh"
    run_interview "$project_dir"
  fi

  # Phase 2: Profile matching + agent selection
  match_profile
  determine_active_agents

  if [ "$dry_run" = "true" ]; then
    # Dry run: show what WOULD be generated without writing
    print_dry_run_preview "$project_dir"
    return 0
  fi

  # Phase 3: Render internal config (agents, rules, hooks, skills — needed by all targets)
  render_project

  # Phase 3b: Apply domain profiles (industry-specific directives)
  apply_domain_profiles "$project_dir"

  # Phase 4: Verify
  verify_output "$project_dir"

  # Phase 5: Initialize Memory Vault (knowledge graph)
  log_step "Phase 5: VAULT — Initializing knowledge graph"
  echo ""
  source "$SCRIPT_DIR/vault.sh"
  vault_init "$project_dir"
  echo ""

  # Phase 5.5: Sync vault to RAG deep memory
  vault_rag_sync "$project_dir" 2>/dev/null

  # Phase 5.6: Generate project facts (anti-hallucination)
  log_step "Phase 5.5: FACTS — Generating verified project facts"
  echo ""
  source "$SCRIPT_DIR/facts.sh"
  generate_facts "$project_dir"
  echo ""

  # Phase 6: Generate capability map
  log_step "Phase 6: DISCOVER — Building capability map"
  echo ""
  source "$SCRIPT_DIR/discover.sh"
  discover_agents "$project_dir"
  local map_file
  map_file=$(generate_capability_map "$project_dir")
  log_success "Capability map: $(basename "$map_file")"
  log_dim "  ${#AGENT_PRIORITY[@]} agents discovered, ${#DOMAIN_TO_AGENTS[@]} domains indexed"
  echo ""

  # Phase 7: Auto-gitignore — keep tasuki out of the repo
  update_gitignore "$project_dir"

  # Phase 8: Write hooks to AI tool's native config
  write_ai_hooks "$project_dir"

  # Print final summary
  print_onboard_summary "$project_dir"
}

apply_domain_profiles() {
  local project_dir="$1"
  local context_file="$project_dir/.tasuki/config/project-context.md"
  local domains_dir="$TASUKI_ROOT/src/profiles/domains"

  [ ! -f "$context_file" ] && return 0
  [ ! -d "$domains_dir" ] && return 0

  local context
  context=$(cat "$context_file" 2>/dev/null || true)

  # Also check multi-tenant detection
  local is_multitenant="${DETECTED[database_multi_tenant]:-none}"

  if command -v python3 &>/dev/null; then
    python3 - "$context_file" "$domains_dir" "$project_dir" "$is_multitenant" << 'PYEOF'
import os, sys, re, yaml

context_file = sys.argv[1]
domains_dir = sys.argv[2]
project_dir = sys.argv[3]
is_multitenant = sys.argv[4]

with open(context_file) as f:
    context = f.read().lower()

applied = []

for domain_file in sorted(os.listdir(domains_dir)):
    if not domain_file.endswith('.yaml'):
        continue

    fpath = os.path.join(domains_dir, domain_file)
    try:
        with open(fpath) as f:
            profile = yaml.safe_load(f)
    except:
        # Fallback: parse yaml manually if pyyaml not available
        continue

    if not profile or 'match' not in profile:
        continue

    match = profile['match']
    matched = False

    # Match by industry keyword
    if 'industry' in match:
        pattern = match['industry']
        if re.search(pattern, context):
            matched = True

    # Match by multi-tenant
    if 'multi_tenant' in match and match['multi_tenant']:
        if is_multitenant not in ('none', ''):
            matched = True

    if not matched:
        continue

    # Apply directives to agent files
    directives = profile.get('directives', {})
    for agent_name, rules in directives.items():
        agent_file = os.path.join(project_dir, '.tasuki', 'agents', f'{agent_name}.md')
        if not os.path.exists(agent_file):
            continue

        with open(agent_file) as f:
            content = f.read()

        # Don't add if already has domain directives
        if '## Domain Directives' in content:
            continue

        # Insert before Handoff section
        insert_point = content.rfind('## Handoff')
        if insert_point == -1:
            insert_point = len(content)

        domain_name = domain_file.replace('.yaml', '').replace('-', ' ').title()
        block = f"\n---\n\n## Domain Directives — {domain_name}\n\n"
        for rule in rules:
            block += f"- {rule}\n"
        block += "\n"

        new_content = content[:insert_point] + block + content[insert_point:]
        with open(agent_file, 'w') as f:
            f.write(new_content)

    applied.append(domain_file.replace('.yaml', ''))

if applied:
    for a in applied:
        print(f'  applied domain: {a}')
PYEOF
    local applied_output
    applied_output=$(python3 - "$context_file" "$domains_dir" "$project_dir" "$is_multitenant" << 'PYEOF2'
import os, sys, re

context_file = sys.argv[1]
domains_dir = sys.argv[2]
project_dir = sys.argv[3]
is_multitenant = sys.argv[4]

with open(context_file) as f:
    context = f.read().lower()

applied = []
for domain_file in sorted(os.listdir(domains_dir)):
    if not domain_file.endswith('.yaml'):
        continue
    fpath = os.path.join(domains_dir, domain_file)
    with open(fpath) as f:
        raw = f.read()

    # Simple yaml parse without pyyaml
    match_line = ''
    for line in raw.split('\n'):
        if 'industry:' in line:
            match_line = line.split('industry:')[1].strip().strip('"')
        if 'multi_tenant:' in line and 'true' in line.lower():
            if is_multitenant not in ('none', ''):
                applied.append(domain_file.replace('.yaml', ''))
                break

    if match_line and re.search(match_line, context):
        if domain_file.replace('.yaml', '') not in applied:
            applied.append(domain_file.replace('.yaml', ''))

    if domain_file.replace('.yaml', '') in applied:
        # Parse directives manually
        in_directives = False
        current_agent = None
        rules = {}
        for line in raw.split('\n'):
            if line.strip() == 'directives:':
                in_directives = True
                continue
            if in_directives:
                if line.startswith('  ') and line.strip().endswith(':') and not line.strip().startswith('-'):
                    current_agent = line.strip().rstrip(':')
                    rules[current_agent] = []
                elif current_agent and line.strip().startswith('- "'):
                    rule = line.strip().lstrip('- ').strip('"')
                    rules[current_agent].append(rule)

        # Apply to agent files
        for agent_name, agent_rules in rules.items():
            agent_file = os.path.join(project_dir, '.tasuki', 'agents', f'{agent_name}.md')
            if not os.path.exists(agent_file):
                continue
            with open(agent_file) as f:
                content = f.read()
            if '## Domain Directives' in content:
                continue
            insert_point = content.rfind('## Handoff')
            if insert_point == -1:
                insert_point = len(content)
            domain_name = domain_file.replace('.yaml', '').replace('-', ' ').title()
            block = f"\n---\n\n## Domain Directives — {domain_name}\n\n"
            for rule in agent_rules:
                block += f"- {rule}\n"
            block += "\n"
            new_content = content[:insert_point] + block + content[insert_point:]
            with open(agent_file, 'w') as f:
                f.write(new_content)

for a in applied:
    print(a)
PYEOF2
    2>/dev/null)

    if [ -n "$applied_output" ]; then
      while IFS= read -r domain; do
        [ -n "$domain" ] && log_dim "  Domain profile applied: $domain"
      done <<< "$applied_output"
    fi
  fi
}

write_ai_hooks() {
  local project_dir="$1"

  # Claude Code: write hooks to .claude/settings.local.json
  local claude_settings="$project_dir/.claude/settings.local.json"
  if command -v python3 &>/dev/null; then
    mkdir -p "$project_dir/.claude"
    python3 -c "
import json, os

f = '$claude_settings'
data = {}
if os.path.exists(f):
    with open(f) as fh:
        try: data = json.load(fh)
        except: data = {}

# Ensure permissions exist with tasuki commands allowed
perms = data.setdefault('permissions', {})
allow = perms.setdefault('allow', [])
tasuki_perms = [
    'Bash(*)', 'Read(*)', 'Edit(*)', 'Write(*)',
    'Glob(*)', 'Grep(*)', 'Agent(*)', 'Notebook(*)'
]
for p in tasuki_perms:
    if p not in allow:
        allow.append(p)

# Write hooks
hooks = data.setdefault('hooks', {})

# PreToolUse — pipeline tracker on all tools
pre = hooks.setdefault('PreToolUse', [])
tracker_entry = {
    'matcher': 'Read|Edit|Write|Bash|Agent|Glob|Grep',
    'hooks': [{'type': 'command', 'command': '$project_dir/.tasuki/hooks/pipeline-tracker.sh'}]
}
edit_hooks = {
    'matcher': 'Edit|Write',
    'hooks': [
        {'type': 'command', 'command': '$project_dir/.tasuki/hooks/protect-files.sh'},
        {'type': 'command', 'command': '$project_dir/.tasuki/hooks/security-check.sh'},
        {'type': 'command', 'command': '$project_dir/.tasuki/hooks/tdd-guard.sh'},
        {'type': 'command', 'command': '$project_dir/.tasuki/hooks/force-agent-read.sh'},
        {'type': 'command', 'command': '$project_dir/.tasuki/hooks/force-planner-first.sh'}
    ]
}
# Clear old hook entries and write fresh
hooks['PreToolUse'] = [tracker_entry, edit_hooks]

# UserPromptSubmit — pipeline trigger
hooks['UserPromptSubmit'] = [{
    'hooks': [{'type': 'command', 'command': '$project_dir/.tasuki/hooks/pipeline-trigger.sh'}]
}]

with open(f, 'w') as fh:
    json.dump(data, fh, indent=2)
" 2>/dev/null
    log_dim "  Hooks written to .claude/settings.local.json"
  fi
}

update_gitignore() {
  local project_dir="$1"
  local gitignore="$project_dir/.gitignore"

  # Only if it's a git repo
  [ ! -d "$project_dir/.git" ] && return

  local entries=(".tasuki/" "memory-vault/" "tasuki-plans/" "TASUKI.md" "CLAUDE.md")
  local added=0

  for entry in "${entries[@]}"; do
    if [ -f "$gitignore" ]; then
      grep -qxF "$entry" "$gitignore" 2>/dev/null && continue
    fi
    echo "$entry" >> "$gitignore"
    added=$((added + 1))
  done

  if [ "$added" -gt 0 ]; then
    log_dim "  Added $added entries to .gitignore"
  fi
}

print_dry_run_preview() {
  local project_dir="$1"

  log_step "DRY RUN — What Tasuki would generate and WHY:"
  echo ""

  # Agents
  echo -e "  ${BOLD}.tasuki/agents/${NC} — ${DIM}specialized AI agents for your pipeline${NC}"
  for agent in "${ACTIVE_AGENTS[@]}"; do
    local reason=""
    case "$agent" in
      planner)     reason="designs architecture before anyone codes" ;;
      qa)          reason="writes tests FIRST — TDD enforcement" ;;
      db-architect) reason="safe migrations, zero-downtime DDL" ;;
      backend-dev) reason="implements until tests pass" ;;
      frontend-dev) reason="design preview before coding" ;;
      debugger)    reason="activates only when tests fail" ;;
      security)    reason="OWASP audit on every change" ;;
      reviewer)    reason="quality gate — nothing ships without approval" ;;
      devops)      reason="Docker, CI/CD, deployment" ;;
    esac
    echo -e "    ${GREEN}+${NC} ${agent}.md ${DIM}— $reason${NC}"
  done
  echo -e "    ${GREEN}+${NC} onboard.md ${DIM}— re-scan and regenerate config${NC}"
  echo ""

  # Rules
  echo -e "  ${BOLD}.tasuki/rules/${NC} — ${DIM}auto-loaded conventions per file type${NC}"
  [ "${DETECTED[backend_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} backend.md ${DIM}— ${DETECTED[backend_framework]} routing + API conventions${NC}"
  [ "${DETECTED[backend_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} models.md ${DIM}— ORM patterns, timestamps, soft delete${NC}"
  [ "${DETECTED[frontend_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} frontend.md ${DIM}— ${DETECTED[frontend_framework]} component conventions${NC}"
  [ "${DETECTED[database_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} migrations.md ${DIM}— safe migration patterns for ${DETECTED[database_migration_tool]:-your ORM}${NC}"
  echo -e "    ${GREEN}+${NC} docker.md ${DIM}— container security, health checks${NC}"
  echo -e "    ${GREEN}+${NC} tests.md ${DIM}— TDD workflow, test pyramid${NC}"
  echo -e "    ${GREEN}+${NC} context-loading.md ${DIM}— anti-hallucination protocol${NC}"
  echo ""

  # Hooks
  echo -e "  ${BOLD}.tasuki/hooks/${NC}"
  echo -e "    ${GREEN}+${NC} protect-files.sh"
  echo -e "    ${GREEN}+${NC} security-check.sh"
  echo -e "    ${GREEN}+${NC} tdd-guard.sh"
  echo -e "    ${GREEN}+${NC} pipeline-tracker.sh"
  echo -e "    ${GREEN}+${NC} pipeline-trigger.sh"
  echo -e "    ${GREEN}+${NC} force-agent-read.sh"
  echo -e "    ${GREEN}+${NC} force-planner-first.sh"
  echo ""

  # Skills
  echo -e "  ${BOLD}.tasuki/skills/${NC}"
  for s in tasuki-onboard tasuki-mode tasuki-status tasuki-plans context-compress memory-vault hotfix test-endpoint; do
    echo -e "    ${GREEN}+${NC} $s/"
  done
  [ "${DETECTED[database_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} db-migrate/"
  [ "${DETECTED[infra_detected]}" = "true" ] && echo -e "    ${GREEN}+${NC} deploy-check/"
  echo ""

  # Config files
  echo -e "  ${BOLD}Root files:${NC}"
  echo -e "    ${GREEN}+${NC} .tasuki/settings.json"
  echo -e "    ${GREEN}+${NC} .tasuki/config/protected-files.txt"
  echo -e "    ${GREEN}+${NC} .mcp.json"
  echo -e "    ${GREEN}+${NC} TASUKI.md"
  echo ""

  # Check for existing .claude
  if [ -d "$project_dir/.tasuki" ]; then
    log_warn "Existing .tasuki/ directory found — would be overwritten."
  fi
  if [ -f "$project_dir/TASUKI.md" ]; then
    log_warn "Existing TASUKI.md found — would be overwritten."
  fi

  echo ""
  echo -e "  ${BOLD}Profile:${NC} $(basename "$MATCHED_PROFILE" .yaml)"
  echo -e "  ${BOLD}Agents:${NC} ${#ACTIVE_AGENTS[@]} active"
  echo ""
  echo -e "  Run ${CYAN}tasuki onboard $project_dir${NC} (without --dry-run) to generate."
  echo ""
}

verify_output() {
  local project_dir="$1"
  local claude_dir="$project_dir/.tasuki"

  log_step "Phase 4: VERIFY — Checking generated configuration"
  echo ""

  local errors=0

  # Check TASUKI.md exists
  if [ -f "$project_dir/TASUKI.md" ]; then
    log_success "  TASUKI.md exists"
  else
    log_error "  TASUKI.md MISSING"
    ((errors++))
  fi

  # Check each active agent has a file
  for agent in "${ACTIVE_AGENTS[@]}"; do
    if [ -f "$claude_dir/agents/${agent}.md" ]; then
      log_dim "  agents/${agent}.md OK"
    else
      log_error "  agents/${agent}.md MISSING"
      ((errors++))
    fi
  done

  # Check settings.json
  if [ -f "$claude_dir/settings.json" ]; then
    log_dim "  settings.json OK"
  else
    log_error "  settings.json MISSING"
    ((errors++))
  fi

  # Check hooks
  if [ -f "$claude_dir/hooks/protect-files.sh" ] && [ -f "$claude_dir/hooks/security-check.sh" ]; then
    log_dim "  hooks/ OK"
  else
    log_error "  hooks/ MISSING"
    ((errors++))
  fi

  # Check .mcp.json
  if [ -f "$project_dir/.mcp.json" ]; then
    log_dim "  .mcp.json OK"
  else
    log_warn "  .mcp.json not generated"
  fi

  # Count unresolved placeholders in TASUKI.md
  if [ -f "$project_dir/TASUKI.md" ]; then
    local unresolved
    unresolved=$(grep -oE '\{\{[A-Z_]+\}\}' "$project_dir/TASUKI.md" 2>/dev/null | wc -l || true)
    unresolved="${unresolved:-0}"
    if [ "$unresolved" -gt 0 ]; then
      log_warn "  TASUKI.md has $unresolved unresolved placeholders:"
      grep -oE '\{\{[A-Z_]+\}\}' "$project_dir/TASUKI.md" 2>/dev/null | sort -u | while read -r ph; do
        log_dim "    $ph"
      done || true
    else
      log_success "  All placeholders resolved in TASUKI.md"
    fi
  fi

  echo ""

  if [ "$errors" -gt 0 ]; then
    log_error "Verification found $errors errors."
  else
    log_success "Verification passed!"
  fi

  echo ""
}

print_onboard_summary() {
  local project_dir="$1"
  local claude_dir="$project_dir/.tasuki"

  local agent_count
  agent_count=$(find "$claude_dir/agents" -name "*.md" 2>/dev/null | wc -l)
  local rule_count
  rule_count=$(find "$claude_dir/rules" -name "*.md" 2>/dev/null | wc -l)
  local skill_count
  skill_count=$(find "$claude_dir/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  local hook_count
  hook_count=$(find "$claude_dir/hooks" -name "*.sh" 2>/dev/null | wc -l)

  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║    Tasuki Onboarding Complete         ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Project:${NC}  ${DETECTED[project_name]}"

  # Stack line
  local stack="${DETECTED[backend_lang]:-?}/${DETECTED[backend_framework]:-?}"
  [ "${DETECTED[frontend_detected]}" = "true" ] && stack="$stack + ${DETECTED[frontend_framework]}"
  [ "${DETECTED[database_detected]}" = "true" ] && stack="$stack + ${DETECTED[database_engine]}"
  echo -e "  ${BOLD}Stack:${NC}    $stack"
  echo -e "  ${BOLD}Profile:${NC}  $(basename "$MATCHED_PROFILE" .yaml)"
  echo -e "  ${BOLD}Mode:${NC}     standard"
  echo ""

  echo -e "  ${BOLD}Detection:${NC}"
  [ "${DETECTED[backend_detected]}" = "true" ] && \
    echo -e "    Backend:  ${GREEN}${DETECTED[backend_framework]}${NC} (${DETECTED[backend_lang]})"
  [ "${DETECTED[frontend_detected]}" = "true" ] && \
    echo -e "    Frontend: ${GREEN}${DETECTED[frontend_framework]}${NC}"
  [ "${DETECTED[database_detected]}" = "true" ] && \
    echo -e "    Database: ${GREEN}${DETECTED[database_engine]}${NC} + ${DETECTED[database_orm]:-none}"
  [ "${DETECTED[infra_detected]}" = "true" ] && \
    echo -e "    Infra:    ${GREEN}${DETECTED[infra_containerization]}${NC}"
  [ "${DETECTED[testing_detected]}" = "true" ] && \
    echo -e "    Testing:  ${GREEN}${DETECTED[testing_backend_runner]:-?}${NC} + ${DETECTED[testing_frontend_runner]:-none}"
  echo ""

  echo -e "  ${BOLD}Agents (${#ACTIVE_AGENTS[@]}/10):${NC}"
  local all_agents=("planner" "qa" "db-architect" "backend-dev" "frontend-dev" "debugger" "security" "reviewer" "devops")
  for a in "${all_agents[@]}"; do
    if is_agent_active "$a"; then
      if [ "$a" = "debugger" ]; then
        echo -e "    ${YELLOW}[~]${NC} $a (reactive)"
      else
        echo -e "    ${GREEN}[x]${NC} $a"
      fi
    else
      echo -e "    ${DIM}[ ] $a (skipped)${NC}"
    fi
  done
  echo ""

  echo -e "  ${BOLD}Files generated:${NC}"
  echo -e "    .tasuki/agents/       — $agent_count agent files"
  echo -e "    .tasuki/rules/        — $rule_count rule files"
  echo -e "    .tasuki/hooks/        — $hook_count hooks"
  echo -e "    .tasuki/skills/       — $skill_count skills"
  echo -e "    .tasuki/settings.json — permissions + hooks"
  echo -e "    .mcp.json             — MCP servers"
  echo -e "    TASUKI.md             — orchestration brain"
  echo ""

  echo -e "  ${BOLD}Execution mode:${NC} standard (change with ${CYAN}tasuki mode [fast|serious|auto]${NC})"
  echo ""

  # Plugin recommendations
  print_recommendations

  # Cleanup suggestion
  print_cleanup_suggestion

  echo -e "  ${GREEN}Ready to test?${NC} Try: \"Plan a small feature to verify the pipeline\""
  echo ""
}

print_cleanup_suggestion() {
  local unused=()

  # Check for agents/skills that might not be needed
  if [ "${DETECTED[frontend_detected]}" != "true" ] && [ -f "${DETECTED[project_dir]}/.tasuki/agents/frontend-dev.md" ]; then
    unused+=("frontend-dev agent")
  fi
  if [ "${DETECTED[backend_detected]}" != "true" ] && [ -f "${DETECTED[project_dir]}/.tasuki/agents/backend-dev.md" ]; then
    unused+=("backend-dev agent")
  fi
  if [ "${DETECTED[database_detected]}" != "true" ] && [ -f "${DETECTED[project_dir]}/.tasuki/agents/db-architect.md" ]; then
    unused+=("db-architect agent")
  fi
  if [ "${DETECTED[frontend_detected]}" != "true" ] && [ -d "${DETECTED[project_dir]}/.tasuki/skills/ui-design" ]; then
    unused+=("ui-design skill")
  fi

  if [ ${#unused[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}${BOLD}Unused components detected:${NC}"
    for item in "${unused[@]}"; do
      echo -e "    ${DIM}- $item${NC}"
    done
    echo -e "    ${DIM}These were kept in case you need them later.${NC}"
    echo -e "    Run ${CYAN}tasuki cleanup${NC} to remove what you don't need."
    echo -e "    Run ${CYAN}tasuki restore${NC} to bring anything back."
    echo ""
  fi
}

print_recommendations() {
  local recs=()

  # Frontend detected → suggest design tools
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    local fw="${DETECTED[frontend_framework]}"
    recs+=("tasuki install mcp playwright     ${DIM}# E2E browser testing for $fw${NC}")
    case "$fw" in
      sveltekit|svelte|react|nextjs|vue|nuxt)
        recs+=("tasuki install mcp stitch         ${DIM}# Preview UI designs before coding${NC}")
        ;;
    esac
  fi

  # Backend API detected → suggest API tools
  if [ "${DETECTED[backend_detected]}" = "true" ]; then
    recs+=("tasuki install skill gen-openapi   ${DIM}# Generate OpenAPI spec from routes${NC}")
    recs+=("tasuki install skill perf-check    ${DIM}# Detect N+1 queries, missing indexes${NC}")
  fi

  # Database detected → suggest DB tools
  if [ "${DETECTED[database_detected]}" = "true" ]; then
    recs+=("tasuki install skill seed-data     ${DIM}# Generate test seed data${NC}")
  fi

  # Testing detected → suggest test tools
  if [ "${DETECTED[testing_detected]}" = "true" ] || [ "${DETECTED[testing_e2e]}" = "playwright" ]; then
    : # playwright already suggested above
  fi

  # Always suggest env-check if .env exists
  if [ -f "${DETECTED[project_dir]}/.env.example" ] || [ -f "${DETECTED[project_dir]}/.env" ]; then
    recs+=("tasuki install skill env-check     ${DIM}# Validate env vars across environments${NC}")
  fi

  # Error tracking
  recs+=("tasuki install mcp sentry           ${DIM}# Error tracking and monitoring${NC}")

  if [ ${#recs[@]} -gt 0 ]; then
    echo -e "  ${BOLD}Recommended plugins:${NC}"
    for rec in "${recs[@]}"; do
      echo -e "    ${CYAN}$rec"
    done
    echo ""
  fi
}

# If run directly (not sourced), execute onboard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  onboard_project "$@"
fi
