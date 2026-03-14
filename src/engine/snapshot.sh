#!/bin/bash
# Tasuki Engine — Project Snapshot
# Saves a configured project as a reusable template for `tasuki init`.
# Usage: bash snapshot.sh <name> [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

take_snapshot() {
  local name="${1:-}"
  local project_dir="${2:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  if [ -z "$name" ]; then
    log_error "Usage: tasuki snapshot <name> [path]"
    echo ""
    echo "  Saves your project's structure as a reusable template."
    echo "  Others can create projects from it: tasuki init --from $name"
    exit 1
  fi

  local snapshot_dir="$TASUKI_ROOT/src/snapshots/$name"

  if [ -d "$snapshot_dir" ]; then
    log_warn "Snapshot '$name' already exists. Overwrite? (y/n)"
    read -r confirm
    [ "$confirm" != "y" ] && exit 0
    rm -rf "$snapshot_dir"
  fi

  echo ""
  echo -e "${BOLD}Tasuki Snapshot: $name${NC}"
  echo ""

  mkdir -p "$snapshot_dir"

  # 1. Save directory structure (without content)
  log_info "Capturing project structure..."
  find "$project_dir" -type f \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.tasuki/*" \
    -not -path "*/memory-vault/*" \
    -not -path "*/tasuki-plans/*" \
    -not -path "*/.next/*" \
    -not -path "*/.svelte-kit/*" \
    -not -path "*/build/*" \
    -not -path "*/dist/*" \
    -not -path "*/.env" \
    2>/dev/null | sed "s|$project_dir/||" | sort > "$snapshot_dir/structure.txt"

  local file_count
  file_count=$(wc -l < "$snapshot_dir/structure.txt")
  log_dim "  $file_count files captured"

  # 2. Save key config files (the ones that define the project)
  log_info "Saving config files..."
  local configs=("package.json" "pyproject.toml" "requirements.txt" "Gemfile" "go.mod" "Cargo.toml" "composer.json"
                 "Dockerfile" "docker-compose.yml" "docker-compose.yaml" "compose.yml"
                 ".gitignore" ".env.example" "tsconfig.json" "svelte.config.js" "next.config.js" "nuxt.config.ts"
                 "tailwind.config.js" "tailwind.config.ts" "vite.config.ts"
                 "alembic.ini" "pytest.ini" "Makefile")

  mkdir -p "$snapshot_dir/files"
  local saved=0
  for config in "${configs[@]}"; do
    if [ -f "$project_dir/$config" ]; then
      cp "$project_dir/$config" "$snapshot_dir/files/$config"
      log_dim "  $config"
      saved=$((saved + 1))
    fi
  done

  # 3. Save .tasuki config (profile, facts, context)
  if [ -d "$project_dir/.tasuki/config" ]; then
    mkdir -p "$snapshot_dir/tasuki-config"
    cp "$project_dir/.tasuki/config/"*.md "$snapshot_dir/tasuki-config/" 2>/dev/null
    cp "$project_dir/.tasuki/config/"*.yaml "$snapshot_dir/tasuki-config/" 2>/dev/null
    log_dim "  tasuki config (facts, context, capability map)"
  fi

  # 4. Create manifest
  local project_name
  project_name=$(basename "$project_dir")
  cat > "$snapshot_dir/manifest.json" << EOF
{
  "name": "$name",
  "source": "$project_name",
  "created": "$(date '+%Y-%m-%d')",
  "files": $file_count,
  "configs": $saved
}
EOF

  echo ""
  log_success "Snapshot saved: $snapshot_dir"
  echo ""
  echo -e "  ${BOLD}Use it:${NC} tasuki init --from $name my-new-project"
  echo -e "  ${BOLD}Share it:${NC} PR to Tasuki repo (see CONTRIBUTING.md)"
  echo ""
}

# List available snapshots
list_snapshots() {
  echo ""
  echo -e "${BOLD}Available Snapshots${NC}"
  echo ""

  local snapshots_dir="$TASUKI_ROOT/src/snapshots"
  if [ ! -d "$snapshots_dir" ] || [ -z "$(ls -A "$snapshots_dir" 2>/dev/null)" ]; then
    echo -e "  ${DIM}No snapshots yet.${NC}"
    echo -e "  ${DIM}Create one: tasuki snapshot my-template${NC}"
    echo ""
    return
  fi

  for snap_dir in "$snapshots_dir"/*/; do
    [ -d "$snap_dir" ] || continue
    local name
    name=$(basename "$snap_dir")
    local source="" created="" files=""
    if [ -f "$snap_dir/manifest.json" ] && command -v python3 &>/dev/null; then
      source=$(python3 -c "import json; print(json.load(open('$snap_dir/manifest.json')).get('source',''))" 2>/dev/null)
      created=$(python3 -c "import json; print(json.load(open('$snap_dir/manifest.json')).get('created',''))" 2>/dev/null)
      files=$(python3 -c "import json; print(json.load(open('$snap_dir/manifest.json')).get('files',''))" 2>/dev/null)
    fi
    echo -e "  ${GREEN}$name${NC} ${DIM}(from: $source, $files files, $created)${NC}"
  done
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    list|--list) list_snapshots ;;
    "") log_error "Usage: tasuki snapshot <name> [path]"; echo "  tasuki snapshot --list" ;;
    *) take_snapshot "$@" ;;
  esac
fi
