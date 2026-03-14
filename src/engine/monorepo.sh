#!/bin/bash
# Tasuki Engine — Monorepo Support
# Detects multiple services in a single repository and shows the structure.
# Usage: bash monorepo.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

detect_monorepo() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  echo ""
  echo -e "${BOLD}Tasuki Monorepo Detection${NC}"
  echo -e "${DIM}═════════════════════════${NC}"
  echo ""

  local services=()
  local service_paths=()
  local service_types=()

  # Pattern 1: services/ or apps/ directory
  for parent in services apps packages microservices; do
    if [ -d "$project_dir/$parent" ]; then
      for dir in "$project_dir/$parent"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        local type
        type=$(detect_service_type "$dir")
        if [ "$type" != "unknown" ]; then
          services+=("$name")
          service_paths+=("$parent/$name")
          service_types+=("$type")
        fi
      done
    fi
  done

  # Pattern 2: top-level backend/ + frontend/ split
  if [ -d "$project_dir/backend" ] && detect_service_type "$project_dir/backend" &>/dev/null; then
    services+=("backend")
    service_paths+=("backend")
    service_types+=("$(detect_service_type "$project_dir/backend")")
  fi
  if [ -d "$project_dir/frontend" ] && detect_service_type "$project_dir/frontend" &>/dev/null; then
    services+=("frontend")
    service_paths+=("frontend")
    service_types+=("$(detect_service_type "$project_dir/frontend")")
  fi
  if [ -d "$project_dir/api" ] && detect_service_type "$project_dir/api" &>/dev/null; then
    services+=("api")
    service_paths+=("api")
    service_types+=("$(detect_service_type "$project_dir/api")")
  fi
  if [ -d "$project_dir/web" ] && detect_service_type "$project_dir/web" &>/dev/null; then
    services+=("web")
    service_paths+=("web")
    service_types+=("$(detect_service_type "$project_dir/web")")
  fi
  if [ -d "$project_dir/worker" ] && detect_service_type "$project_dir/worker" &>/dev/null; then
    services+=("worker")
    service_paths+=("worker")
    service_types+=("$(detect_service_type "$project_dir/worker")")
  fi

  # Pattern 3: Docker compose service names
  for compose in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [ -f "$project_dir/$compose" ]; then
      local compose_services
      compose_services=$(grep -E '^\s{2}\w+:$' "$project_dir/$compose" 2>/dev/null | sed 's/://;s/^\s*//' | grep -vE '^(services|volumes|networks)$' || true)
      if [ -n "$compose_services" ]; then
        echo -e "  ${BOLD}Docker Compose services:${NC}"
        echo "$compose_services" | while read -r svc; do
          echo -e "    ${CYAN}*${NC} $svc"
        done
        echo ""
      fi
      break
    fi
  done

  # Results
  if [ ${#services[@]} -eq 0 ]; then
    echo -e "  ${DIM}Single-service project (not a monorepo)${NC}"
    echo ""
    echo -e "  Run ${CYAN}tasuki onboard${NC} to configure normally."
  elif [ ${#services[@]} -eq 1 ]; then
    echo -e "  ${DIM}Single service detected: ${services[0]} (${service_types[0]})${NC}"
    echo ""
    echo -e "  Run ${CYAN}tasuki onboard${NC} to configure normally."
  else
    echo -e "  ${GREEN}${BOLD}Monorepo detected!${NC} ${#services[@]} services found:"
    echo ""

    local i
    for i in $(seq 0 $((${#services[@]} - 1))); do
      echo -e "    ${GREEN}$((i + 1)).${NC} ${BOLD}${services[$i]}${NC} — ${service_types[$i]}"
      echo -e "       ${DIM}${service_paths[$i]}/${NC}"
    done

    echo ""
    echo -e "  ${BOLD}To onboard each service:${NC}"
    for i in $(seq 0 $((${#services[@]} - 1))); do
      echo -e "    ${CYAN}tasuki onboard ${service_paths[$i]}${NC}"
    done
    echo ""
    echo -e "  Each service gets its own .tasuki/ config tailored to its stack."
  fi
  echo ""
}

detect_service_type() {
  local dir="$1"

  # Python
  if [ -f "$dir/requirements.txt" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/Pipfile" ]; then
    if grep -qi "fastapi" "$dir"/requirements*.txt "$dir"/pyproject.toml 2>/dev/null; then
      echo "python-fastapi"
    elif grep -qi "django" "$dir"/requirements*.txt "$dir"/pyproject.toml 2>/dev/null; then
      echo "python-django"
    elif grep -qi "flask" "$dir"/requirements*.txt "$dir"/pyproject.toml 2>/dev/null; then
      echo "python-flask"
    else
      echo "python"
    fi
    return
  fi

  # Node/TS
  if [ -f "$dir/package.json" ]; then
    local pkg
    pkg=$(cat "$dir/package.json" 2>/dev/null)
    if echo "$pkg" | grep -q '"next"'; then echo "nextjs"; return; fi
    if echo "$pkg" | grep -q '"@sveltejs/kit"'; then echo "sveltekit"; return; fi
    if echo "$pkg" | grep -q '"nuxt"'; then echo "nuxt"; return; fi
    if echo "$pkg" | grep -q '"@nestjs/core"'; then echo "nestjs"; return; fi
    if echo "$pkg" | grep -q '"express"'; then echo "express"; return; fi
    if echo "$pkg" | grep -q '"react"'; then echo "react"; return; fi
    if echo "$pkg" | grep -q '"vue"'; then echo "vue"; return; fi
    echo "node"
    return
  fi

  # Go
  if [ -f "$dir/go.mod" ]; then echo "go"; return; fi

  # Ruby
  if [ -f "$dir/Gemfile" ]; then echo "ruby"; return; fi

  # Java
  if [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ]; then echo "java"; return; fi

  # PHP
  if [ -f "$dir/composer.json" ]; then echo "php"; return; fi

  echo "unknown"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_monorepo "$@"
fi
