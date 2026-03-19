#!/bin/bash
# Tasuki Engine — Template Rendering Engine
# Renders all templates with detected values and writes the .tasuki/ directory.
# Usage: source this file, then call render_project (requires DETECTED, CONVENTIONS, ACTIVE_AGENTS)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Global: associative array of all template variables
declare -A TASUKI_VARS

# Build the variable map from detection results and conventions
build_variable_map() {
  local project_dir="${DETECTED[project_dir]}"

  # Project info
  TASUKI_VARS[PROJECT_NAME]="${DETECTED[project_name]}"
  TASUKI_VARS[PROJECT_DESCRIPTION]="Multi-agent development pipeline for ${DETECTED[project_name]}"
  TASUKI_VARS[PROJECT_PATH]="$project_dir"

  # Paths
  TASUKI_VARS[BACKEND_PATH]="${DETECTED[backend_path]}"
  TASUKI_VARS[FRONTEND_PATH]="${DETECTED[frontend_path]}"
  TASUKI_VARS[MODELS_PATH]="${DETECTED[models_path]}"
  TASUKI_VARS[MIGRATIONS_PATH]="${DETECTED[migrations_path]}"
  TASUKI_VARS[TEST_PATH]="${DETECTED[test_path]}"
  TASUKI_VARS[DOCKER_COMPOSE_PATH]="${DETECTED[docker_compose_path]}"
  TASUKI_VARS[CI_CD_CONFIG_PATH]="${DETECTED[ci_cd_config_path]}"

  # Stack
  TASUKI_VARS[BACKEND_LANG]="${DETECTED[backend_lang]:-unknown}"
  TASUKI_VARS[BACKEND_FRAMEWORK]="${DETECTED[backend_framework]:-unknown}"
  TASUKI_VARS[FRONTEND_FRAMEWORK]="${DETECTED[frontend_framework]:-none}"
  TASUKI_VARS[FRONTEND_STYLING]="${DETECTED[frontend_styling]:-unknown}"
  TASUKI_VARS[FRONTEND_STATE]="${DETECTED[frontend_state]:-unknown}"
  TASUKI_VARS[DB_ENGINE]="${DETECTED[database_engine]:-none}"
  TASUKI_VARS[ORM]="${DETECTED[database_orm]:-none}"
  TASUKI_VARS[MIGRATION_TOOL]="${DETECTED[database_migration_tool]:-none}"
  TASUKI_VARS[DB_CREDENTIALS_REF]="see .env"

  # Commands
  TASUKI_VARS[RUN_CMD]="${DETECTED[run_cmd]}"
  TASUKI_VARS[MIGRATION_CONVENTION]="${DETECTED[database_migration_tool]:-manual} migrations"

  # Auth
  local auth="${DETECTED[backend_auth_pattern]:-unknown}"
  case "$auth" in
    jwt)
      TASUKI_VARS[AUTH_PATTERN]="JWT authentication via \`Depends(get_current_user)\`. Tokens signed with HS256, signing key from env. Access tokens expire in 15-30 min."
      TASUKI_VARS[AUTH_GREP_PATTERN]="grep -rn 'def.*(' ${DETECTED[backend_path]} --include='*.py' | grep -v 'get_current_user\\|Depends\\|def test_\\|conftest\\|__init__'"
      ;;
    django-auth)
      TASUKI_VARS[AUTH_PATTERN]="Django built-in authentication with session middleware and permission classes."
      TASUKI_VARS[AUTH_GREP_PATTERN]="grep -rn 'class.*View' ${DETECTED[backend_path]} --include='*.py' | grep -v 'permission_classes\\|IsAuthenticated'"
      ;;
    *)
      TASUKI_VARS[AUTH_PATTERN]="Authentication pattern: $auth. Check the auth middleware for details."
      TASUKI_VARS[AUTH_GREP_PATTERN]="# Auth grep pattern not configured for this stack"
      ;;
  esac

  # Conventions from profile
  TASUKI_VARS[CONVENTIONS_BACKEND]="${CONVENTIONS[routing]:-No specific backend conventions}"
  TASUKI_VARS[CONVENTIONS_FRONTEND]="${CONVENTIONS[frontend]:-No specific frontend conventions}"
  TASUKI_VARS[CONVENTIONS_MODELS]="${CONVENTIONS[models]:-No specific model conventions}"
  TASUKI_VARS[CONVENTIONS_MIGRATIONS]="${CONVENTIONS[migrations]:-No specific migration conventions}"
  # Tools from profile (verified commands)
  TASUKI_VARS[TEST_COMMAND]="${CONVENTIONS[test_runner]:-echo 'test runner not configured'}"

  # Security
  TASUKI_VARS[SECURITY_CHECKS]=$(build_security_checks)
  TASUKI_VARS[FRONTEND_XSS_GREP]=$(build_xss_grep)

  # Mode
  local current_mode="${DETECTED[mode]:-standard}"
  TASUKI_VARS[CURRENT_MODE]="$current_mode"
  TASUKI_VARS[MODE_BEHAVIOR]="Full pipeline with TDD enforcement. Sonnet for implementation, Opus for planning and review.\n\n**Memory by mode:**\n- **Fast mode**: Wikilinks only (Layer 1). No RAG queries.\n- **Standard mode**: Wikilinks + RAG when agent needs deeper context.\n- **Serious mode**: Wikilinks + RAG mandatory. Every agent MUST query RAG before acting for full project context (schema, incidents, related code)."

  # Graph depth is now auto-detected by vault expand from .tasuki/config/mode

  # Dynamic sections (tables, lists)
  TASUKI_VARS[SKILLS_TABLE]=$(build_skills_table)
  TASUKI_VARS[RULES_LIST]=$(build_rules_list)
  TASUKI_VARS[MCP_TABLE]=$(build_mcp_table)
  TASUKI_VARS[HOOKS_LIST]=$(build_hooks_list)

  # Docker/Infra
  TASUKI_VARS[PORT]="8000"
  TASUKI_VARS[HEALTH_ENDPOINT]="/health"
  TASUKI_VARS[FRONTEND_URL]="http://localhost:3000"
}

build_security_checks() {
  local checks=""
  local lang="${DETECTED[backend_lang]}"

  case "$lang" in
    python)
      checks="# Python security scan
bandit -r ${DETECTED[backend_path]} -f json 2>/dev/null || echo 'bandit not installed'
pip-audit 2>/dev/null || echo 'pip-audit not installed'"
      ;;
    javascript|typescript)
      checks="# JavaScript/TypeScript security scan
npm audit --json 2>/dev/null || echo 'npm audit failed'
npx eslint --ext .js,.ts ${DETECTED[backend_path]} 2>/dev/null || true"
      ;;
    go)
      checks="# Go security scan
gosec ./... 2>/dev/null || echo 'gosec not installed'
go list -json -m all 2>/dev/null | nancy 2>/dev/null || true"
      ;;
    *)
      checks="# Generic security scan — add stack-specific tools
grep -rn 'password.*=.*[\"'\\'']\|secret.*=.*[\"'\\'']\|api_key.*=.*[\"'\\'']]' . --include='*.py' --include='*.ts' --include='*.js' 2>/dev/null || true"
      ;;
  esac

  echo "$checks"
}

build_xss_grep() {
  local fw="${DETECTED[frontend_framework]}"
  case "$fw" in
    sveltekit|svelte) echo "grep -rn '{@html' ${DETECTED[frontend_path]} --include='*.svelte'" ;;
    react|nextjs) echo "grep -rn 'dangerouslySetInnerHTML' ${DETECTED[frontend_path]} --include='*.tsx' --include='*.jsx'" ;;
    vue|nuxt) echo "grep -rn 'v-html' ${DETECTED[frontend_path]} --include='*.vue'" ;;
    angular) echo "grep -rn 'bypassSecurityTrust' ${DETECTED[frontend_path]} --include='*.ts'" ;;
    *) echo "# No frontend XSS grep pattern for $fw" ;;
  esac
}

build_pipeline_table() {
  local table=""
  local stage=1

  # Planner
  if is_agent_active "planner"; then
    table+="| $stage | /planner | Planner | Analyzes requirements, designs architecture, creates implementation plan | Simple bug fix, small tweak |
"
    ((stage++))
  fi

  # QA (pre-implementation)
  if is_agent_active "qa"; then
    table+="| $stage | /qa | QA | Writes failing tests FIRST (TDD) | No testable changes |
"
    ((stage++))
  fi

  # DB Architect
  if is_agent_active "db-architect"; then
    table+="| $stage | /db-architect | DB | Designs schema, writes migrations | No schema changes |
"
    ((stage++))
  fi

  # Backend Dev
  if is_agent_active "backend-dev"; then
    table+="| $stage | /backend-dev | Dev | Implements backend: routers, services, models | No backend changes |
"
    ((stage++))
  fi

  # Frontend Dev
  if is_agent_active "frontend-dev"; then
    table+="| $stage | /frontend-dev | FrontDev | Implements frontend: pages, components, stores | No frontend changes |
"
    ((stage++))
  fi

  # Debugger (reactive)
  table+="| - | /debugger | Debugger | Diagnoses failures (reactive, on-demand only) | Everything passes |
"

  # Security
  if is_agent_active "security"; then
    table+="| $stage | /security | SecEng | OWASP audit, vulnerability scan, dependency check | Never skipped |
"
    ((stage++))
  fi

  # Reviewer
  if is_agent_active "reviewer"; then
    table+="| $stage | /reviewer | Reviewer | Quality gate: review, delegate fixes, re-review | Never skipped |
"
    ((stage++))
  fi

  # DevOps
  if is_agent_active "devops"; then
    table+="| $stage | /devops | DevOps | Docker, CI/CD, deployment, infrastructure | No infra changes |
"
    ((stage++))
  fi

  echo "$table"
}

build_stage_details() {
  # Simplified: each active agent gets a brief description
  local details=""

  for agent in "${ACTIVE_AGENTS[@]}"; do
    case "$agent" in
      planner)    details+="#### Planner
Reads the codebase, identifies affected components, and produces a structured implementation plan. Output goes to the next stage, not to production.

" ;;
      qa)         details+="#### QA
Writes tests FIRST (TDD). Backend tests before frontend tests. Tests must fail before implementation begins.

" ;;
      db-architect) details+="#### DB Architect
Designs schema changes and writes migrations. Uses ${DETECTED[database_migration_tool]:-the project's migration tool}. All migrations must be idempotent.

" ;;
      backend-dev) details+="#### Backend Dev
Implements backend code: routers, services, schemas, background jobs. Runs existing tests to verify changes.

" ;;
      frontend-dev) details+="#### Frontend Dev
Implements frontend: pages, components, stores. Follows ${DETECTED[frontend_framework]:-the project's} patterns.

" ;;
      debugger)   details+="#### Debugger
Reactive agent. Only activated when tests fail or runtime errors occur. Traces root cause through logs, DB state, and code.

" ;;
      security)   details+="#### Security
Runs OWASP Top 10:2025 audit on every change. Delegates fixes to specialist agents. Re-scans after remediation.

" ;;
      reviewer)   details+="#### Reviewer
Quality gate. Reviews all changes for security, correctness, performance, conventions. Can delegate fixes and re-review. Nothing passes without Reviewer approval.

" ;;
      devops)     details+="#### DevOps
Manages Docker, CI/CD, reverse proxy, deployments. Only acts after Reviewer approval.

" ;;
    esac
  done

  echo "$details"
}

build_skills_table() {
  local table=""
  table+="| tasuki-onboard | /tasuki-onboard | Scan codebase and regenerate .tasuki/ config | onboard agent |
"
  table+="| tasuki-mode | /tasuki-mode [mode] | Switch execution mode (fast/standard/serious/auto) | user |
"
  table+="| tasuki-status | /tasuki-status | Show current pipeline configuration | user |
"
  table+="| hotfix | /hotfix | Create hotfix branch, minimal fix, run tests | any agent |
"
  table+="| test-endpoint | /test-endpoint [url] | Test API endpoint with curl | qa, dev |
"

  if [ "${DETECTED[database_detected]}" = "true" ]; then
    table+="| db-migrate | /db-migrate | Create new database migration | db-architect |
"
  fi

  if [ "${DETECTED[infra_detected]}" = "true" ]; then
    table+="| deploy-check | /deploy-check | Health check all services | devops |
"
  fi

  echo "$table"
}

build_rules_list() {
  local list=""

  if [ "${DETECTED[backend_detected]}" = "true" ]; then
    list+="- **backend.md**: Backend conventions for ${DETECTED[backend_framework]}
"
    list+="- **models.md**: ORM/model conventions for ${DETECTED[database_orm]:-the project's ORM}
"
  fi

  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    list+="- **frontend.md**: Frontend conventions for ${DETECTED[frontend_framework]}
"
  fi

  if [ "${DETECTED[database_detected]}" = "true" ]; then
    list+="- **migrations.md**: Migration conventions for ${DETECTED[database_migration_tool]:-the project's migration tool}
"
  fi

  list+="- **docker.md**: Docker and infrastructure best practices
"
  list+="- **tests.md**: TDD workflow and testing conventions
"

  echo "$list"
}

build_mcp_table() {
  local table=""

  # Always-on MCPs
  table+="| context7 | stdio | Up-to-date documentation for libraries and frameworks | All agents |
"
  table+="| taskmaster-ai | stdio | Task management and project orchestration | planner |
"
  table+="| semgrep | stdio | Static analysis and security scanning | security |
"

  # GitHub MCP if git repo
  if [ -d "${DETECTED[project_dir]}/.git" ]; then
    table+="| github | http | GitHub integration (PRs, issues, actions) | reviewer, devops |
"
  fi

  # Sentry (always useful)
  table+="| sentry | http | Error tracking and monitoring | debugger, devops |
"

  # Database MCPs
  if [ "${DETECTED[database_engine]}" = "postgresql" ] || [ "${DETECTED[database_engine]}" = "postgres" ]; then
    table+="| postgres | stdio | Direct database access for schema inspection | db-architect, debugger |
"
  fi

  # Frontend MCPs
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    table+="| figma | http | Design specs and assets from Figma | frontend-dev |
"
    table+="| stitch | stdio | Preview UI designs before coding (Google Stitch) | frontend-dev |
"
    table+="| playwright | stdio | Browser automation for E2E testing | qa, frontend-dev |
"
  fi

  echo "$table"
}

build_hooks_list() {
  local list="- **protect-files.sh** (PreToolUse: Edit|Write): Blocks edits to sensitive files (.env, secrets/, lock files)
- **security-check.sh** (PreToolUse: Edit|Write): Scans for security anti-patterns (SQL injection, hardcoded secrets, unsafe functions)
- **tdd-guard.sh** (PreToolUse: Edit|Write): Blocks implementation code if tests don't exist yet (TDD enforcement)
- **pipeline-tracker.sh** (PostToolUse): Tracks pipeline stage transitions and logs agent activity
- **pipeline-trigger.sh** (UserPromptSubmit): Activates the pipeline when user says 'tasuki' in their prompt
- **force-agent-read.sh** (PreToolUse): Forces agents to read their agent file before acting
- **force-planner-first.sh** (PreToolUse): Ensures the planner agent runs before any implementation agents
- **teammate-idle.sh** (TeammateIdle): Quality gate — runs tests and security checks before a teammate can go idle (Agent Teams)
- **task-completed.sh** (TaskCompleted): Validates acceptance criteria before marking a task done (Agent Teams)"
  echo "$list"
}

is_agent_active() {
  local name="$1"
  for agent in "${ACTIVE_AGENTS[@]}"; do
    if [ "$agent" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

# --- Main render function ---
render_project() {
  local project_dir="${DETECTED[project_dir]}"
  local claude_dir="$project_dir/.tasuki"

  log_step "Phase 3: GENERATE — Rendering configuration"
  echo ""

  # Build all template variables
  build_variable_map

  # 3a: Create directories
  log_info "Creating .tasuki/ directory structure..."
  mkdir -p "$claude_dir"/{agents,rules,hooks,skills,agent-memory,config}

  # 3b: Render agent files
  log_info "Rendering agent templates..."
  render_agents "$claude_dir"

  # 3c: Render rule files
  log_info "Rendering rule templates..."
  render_rules "$claude_dir"

  # 3d: Copy hooks
  log_info "Copying hooks..."
  render_hooks "$claude_dir"

  # 3e: Copy skills
  log_info "Copying skills..."
  render_skills "$claude_dir"

  # 3f: Render settings.json
  log_info "Rendering settings.json..."
  render_settings "$claude_dir"

  # 3g: Generate .mcp.json
  log_info "Generating .mcp.json..."
  render_mcp_json "$project_dir"

  # 3h: Render TASUKI.md
  log_info "Rendering TASUKI.md..."
  render_brain_md "$project_dir"

  # 3i: Generate protected-files config
  log_info "Generating protected-files config..."
  render_protected_files "$claude_dir"

  # 3j: Initialize tasuki-plans directory
  log_info "Initializing tasuki-plans/..."
  render_plans_dir "$project_dir"

  echo ""
  log_success "Configuration generated!"
  echo ""
}

render_plans_dir() {
  local project_dir="$1"
  local plans_dir="$project_dir/tasuki-plans"

  if [ -d "$plans_dir" ]; then
    log_dim "  tasuki-plans/ already exists"
    return
  fi

  mkdir -p "$plans_dir"

  local project_name="${DETECTED[project_name]}"
  local date
  date=$(date '+%Y-%m-%d')

  cat > "$plans_dir/index.md" << EOF
# Tasuki Plans — $project_name

All implementation plans created by the Planner agent. Each feature gets a PRD, plan, and status tracker.

| Feature | Status | Created | PRD | Plan |
|---------|--------|---------|-----|------|

<!-- New plans are appended here automatically by the Planner agent -->
EOF

  log_dim "  tasuki-plans/index.md"
}

render_agents() {
  local claude_dir="$1"

  for agent in "${ACTIVE_AGENTS[@]}"; do
    local template="$TASUKI_TEMPLATES/agents/${agent}.md"
    local output="$claude_dir/agents/${agent}.md"

    if [ -f "$template" ]; then
      render_placeholders "$template" "$output"
      # Inject interview-based directives into agent file
      inject_agent_directives "$agent" "$output"
      log_dim "  ${agent}.md"
    else
      log_warn "  Template not found: $template"
    fi
  done

  # Always copy onboard agent
  if [ -f "$TASUKI_TEMPLATES/agents/onboard.md" ]; then
    render_placeholders "$TASUKI_TEMPLATES/agents/onboard.md" "$claude_dir/agents/onboard.md"
    log_dim "  onboard.md"
  fi
}

inject_agent_directives() {
  local agent="$1"
  local output="$2"
  local context_file="${TASUKI_VARS[PROJECT_PATH]}/.tasuki/config/project-context.md"

  # Only inject if context file exists and has agent directives
  [ ! -f "$context_file" ] && return
  grep -q "Agent Directives" "$context_file" 2>/dev/null || return

  # Extract directives for this agent
  local agent_title=""
  case "$agent" in
    security)    agent_title="Security Agent" ;;
    qa)          agent_title="QA Agent" ;;
    backend-dev) agent_title="Backend Dev Agent" ;;
    devops)      agent_title="DevOps Agent" ;;
    db-architect) agent_title="DB Architect Agent" ;;
    reviewer)    agent_title="Reviewer Agent" ;;
    *) return ;;
  esac

  # Extract the section for this agent from context file
  local directives=""
  directives=$(awk -v title="### $agent_title" '
    $0 == title { found=1; next }
    found && /^### / { found=0 }
    found && /^## / { found=0 }
    found { print }
  ' "$context_file" 2>/dev/null)

  if [ -n "$directives" ]; then
    {
      echo ""
      echo "## Project-Specific Directives (from onboard interview)"
      echo ""
      echo "$directives"
    } >> "$output"
  fi
}

render_rules() {
  local claude_dir="$1"

  # Backend rules
  if [ "${DETECTED[backend_detected]}" = "true" ]; then
    render_placeholders "$TASUKI_TEMPLATES/rules/backend.md" "$claude_dir/rules/backend.md"
    log_dim "  backend.md"

    render_placeholders "$TASUKI_TEMPLATES/rules/models.md" "$claude_dir/rules/models.md"
    log_dim "  models.md"
  fi

  # Frontend rules
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    render_placeholders "$TASUKI_TEMPLATES/rules/frontend.md" "$claude_dir/rules/frontend.md"
    log_dim "  frontend.md"
  fi

  # Migration rules
  if [ "${DETECTED[database_detected]}" = "true" ]; then
    render_placeholders "$TASUKI_TEMPLATES/rules/migrations.md" "$claude_dir/rules/migrations.md"
    log_dim "  migrations.md"
  fi

  # Docker rules (always — even if no Docker yet, the rules are useful)
  render_placeholders "$TASUKI_TEMPLATES/rules/docker.md" "$claude_dir/rules/docker.md"
  log_dim "  docker.md"

  # Test rules (always)
  render_placeholders "$TASUKI_TEMPLATES/rules/tests.md" "$claude_dir/rules/tests.md"
  log_dim "  tests.md"

  # Context loading protocol (always — anti-hallucination)
  cp "$TASUKI_TEMPLATES/rules/context-loading.md" "$claude_dir/rules/context-loading.md"
  log_dim "  context-loading.md"
}

render_hooks() {
  local claude_dir="$1"

  # Core hooks (always installed)
  local core_hooks=("protect-files" "security-check" "tdd-guard" "pipeline-tracker" "pipeline-trigger" "force-agent-read" "force-planner-first")
  for hook in "${core_hooks[@]}"; do
    cp "$TASUKI_TEMPLATES/hooks/${hook}.sh" "$claude_dir/hooks/"
    log_dim "  ${hook}.sh"
  done

  # Agent Teams hooks (always copy — activated only when Agent Teams is enabled)
  local team_hooks=("teammate-idle" "task-completed")
  for hook in "${team_hooks[@]}"; do
    if [ -f "$TASUKI_TEMPLATES/hooks/${hook}.sh" ]; then
      cp "$TASUKI_TEMPLATES/hooks/${hook}.sh" "$claude_dir/hooks/"
      log_dim "  ${hook}.sh (Agent Teams)"
    fi
  done

  chmod +x "$claude_dir/hooks/"*.sh
}

render_skills() {
  local claude_dir="$1"

  # Always copy these skills
  local always_skills=("tasuki-onboard" "tasuki-mode" "tasuki-status" "tasuki-plans" "context-compress" "memory-vault" "hotfix" "test-endpoint")

  for skill in "${always_skills[@]}"; do
    local src="$TASUKI_TEMPLATES/skills/$skill"
    local dst="$claude_dir/skills/$skill"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp "$src/SKILL.md" "$dst/SKILL.md"
      log_dim "  $skill"
    fi
  done

  # Conditional skills
  if [ "${DETECTED[database_detected]}" = "true" ]; then
    local src="$TASUKI_TEMPLATES/skills/db-migrate"
    local dst="$claude_dir/skills/db-migrate"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp "$src/SKILL.md" "$dst/SKILL.md"
      log_dim "  db-migrate"
    fi
  fi

  if [ "${DETECTED[infra_detected]}" = "true" ]; then
    local src="$TASUKI_TEMPLATES/skills/deploy-check"
    local dst="$claude_dir/skills/deploy-check"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp "$src/SKILL.md" "$dst/SKILL.md"
      log_dim "  deploy-check"
    fi
  fi

  # Frontend: UI design skills
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    local src="$TASUKI_TEMPLATES/skills/ui-design"
    local dst="$claude_dir/skills/ui-design"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp "$src/SKILL.md" "$dst/SKILL.md"
      log_dim "  ui-design"
    fi

    # UI/UX Pro Max — comprehensive design intelligence (161 rules, 67 styles, 57 font pairings)
    local src="$TASUKI_TEMPLATES/skills/ui-ux-pro-max"
    local dst="$claude_dir/skills/ui-ux-pro-max"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp "$src/SKILL.md" "$dst/SKILL.md"
      log_dim "  ui-ux-pro-max"
    fi
  fi
}

render_settings() {
  local claude_dir="$1"
  render_placeholders "$TASUKI_TEMPLATES/settings.json" "$claude_dir/settings.json"

  # Add stack-specific permissions
  local settings_file="$claude_dir/settings.json"
  local extra_allows=""

  case "${DETECTED[backend_lang]}" in
    python)
      extra_allows='"Bash(python3 *)", "Bash(pip *)", "Bash(alembic *)", "Bash(pytest *)", "Bash(ruff *)"'
      ;;
    javascript|typescript)
      extra_allows='"Bash(node *)", "Bash(npx *)", "Bash(pnpm *)", "Bash(yarn *)"'
      ;;
    go)
      extra_allows='"Bash(go *)", "Bash(gosec *)"'
      ;;
    ruby)
      extra_allows='"Bash(bundle *)", "Bash(rails *)", "Bash(rake *)"'
      ;;
  esac

  if [ -n "$extra_allows" ]; then
    # Insert extra allows before the closing ] of the allow array
    sed -i "s|\"Read({{PROJECT_PATH}}/\*\*)\"|\"Read(${DETECTED[project_dir]}/**)\", $extra_allows|" "$settings_file" 2>/dev/null || true
  fi

  log_dim "  settings.json"
}

render_mcp_json() {
  local project_dir="$1"
  local mcp_file="$project_dir/.mcp.json"
  local has_git=false
  local has_postgres=false
  local has_frontend=false

  [ -d "$project_dir/.git" ] && has_git=true
  { [ "${DETECTED[database_engine]}" = "postgresql" ] || [ "${DETECTED[database_engine]}" = "postgres" ]; } && has_postgres=true
  [ "${DETECTED[frontend_detected]}" = "true" ] && has_frontend=true

  local server_count=0

  # Build JSON directly — always-on MCPs first
  cat > "$mcp_file" << 'MCPEOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
MCPEOF
  server_count=$((server_count + 1))

  # GitHub
  if $has_git; then
    cat >> "$mcp_file" << 'MCPEOF'
    ,"github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    }
MCPEOF
    server_count=$((server_count + 1))
  fi

  # Sentry — only if uvx or sentry token available
  if command -v uvx &>/dev/null || [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
    cat >> "$mcp_file" << 'MCPEOF'
    ,"sentry": {
      "type": "http",
      "url": "https://mcp.sentry.dev/mcp"
    }
MCPEOF
    server_count=$((server_count + 1))
  fi

  # Semgrep — only if uvx available
  if command -v uvx &>/dev/null; then
    cat >> "$mcp_file" << 'MCPEOF'
    ,"semgrep": {
      "command": "uvx",
      "args": ["semgrep-mcp"],
      "timeout": 30000
    }
MCPEOF
    server_count=$((server_count + 1))
  fi

  # Taskmaster — task management for planner
  cat >> "$mcp_file" << 'MCPEOF'
    ,"taskmaster-ai": {
      "command": "npx",
      "args": ["-y", "task-master-ai@latest"],
      "env": {
        "TASK_MASTER_TOOLS": "standard"
      }
    }
MCPEOF
  server_count=$((server_count + 1))

  # Postgres — if detected
  if $has_postgres; then
    local db_dsn="postgresql://user:pass@localhost:5432/${DETECTED[project_name]}"
    cat >> "$mcp_file" << MCPEOF
    ,"postgres": {
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub", "--dsn", "$db_dsn"],
      "timeout": 10000
    }
MCPEOF
    server_count=$((server_count + 1))
  fi

  # Frontend MCPs — only add what the user actually has
  if $has_frontend; then
    # Playwright — E2E browser automation (npx, no account needed)
    cat >> "$mcp_file" << 'MCPEOF'
    ,"playwright": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-playwright@latest"]
    }
MCPEOF
    server_count=$((server_count + 1))

    # Figma — only if FIGMA_ACCESS_TOKEN is set
    if [ -n "${FIGMA_ACCESS_TOKEN:-}" ]; then
      cat >> "$mcp_file" << 'MCPEOF'
    ,"figma": {
      "type": "http",
      "url": "https://mcp.figma.com/mcp"
    }
MCPEOF
      server_count=$((server_count + 1))
    fi

    # Stitch — only if stitch-mcp is installed
    if npx --dry-run stitch-mcp &>/dev/null 2>&1; then
      cat >> "$mcp_file" << 'MCPEOF'
    ,"stitch": {
      "command": "npx",
      "args": ["-y", "stitch-mcp"]
    }
MCPEOF
      server_count=$((server_count + 1))
    fi
  fi

  echo '  }' >> "$mcp_file"
  echo '}' >> "$mcp_file"

  log_dim "  .mcp.json ($server_count servers)"
}

render_brain_md() {
  local project_dir="$1"
  render_placeholders "$TASUKI_TEMPLATES/TASUKI.md" "$project_dir/TASUKI.md"
  log_dim "  TASUKI.md"
}

render_protected_files() {
  local claude_dir="$1"
  local pf="$claude_dir/config/protected-files.txt"

  cat > "$pf" << 'EOF'
.env
.env.*
secrets/
credentials
.git/
node_modules/
EOF

  # Stack-specific entries
  case "${DETECTED[backend_lang]}" in
    python)
      echo "__pycache__/" >> "$pf"
      echo "*.pyc" >> "$pf"
      ;;
    javascript|typescript)
      echo "package-lock.json" >> "$pf"
      echo "pnpm-lock.yaml" >> "$pf"
      echo "yarn.lock" >> "$pf"
      ;;
    ruby)
      echo "Gemfile.lock" >> "$pf"
      ;;
    go)
      echo "go.sum" >> "$pf"
      ;;
    rust)
      echo "Cargo.lock" >> "$pf"
      ;;
  esac

  log_dim "  protected-files.txt"
}
