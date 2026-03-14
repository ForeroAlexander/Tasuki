#!/bin/bash
# Tasuki Engine — Onboard Interview
# Interactive questions during onboard to enrich project context.
# Answers go into .tasuki/config/project-context.md
# The planner reads this to understand the business, not just the stack.
#
# Usage: source this file, then call run_interview /path/to/project
# All questions are skippable (Enter = skip)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set +u
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

run_interview() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local output="$project_dir/.tasuki/config/project-context.md"
  mkdir -p "$(dirname "$output")"

  echo ""
  echo -e "${BOLD}Tasuki — Project Context${NC}"
  echo -e "${DIM}Quick questions to help agents understand your project better.${NC}"
  echo -e "${DIM}Press Enter to skip any question.${NC}"
  echo ""

  local project_name
  project_name=$(basename "$project_dir")
  local date
  date=$(date '+%Y-%m-%d')

  # Collect answers
  local business="" domain="" users="" auth_model="" multi_tenant=""
  local deploy_target="" branch_strategy="" conventions="" correct_stack="" custom_rules=""

  # --- Business Context ---
  echo -e "${BOLD}Business:${NC}"

  echo -en "  What does this project do? (1 sentence): "
  read -r business

  echo -en "  Industry/domain (e.g., e-commerce, healthcare, fintech, SaaS): "
  read -r domain

  echo -en "  Who are the users? (e.g., internal team, B2B clients, consumers): "
  read -r users

  # --- Confirm Detection ---
  echo ""
  echo -e "${BOLD}Stack confirmation:${NC}"

  # Show what we detected from DETECTED array
  echo -e "  ${DIM}Auto-detected:${NC}"
  # Backend
  if [ "${DETECTED[backend_detected]:-}" = "true" ]; then
    local be_info="${DETECTED[backend_framework]^}"
    [ -n "${DETECTED[backend_framework_version]:-}" ] && be_info="$be_info ${DETECTED[backend_framework_version]}"
    be_info="$be_info (${DETECTED[backend_lang]}"
    [ -n "${DETECTED[backend_lang_version]:-}" ] && be_info="$be_info ${DETECTED[backend_lang_version]}"
    be_info="$be_info)"
    [ -n "${DETECTED[backend_path]:-}" ] && be_info="$be_info at ${DETECTED[backend_path]}/"
    echo -e "    ${GREEN}- Backend: $be_info${NC}"
    echo -e "    ${DIM}  ${DETECTED[backend_counts_routers]:-0} routers, ${DETECTED[backend_counts_models]:-0} models, ${DETECTED[backend_counts_services]:-0} services${NC}"
  fi
  # Frontend
  if [ "${DETECTED[frontend_detected]:-}" = "true" ]; then
    local fe_info="${DETECTED[frontend_framework]^}"
    [ -n "${DETECTED[frontend_version]:-}" ] && fe_info="$fe_info ${DETECTED[frontend_version]}"
    [ -n "${DETECTED[frontend_lang]:-}" ] && fe_info="$fe_info (${DETECTED[frontend_lang]})"
    [ -n "${DETECTED[frontend_path]:-}" ] && fe_info="$fe_info at ${DETECTED[frontend_path]}/"
    echo -e "    ${GREEN}- Frontend: $fe_info${NC}"
    local fe_extras=""
    [ -n "${DETECTED[frontend_styling]:-}" ] && fe_extras="${DETECTED[frontend_styling]}"
    [ -n "${DETECTED[frontend_state]:-}" ] && fe_extras="$fe_extras + ${DETECTED[frontend_state]}"
    [ -n "${DETECTED[frontend_components_lib]:-}" ] && fe_extras="$fe_extras + ${DETECTED[frontend_components_lib]}"
    [ -n "$fe_extras" ] && echo -e "    ${DIM}  $fe_extras${NC}"
    echo -e "    ${DIM}  ${DETECTED[frontend_counts_pages]:-0} pages, ${DETECTED[frontend_counts_components]:-0} components${NC}"
  fi
  # Database
  [ "${DETECTED[database_engine]:-}" != "" ] && echo -e "    ${GREEN}- Database: ${DETECTED[database_engine]^} + ${DETECTED[database_orm]:-no ORM}${NC}"
  [ "${DETECTED[database_migration_tool]:-}" != "" ] && echo -e "    ${DIM}  Migrations: ${DETECTED[database_migration_tool]}${NC}"
  # Infra
  [ -f "$project_dir/Dockerfile" ] || find "$project_dir" -maxdepth 2 -name "Dockerfile" 2>/dev/null | head -1 | grep -q . && echo -e "    ${GREEN}- Docker (detected)${NC}"
  [ -f "$project_dir/docker-compose.yml" ] || [ -f "$project_dir/docker-compose.yaml" ] || find "$project_dir" -maxdepth 2 -name "docker-compose*" 2>/dev/null | head -1 | grep -q . && echo -e "    ${GREEN}- docker-compose (detected)${NC}"
  [ "${DETECTED[infra_ci_cd]:-}" != "" ] && [ "${DETECTED[infra_ci_cd]:-}" != "none" ] && echo -e "    ${GREEN}- CI/CD: ${DETECTED[infra_ci_cd]}${NC}"
  # Testing
  [ "${DETECTED[testing_backend_runner]:-}" != "" ] && [ "${DETECTED[testing_backend_runner]:-}" != "none" ] && echo -e "    ${GREEN}- Testing: ${DETECTED[testing_backend_runner]}${NC}"
  # Package manager
  local pkg_mgr="${DETECTED[backend_package_manager]:-}"
  [ -z "$pkg_mgr" ] && pkg_mgr="${DETECTED[frontend_package_manager]:-}"
  [ -n "$pkg_mgr" ] && echo -e "    ${GREEN}- Package manager: $pkg_mgr${NC}"
  echo ""

  # --- Ask only about what's MISSING ---
  local has_gaps=false

  if [ "${DETECTED[backend_detected]:-}" != "true" ]; then
    has_gaps=true
    echo -e "    ${YELLOW}✗ Backend: not detected${NC}"
    echo -en "    ${DIM}Do you have a backend? Framework + path (e.g., FastAPI at app/backend/) or Enter to skip: ${NC}"
    read -r manual_backend
    [ -n "$manual_backend" ] && correct_stack="${correct_stack:-} Backend: $manual_backend"
  fi

  if [ "${DETECTED[frontend_detected]:-}" != "true" ]; then
    has_gaps=true
    echo -e "    ${YELLOW}✗ Frontend: not detected${NC}"
    echo -en "    ${DIM}Do you have a frontend? Framework + path (e.g., SvelteKit at app/frontend/) or Enter to skip: ${NC}"
    read -r manual_frontend
    [ -n "$manual_frontend" ] && correct_stack="${correct_stack:-} Frontend: $manual_frontend"
  fi

  if [ "${DETECTED[database_detected]:-}" != "true" ]; then
    has_gaps=true
    echo -e "    ${YELLOW}✗ Database: not detected${NC}"
    echo -en "    ${DIM}Database engine? (postgresql, mysql, mongodb, sqlite, none): ${NC}"
    read -r manual_db
    [ -n "$manual_db" ] && correct_stack="${correct_stack:-} Database: $manual_db"
  fi

  if [ "${DETECTED[testing_backend_runner]:-}" = "" ] || [ "${DETECTED[testing_backend_runner]:-}" = "none" ]; then
    has_gaps=true
    echo -e "    ${YELLOW}✗ Testing: not detected${NC}"
    echo -en "    ${DIM}Test runner? (pytest, jest, vitest, go test, none) or Enter to skip: ${NC}"
    read -r manual_testing
  fi

  echo ""

  if [ "$has_gaps" = false ]; then
    echo -en "  Is this correct? (y/n, Enter=yes): "
    read -r stack_correct
    stack_correct="${stack_correct:-y}"
    if [ "$stack_correct" = "n" ] || [ "$stack_correct" = "N" ]; then
      echo -en "  What should be corrected? "
      read -r correct_stack
    fi
  else
    echo -en "  Anything else to add or correct? (Enter to continue): "
    read -r extra_stack
    [ -n "$extra_stack" ] && correct_stack="${correct_stack:-} $extra_stack"
  fi

  # --- Architecture ---
  echo ""
  echo -e "${BOLD}Architecture:${NC}"

  # Only ask auth if not already detected
  local auth_model=""
  if [ "${DETECTED[backend_auth_pattern]:-unknown}" = "unknown" ]; then
    echo -en "  Auth model (jwt, session, oauth, none): "
    read -r auth_model
  else
    auth_model="${DETECTED[backend_auth_pattern]}"
    echo -e "  Auth model: ${GREEN}${auth_model} (detected)${NC}"
  fi

  local multi_tenant=""
  if [ "${DETECTED[database_multi_tenant]:-none}" != "none" ] && [ -n "${DETECTED[database_multi_tenant]:-}" ]; then
    multi_tenant="yes"
    echo -e "  Multi-tenant: ${GREEN}yes — ${DETECTED[database_multi_tenant]} (detected)${NC}"
  else
    echo -en "  Multi-tenant? (yes/no): "
    read -r multi_tenant
  fi

  local deploy_target=""
  if [ "${DETECTED[infra_deploy_target]:-unknown}" != "unknown" ] && [ -n "${DETECTED[infra_deploy_target]:-}" ]; then
    deploy_target="${DETECTED[infra_deploy_target]}"
    echo -e "  Deploy target: ${GREEN}${deploy_target} (detected)${NC}"
  else
    echo -en "  Deploy target (vercel, aws, docker, railway, fly, manual): "
    read -r deploy_target
  fi

  # --- Team Conventions ---
  echo ""
  echo -e "${BOLD}Conventions:${NC}"

  echo -en "  Branch strategy (gitflow, trunk, feature-branch): "
  read -r branch_strategy

  echo -en "  Commit format (conventional, freeform): "
  read -r conventions

  echo -en "  Any specific rules agents should follow? (Enter=none): "
  read -r custom_rules

  # --- Write context file ---
  {
    echo "# Project Context — $project_name"
    echo "# Answers from onboard interview. Agents read this to understand the business."
    echo "# Updated: $date"
    echo ""

    if [ -n "$business" ]; then
      echo "## What This Project Does"
      echo "$business"
      echo ""
    fi

    if [ -n "$domain" ]; then
      echo "## Domain"
      echo "$domain"
      echo ""
    fi

    if [ -n "$users" ]; then
      echo "## Users"
      echo "$users"
      echo ""
    fi

    if [ -n "$correct_stack" ]; then
      echo "## Stack (corrected by user)"
      echo "$correct_stack"
      echo ""
    fi

    if [ -n "$auth_model" ]; then
      echo "## Auth Model"
      echo "$auth_model"
      echo ""
    fi

    if [ -n "$multi_tenant" ]; then
      echo "## Multi-Tenant"
      echo "$multi_tenant"
      echo ""
    fi

    if [ -n "$deploy_target" ]; then
      echo "## Deploy Target"
      echo "$deploy_target"
      echo ""
    fi

    if [ -n "$branch_strategy" ]; then
      echo "## Branch Strategy"
      echo "$branch_strategy"
      echo ""
    fi

    if [ -n "$conventions" ]; then
      echo "## Commit Format"
      echo "$conventions"
      echo ""
    fi

    if [ -n "$custom_rules" ]; then
      echo "## Custom Rules"
      echo "$custom_rules"
      echo ""
    fi

  } > "$output"

  # Check if any answers were given
  local answers=0
  [ -n "$business" ] && answers=$((answers + 1))
  [ -n "$domain" ] && answers=$((answers + 1))
  [ -n "$users" ] && answers=$((answers + 1))
  [ -n "$auth_model" ] && answers=$((answers + 1))
  [ -n "$deploy_target" ] && answers=$((answers + 1))

  # Generate agent-specific directives from answers
  if [ "$answers" -gt 0 ]; then
    {
      echo ""
      echo "## Agent Directives (auto-generated from your answers)"
      echo ""

      # Domain-specific security rules
      if [ -n "$domain" ]; then
        local domain_lower
        domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        case "$domain_lower" in
          *fintech*|*finance*|*banking*|*payment*)
            echo "### Security Agent"
            echo "- CRITICAL: This is a fintech project. Check for PCI-DSS compliance patterns."
            echo "- Verify encryption at rest for sensitive financial data (amounts, account numbers)."
            echo "- Audit all monetary calculations for floating point errors (use Decimal, not float)."
            echo "- Check rate limiting on all financial endpoints."
            echo ""
            echo "### QA Agent"
            echo "- Write edge case tests for monetary calculations (rounding, overflow, negative amounts)."
            echo "- Test concurrent transaction scenarios."
            echo ""
            ;;
          *health*|*medical*|*clinic*)
            echo "### Security Agent"
            echo "- CRITICAL: Healthcare project. Check for HIPAA compliance patterns."
            echo "- All patient data must be encrypted at rest and in transit."
            echo "- Audit access logging for all patient record endpoints."
            echo ""
            ;;
          *ecommerce*|*e-commerce*|*shop*|*store*|*retail*)
            echo "### Security Agent"
            echo "- Check payment processing for injection vulnerabilities."
            echo "- Verify inventory operations are atomic (no overselling)."
            echo ""
            echo "### QA Agent"
            echo "- Test cart edge cases: empty cart checkout, expired items, concurrent purchases."
            echo ""
            ;;
          *social*|*community*|*forum*)
            echo "### Security Agent"
            echo "- CRITICAL: User-generated content. Check for XSS in all input rendering."
            echo "- Rate limit content creation endpoints."
            echo ""
            ;;
        esac
      fi

      # Auth-specific directives
      if [ -n "$auth_model" ]; then
        local auth_lower
        auth_lower=$(echo "$auth_model" | tr '[:upper:]' '[:lower:]')
        case "$auth_lower" in
          *jwt*)
            echo "### Backend Dev Agent"
            echo "- Use short-lived access tokens (15min) + refresh tokens."
            echo "- Never store sensitive data in JWT payload (it's base64, not encrypted)."
            echo ""
            echo "### QA Agent"
            echo "- Write tests for: expired token, malformed token, missing token, refresh flow."
            echo "- Test token blacklisting on logout."
            echo ""
            ;;
          *session*)
            echo "### Backend Dev Agent"
            echo "- Use secure, httpOnly, sameSite cookies for session IDs."
            echo "- Implement session expiry and rotation."
            echo ""
            ;;
          *oauth*)
            echo "### Backend Dev Agent"
            echo "- Validate OAuth state parameter to prevent CSRF."
            echo "- Store tokens securely, never in localStorage."
            echo ""
            ;;
        esac
      fi

      # Deploy-specific directives
      if [ -n "$deploy_target" ]; then
        local deploy_lower
        deploy_lower=$(echo "$deploy_target" | tr '[:upper:]' '[:lower:]')
        case "$deploy_lower" in
          *docker*)
            echo "### DevOps Agent"
            echo "- Multi-stage Dockerfile for smaller images."
            echo "- Non-root user in container."
            echo "- Health check endpoint required."
            echo ""
            ;;
          *vercel*|*netlify*)
            echo "### DevOps Agent"
            echo "- Serverless deployment. Check for cold start optimizations."
            echo "- Environment variables via platform dashboard, not .env files."
            echo ""
            ;;
          *aws*)
            echo "### DevOps Agent"
            echo "- Use IAM roles, not access keys."
            echo "- Check for S3 bucket policies and CloudFront settings."
            echo ""
            ;;
        esac
      fi

      # Multi-tenant directives
      if [ "$multi_tenant" = "yes" ] || [ "$multi_tenant" = "y" ]; then
        echo "### DB Architect Agent"
        echo "- CRITICAL: Multi-tenant project. Every query MUST filter by tenant_id."
        echo "- Use RLS (Row Level Security) in PostgreSQL for tenant isolation."
        echo "- Never allow cross-tenant data leaks in joins or subqueries."
        echo ""
        echo "### Security Agent"
        echo "- Audit every endpoint for tenant isolation. Test: can tenant A access tenant B's data?"
        echo ""
      fi

      # Branch strategy
      if [ -n "$branch_strategy" ]; then
        echo "### Reviewer Agent"
        echo "- Branch strategy: $branch_strategy. Verify PR targets the correct base branch."
        echo ""
      fi

    } >> "$output"
  fi

  if [ "$answers" -gt 0 ]; then
    echo ""
    log_success "Project context saved ($answers answers)"
    log_dim "  File: $output"
    log_dim "  Agents will read this to understand your project's business logic."
  else
    echo ""
    log_dim "  No answers provided. Agents will work with auto-detected context only."
    rm -f "$output"  # Don't save empty file
  fi
  echo ""
}

# If run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_interview "$@"
fi
