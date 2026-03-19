#!/bin/bash
# Tasuki Engine — Profile Matching
# Matches detected stack against available profiles.
# Usage: source this file, then call match_profile (requires DETECTED array from detect.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Global: matched profile path
MATCHED_PROFILE=""

# Global: conventions extracted from profile (multi-line strings)
declare -A CONVENTIONS

match_profile() {
  log_step "Phase 2a: ANALYZE — Matching profile"
  echo ""

  local lang="${DETECTED[backend_lang]:-unknown}"
  local framework="${DETECTED[backend_framework]:-unknown}"
  local fe_framework="${DETECTED[frontend_framework]:-none}"

  # Normalize framework names (detectors may append version/variant)
  case "$fe_framework" in
    sveltekit-5|sveltekit-4) fe_framework="sveltekit" ;;
    nextjs-app|nextjs-pages) fe_framework="nextjs" ;;
  esac

  # Try exact backend match: lang-framework.yaml
  local exact="$TASUKI_PROFILES/${lang}-${framework}.yaml"
  if [ -f "$exact" ]; then
    MATCHED_PROFILE="$exact"
    log_success "  Profile: ${lang}-${framework} (exact match)"

  # Try frontend framework match (for fullstack frameworks like Next.js, SvelteKit, Nuxt)
  elif [ "$fe_framework" != "none" ] && [ -f "$TASUKI_PROFILES/typescript-${fe_framework}.yaml" ]; then
    MATCHED_PROFILE="$TASUKI_PROFILES/typescript-${fe_framework}.yaml"
    log_success "  Profile: typescript-${fe_framework} (frontend framework match)"

  else
    # Try lang-only match: find any profile starting with lang
    local partial
    partial=$(find "$TASUKI_PROFILES" -name "${lang}-*.yaml" 2>/dev/null | head -1)
    if [ -n "$partial" ] && [ -f "$partial" ]; then
      MATCHED_PROFILE="$partial"
      log_success "  Profile: $(basename "$partial" .yaml) (partial match)"
    else
      # No match — ask user if interactive
      if [ -t 0 ]; then
        echo ""
        log_warn "  No specific profile found for $lang/$framework"
        echo ""
        echo -e "  ${BOLD}Options:${NC}"
        echo -e "    ${CYAN}1${NC}) Use generic profile (safe, universal conventions)"
        echo -e "    ${CYAN}2${NC}) Generate a custom profile for $lang/$framework (uses AI tokens)"
        echo -en "  ${BOLD}Choice${NC} (1/2, Enter=1): "
        read -r profile_choice

        if [ "$profile_choice" = "2" ]; then
          log_info "  To generate a custom profile, run your AI tool and ask:"
          log_dim "    \"Analyze this project and create a profile at .tasuki/config/custom-profile.yaml"
          log_dim "     following the format in src/profiles/python-fastapi.yaml\""
          echo ""
          log_info "  Using generic for now. Re-onboard after generating the custom profile."
        fi
      fi

      MATCHED_PROFILE="$TASUKI_PROFILES/generic.yaml"
      log_warn "  Profile: generic"
    fi
  fi

  log_dim "  File: $MATCHED_PROFILE"
  echo ""

  # Extract conventions from the matched profile
  extract_conventions
}

extract_conventions() {
  log_info "Extracting conventions from profile..."

  # Read convention sections from the profile YAML
  # Each section is a list of strings under conventions.{section}
  local sections=("routing" "models" "migrations" "testing" "docker" "frontend")

  for section in "${sections[@]}"; do
    local content=""
    content=$(extract_yaml_list "$MATCHED_PROFILE" "$section")
    if [ -n "$content" ]; then
      CONVENTIONS[$section]="$content"
    else
      CONVENTIONS[$section]="(No specific conventions defined)"
    fi
  done

  # Derive tools from detectors (not from profile — detectors are the source of truth)
  local backend_runner="${DETECTED[testing_backend_runner]:-none}"
  case "$backend_runner" in
    pytest)   CONVENTIONS[test_runner]="python3 -m pytest" ;;
    unittest) CONVENTIONS[test_runner]="python3 -m unittest discover" ;;
    jest)     CONVENTIONS[test_runner]="npx jest" ;;
    vitest)   CONVENTIONS[test_runner]="npx vitest" ;;
    mocha)    CONVENTIONS[test_runner]="npx mocha" ;;
    go-test)  CONVENTIONS[test_runner]="go test ./..." ;;
    rspec)    CONVENTIONS[test_runner]="bundle exec rspec" ;;
    junit)    CONVENTIONS[test_runner]="mvn test" ;;
    *)        CONVENTIONS[test_runner]="echo 'test runner not configured'" ;;
  esac

  local migration_tool="${DETECTED[database_migration_tool]:-none}"
  case "$migration_tool" in
    alembic)           CONVENTIONS[migration_cmd]="alembic" ;;
    django-migrations) CONVENTIONS[migration_cmd]="python3 manage.py migrate" ;;
    prisma-migrate)    CONVENTIONS[migration_cmd]="npx prisma migrate" ;;
    knex)              CONVENTIONS[migration_cmd]="npx knex migrate:latest" ;;
    rails-migrations)  CONVENTIONS[migration_cmd]="rails db:migrate" ;;
    golang-migrate)    CONVENTIONS[migration_cmd]="migrate" ;;
    *)                 CONVENTIONS[migration_cmd]="" ;;
  esac

  # Scanner/linter/formatter — detect from project config files
  local lang="${DETECTED[backend_lang]:-}"
  case "$lang" in
    python)
      CONVENTIONS[scanner]="bandit"
      CONVENTIONS[linter]="ruff"
      CONVENTIONS[formatter]="ruff format"
      ;;
    typescript|javascript)
      CONVENTIONS[scanner]=""
      CONVENTIONS[linter]="eslint"
      CONVENTIONS[formatter]="prettier"
      ;;
    go)
      CONVENTIONS[scanner]=""
      CONVENTIONS[linter]="golangci-lint"
      CONVENTIONS[formatter]="gofmt"
      ;;
    ruby)
      CONVENTIONS[scanner]="brakeman"
      CONVENTIONS[linter]="rubocop"
      CONVENTIONS[formatter]="rubocop -A"
      ;;
    java)
      CONVENTIONS[scanner]="spotbugs"
      CONVENTIONS[linter]="checkstyle"
      CONVENTIONS[formatter]=""
      ;;
    php)
      CONVENTIONS[scanner]="phpstan"
      CONVENTIONS[linter]="phpcs"
      CONVENTIONS[formatter]="php-cs-fixer"
      ;;
    bash)
      CONVENTIONS[scanner]="shellcheck"
      CONVENTIONS[linter]="shellcheck"
      CONVENTIONS[formatter]=""
      ;;
    *)
      CONVENTIONS[scanner]=""
      CONVENTIONS[linter]=""
      CONVENTIONS[formatter]=""
      ;;
  esac

  log_success "  Extracted conventions for: ${!CONVENTIONS[*]}"
  echo ""
}

# Extract a list section from YAML as formatted bullet points
extract_yaml_list() {
  local file="$1" section="$2"
  local in_section=false
  local result=""

  while IFS= read -r line; do
    # Check if we hit our section header
    if echo "$line" | grep -qE "^\s+${section}:"; then
      in_section=true
      continue
    fi

    if $in_section; then
      # Check if this is a list item (starts with -)
      if echo "$line" | grep -qE '^\s+-\s'; then
        local item
        item=$(echo "$line" | sed 's/^\s*-\s*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
        if [ -n "$result" ]; then
          result="${result}
- ${item}"
        else
          result="- ${item}"
        fi
      # Check if we've left the section (non-list, non-empty, non-comment line at same or lower indent)
      elif echo "$line" | grep -qE '^[[:space:]]{0,4}[a-zA-Z_]'; then
        break
      fi
    fi
  done < "$file"

  echo "$result"
}

# Extract a simple value from YAML
extract_yaml_value() {
  local file="$1" key="$2"
  grep -E "^\s+${key}:" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" | tr -d '"'
}

# Determine which agents should be active based on detection results
determine_active_agents() {
  log_step "Phase 2b: ANALYZE — Determining active agents"
  echo ""

  # Always active
  ACTIVE_AGENTS=("planner" "qa" "security" "reviewer")
  SKIPPED_AGENTS=()

  # Conditional on backend
  if [ "${DETECTED[backend_detected]}" = "true" ]; then
    ACTIVE_AGENTS+=("backend-dev")
    log_success "  backend-dev: ACTIVE (${DETECTED[backend_framework]} detected)"
  else
    SKIPPED_AGENTS+=("backend-dev")
    log_dim "  backend-dev: SKIPPED (no backend detected)"
  fi

  # Conditional on frontend
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    ACTIVE_AGENTS+=("frontend-dev")
    log_success "  frontend-dev: ACTIVE (${DETECTED[frontend_framework]} detected)"
  else
    SKIPPED_AGENTS+=("frontend-dev")
    log_dim "  frontend-dev: SKIPPED (no frontend detected)"
  fi

  # Conditional on database
  if [ "${DETECTED[database_detected]}" = "true" ]; then
    ACTIVE_AGENTS+=("db-architect")
    log_success "  db-architect: ACTIVE (${DETECTED[database_engine]} detected)"
  else
    SKIPPED_AGENTS+=("db-architect")
    log_dim "  db-architect: SKIPPED (no database detected)"
  fi

  # DevOps: active unless user explicitly chose manual deploy
  local deploy_target="${DETECTED[infra_deploy_target]:-auto}"
  if [ "$deploy_target" = "manual" ] && [ "${DETECTED[infra_detected]}" != "true" ]; then
    SKIPPED_AGENTS+=("devops")
    log_dim "  devops: SKIPPED (deploy target: manual, no infra detected)"
  else
    ACTIVE_AGENTS+=("devops")
    if [ "${DETECTED[infra_detected]}" = "true" ]; then
      log_success "  devops: ACTIVE (${DETECTED[infra_containerization]:-infra} detected)"
    else
      log_success "  devops: ACTIVE (CI/CD, deployment, infrastructure)"
    fi
  fi

  # Debugger is always available but reactive
  ACTIVE_AGENTS+=("debugger")
  log_dim "  debugger: REACTIVE (activated on failure)"

  # Always active agents
  log_success "  planner: ACTIVE (always)"
  log_success "  qa: ACTIVE (always)"
  log_success "  security: ACTIVE (always)"
  log_success "  reviewer: ACTIVE (always)"

  echo ""
  log_info "Active agents: ${#ACTIVE_AGENTS[@]}/10"
  echo ""
}
