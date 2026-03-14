#!/bin/bash
# Tasuki Engine — Stack Detection Orchestrator
# Runs all 5 detectors against a project and stores results.
# Usage: source this file, then call run_detection /path/to/project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Global detection results (raw JSON strings)
DETECT_BACKEND=""
DETECT_FRONTEND=""
DETECT_DATABASE=""
DETECT_INFRA=""
DETECT_TESTING=""

# Parsed detection summary
declare -A DETECTED

run_detection() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  log_step "Phase 1: SCAN — Detecting stack"
  log_dim "Project: $project_dir"
  echo ""

  # Run all 5 detectors
  log_info "Running backend detector..."
  DETECT_BACKEND=$(bash "$TASUKI_DETECTORS/detect-backend.sh" "$project_dir" 2>/dev/null || echo '{"detected":false}')

  log_info "Running frontend detector..."
  DETECT_FRONTEND=$(bash "$TASUKI_DETECTORS/detect-frontend.sh" "$project_dir" 2>/dev/null || echo '{"detected":false}')

  log_info "Running database detector..."
  DETECT_DATABASE=$(bash "$TASUKI_DETECTORS/detect-database.sh" "$project_dir" 2>/dev/null || echo '{"detected":false}')

  log_info "Running infra detector..."
  DETECT_INFRA=$(bash "$TASUKI_DETECTORS/detect-infra.sh" "$project_dir" 2>/dev/null || echo '{"detected":false}')

  log_info "Running testing detector..."
  DETECT_TESTING=$(bash "$TASUKI_DETECTORS/detect-testing.sh" "$project_dir" 2>/dev/null || echo '{"detected":false}')

  echo ""

  # Parse results into DETECTED associative array
  parse_detection_results "$project_dir"

  # Print summary
  print_detection_summary
}

parse_detection_results() {
  local project_dir="$1"

  # Backend
  DETECTED[backend_detected]=$(json_bool "$DETECT_BACKEND" "detected")
  DETECTED[backend_lang]=$(json_get "$DETECT_BACKEND" "lang")
  DETECTED[backend_lang_version]=$(json_get "$DETECT_BACKEND" "lang_version")
  DETECTED[backend_framework]=$(json_get "$DETECT_BACKEND" "framework")
  DETECTED[backend_framework_version]=$(json_get "$DETECT_BACKEND" "framework_version")
  DETECTED[backend_path]=$(json_get "$DETECT_BACKEND" "path")
  DETECTED[backend_entry]=$(json_get "$DETECT_BACKEND" "entry")
  DETECTED[backend_package_manager]=$(json_get "$DETECT_BACKEND" "package_manager")
  DETECTED[backend_auth_pattern]=$(json_get "$DETECT_BACKEND" "auth_pattern")
  DETECTED[backend_api_style]=$(json_get "$DETECT_BACKEND" "api_style")
  DETECTED[backend_counts_routers]=$(json_get "$DETECT_BACKEND" "routers")
  DETECTED[backend_counts_models]=$(json_get "$DETECT_BACKEND" "models")
  DETECTED[backend_counts_services]=$(json_get "$DETECT_BACKEND" "services")

  # Frontend
  DETECTED[frontend_detected]=$(json_bool "$DETECT_FRONTEND" "detected")
  DETECTED[frontend_framework]=$(json_get "$DETECT_FRONTEND" "framework")
  DETECTED[frontend_lang]=$(json_get "$DETECT_FRONTEND" "lang")
  DETECTED[frontend_path]=$(json_get "$DETECT_FRONTEND" "path")
  DETECTED[frontend_version]=$(json_get "$DETECT_FRONTEND" "version")
  DETECTED[frontend_styling]=$(json_get "$DETECT_FRONTEND" "styling")
  DETECTED[frontend_state]=$(json_get "$DETECT_FRONTEND" "state")
  DETECTED[frontend_components_lib]=$(json_get "$DETECT_FRONTEND" "components_lib")
  DETECTED[frontend_package_manager]=$(json_get "$DETECT_FRONTEND" "package_manager")
  DETECTED[frontend_counts_pages]=$(json_get "$DETECT_FRONTEND" "pages")
  DETECTED[frontend_counts_components]=$(json_get "$DETECT_FRONTEND" "components")

  # Database
  DETECTED[database_detected]=$(json_bool "$DETECT_DATABASE" "detected")
  DETECTED[database_engine]=$(json_get "$DETECT_DATABASE" "engine")
  DETECTED[database_orm]=$(json_get "$DETECT_DATABASE" "orm")
  DETECTED[database_migration_tool]=$(json_get "$DETECT_DATABASE" "migration_tool")
  DETECTED[database_multi_tenant]=$(json_get "$DETECT_DATABASE" "multi_tenant")

  # Infra
  DETECTED[infra_detected]=$(json_bool "$DETECT_INFRA" "detected")
  DETECTED[infra_containerization]=$(json_get "$DETECT_INFRA" "containerization")
  DETECTED[infra_ci_cd]=$(json_get "$DETECT_INFRA" "ci_cd")
  DETECTED[infra_reverse_proxy]=$(json_get "$DETECT_INFRA" "reverse_proxy")
  DETECTED[infra_deploy_target]=$(json_get "$DETECT_INFRA" "deploy_target")
  DETECTED[infra_services]=$(json_get "$DETECT_INFRA" "services")

  # Testing
  DETECTED[testing_detected]=$(json_bool "$DETECT_TESTING" "detected")
  DETECTED[testing_backend_runner]=$(json_get "$DETECT_TESTING" "backend_test")
  DETECTED[testing_frontend_runner]=$(json_get "$DETECT_TESTING" "frontend_test")
  DETECTED[testing_e2e]=$(json_get "$DETECT_TESTING" "e2e")

  # Derive paths
  DETECTED[project_dir]="$project_dir"
  DETECTED[project_name]=$(basename "$project_dir")

  # Backend path: directory containing the entry file, or "app" / "src" fallback
  if [ -n "${DETECTED[backend_entry]}" ] && [ -f "${DETECTED[backend_entry]}" ]; then
    DETECTED[backend_path]=$(dirname "${DETECTED[backend_entry]}")
  elif [ -d "$project_dir/app" ]; then
    DETECTED[backend_path]="app"
  elif [ -d "$project_dir/src" ]; then
    DETECTED[backend_path]="src"
  else
    DETECTED[backend_path]="."
  fi

  # Frontend path
  if [ -d "$project_dir/frontend" ]; then
    DETECTED[frontend_path]="frontend"
  elif [ -d "$project_dir/client" ]; then
    DETECTED[frontend_path]="client"
  elif [ -d "$project_dir/web" ]; then
    DETECTED[frontend_path]="web"
  elif [ -d "$project_dir/src" ] && [ "${DETECTED[frontend_detected]}" = "true" ]; then
    DETECTED[frontend_path]="src"
  else
    DETECTED[frontend_path]="frontend"
  fi

  # Models path
  if [ -d "$project_dir/app/models" ]; then
    DETECTED[models_path]="app/models"
  elif [ -d "$project_dir/src/models" ]; then
    DETECTED[models_path]="src/models"
  elif [ -d "$project_dir/models" ]; then
    DETECTED[models_path]="models"
  else
    DETECTED[models_path]="${DETECTED[backend_path]}/models"
  fi

  # Migrations path
  if [ -d "$project_dir/alembic" ]; then
    DETECTED[migrations_path]="alembic"
  elif [ -d "$project_dir/migrations" ]; then
    DETECTED[migrations_path]="migrations"
  elif [ -d "$project_dir/db/migrate" ]; then
    DETECTED[migrations_path]="db/migrate"
  elif [ -d "$project_dir/prisma/migrations" ]; then
    DETECTED[migrations_path]="prisma/migrations"
  else
    DETECTED[migrations_path]="migrations"
  fi

  # Test path
  if [ -d "$project_dir/tests" ]; then
    DETECTED[test_path]="tests"
  elif [ -d "$project_dir/test" ]; then
    DETECTED[test_path]="test"
  elif [ -d "$project_dir/spec" ]; then
    DETECTED[test_path]="spec"
  elif [ -d "$project_dir/__tests__" ]; then
    DETECTED[test_path]="__tests__"
  else
    DETECTED[test_path]="tests"
  fi

  # Docker compose path
  if [ -f "$project_dir/docker-compose.yml" ]; then
    DETECTED[docker_compose_path]="docker-compose.yml"
  elif [ -f "$project_dir/docker-compose.yaml" ]; then
    DETECTED[docker_compose_path]="docker-compose.yaml"
  elif [ -f "$project_dir/compose.yml" ]; then
    DETECTED[docker_compose_path]="compose.yml"
  elif [ -f "$project_dir/compose.yaml" ]; then
    DETECTED[docker_compose_path]="compose.yaml"
  else
    DETECTED[docker_compose_path]="docker-compose.yml"
  fi

  # CI/CD config path
  if [ -d "$project_dir/.github/workflows" ]; then
    DETECTED[ci_cd_config_path]=".github/workflows"
  elif [ -f "$project_dir/.gitlab-ci.yml" ]; then
    DETECTED[ci_cd_config_path]=".gitlab-ci.yml"
  else
    DETECTED[ci_cd_config_path]=".github/workflows"
  fi

  # Run command
  case "${DETECTED[backend_lang]}" in
    python) DETECTED[run_cmd]="python3" ;;
    javascript|typescript) DETECTED[run_cmd]="npm run dev" ;;
    go) DETECTED[run_cmd]="go run ." ;;
    ruby) DETECTED[run_cmd]="bundle exec rails s" ;;
    java) DETECTED[run_cmd]="./mvnw spring-boot:run" ;;
    rust) DETECTED[run_cmd]="cargo run" ;;
    *) DETECTED[run_cmd]="echo 'run command not configured'" ;;
  esac
}

print_detection_summary() {
  log_step "Detection Results"
  echo ""

  # Backend
  if [ "${DETECTED[backend_detected]}" = "true" ]; then
    local be_ver="${DETECTED[backend_framework_version]:-}"
    local be_pyver="${DETECTED[backend_lang_version]:-}"
    local be_path="${DETECTED[backend_path]:-}"
    local be_label="${DETECTED[backend_framework]} (${DETECTED[backend_lang]}${be_pyver:+ $be_pyver})"
    [ -n "$be_ver" ] && be_label="${DETECTED[backend_framework]} $be_ver (${DETECTED[backend_lang]}${be_pyver:+ $be_pyver})"
    log_success "  Backend:  $be_label"
    [ -n "$be_path" ] && log_dim "            Path: $be_path/"
    log_dim "            Entry: ${DETECTED[backend_entry]:-not found}"
    log_dim "            Auth: ${DETECTED[backend_auth_pattern]:-unknown}  API: ${DETECTED[backend_api_style]:-unknown}"
    log_dim "            ${DETECTED[backend_counts_routers]:-0} routers, ${DETECTED[backend_counts_models]:-0} models, ${DETECTED[backend_counts_services]:-0} services"
  else
    log_warn "  Backend:  not detected"
  fi

  # Frontend
  if [ "${DETECTED[frontend_detected]}" = "true" ]; then
    local fe_ver="${DETECTED[frontend_version]:-}"
    local fe_path="${DETECTED[frontend_path]:-}"
    local fe_label="${DETECTED[frontend_framework]}${fe_ver:+ $fe_ver} (${DETECTED[frontend_lang]:-unknown})"
    log_success "  Frontend: $fe_label"
    [ -n "$fe_path" ] && log_dim "            Path: $fe_path/"
    log_dim "            Styling: ${DETECTED[frontend_styling]:-unknown}  State: ${DETECTED[frontend_state]:-unknown}"
    [ -n "${DETECTED[frontend_components_lib]:-}" ] && log_dim "            Components: ${DETECTED[frontend_components_lib]}"
    log_dim "            ${DETECTED[frontend_counts_pages]:-0} pages, ${DETECTED[frontend_counts_components]:-0} components"
  else
    log_warn "  Frontend: not detected"
  fi

  # Database
  if [ "${DETECTED[database_detected]}" = "true" ]; then
    log_success "  Database: ${DETECTED[database_engine]} + ${DETECTED[database_orm]:-no ORM}"
    log_dim "            Migrations: ${DETECTED[database_migration_tool]:-unknown}  Multi-tenant: ${DETECTED[database_multi_tenant]:-none}"
  else
    log_warn "  Database: not detected"
  fi

  # Infra
  if [ "${DETECTED[infra_detected]}" = "true" ]; then
    log_success "  Infra:    ${DETECTED[infra_containerization]:-none}"
    log_dim "            CI/CD: ${DETECTED[infra_ci_cd]:-unknown}  Deploy: ${DETECTED[infra_deploy_target]:-unknown}"
    [ -n "${DETECTED[infra_reverse_proxy]:-}" ] && [ "${DETECTED[infra_reverse_proxy]}" != "none" ] && log_dim "            Proxy: ${DETECTED[infra_reverse_proxy]}"
    if [ -n "${DETECTED[infra_services]:-}" ] && [ "${DETECTED[infra_services]}" != "none" ]; then
      log_dim "            Services: ${DETECTED[infra_services]//,/, }"
    fi
  else
    log_warn "  Infra:    not detected"
  fi

  # Testing
  if [ "${DETECTED[testing_detected]}" = "true" ]; then
    log_success "  Testing:  ${DETECTED[testing_backend_runner]:-none} + ${DETECTED[testing_frontend_runner]:-none}"
    log_dim "            E2E: ${DETECTED[testing_e2e]:-none}"
  else
    log_warn "  Testing:  not detected"
  fi

  echo ""
}
