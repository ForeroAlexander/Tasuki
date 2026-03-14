#!/bin/bash
# Tasuki Engine — Config Sharing (Export/Import)
# Export your project's Tasuki config as a portable .tasuki-config package.
# Another team member imports it to get the same agents, skills, rules, hooks, MCPs.
#
# Usage:
#   bash share.sh export [/path/to/project]          → creates .tasuki-config.tar.gz
#   bash share.sh import <file.tar.gz> [/path/to/project]  → applies config
#   bash share.sh preview <file.tar.gz>              → shows what's inside

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

export_config() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  if [ ! -d "$claude_dir" ]; then
    log_error "Project not onboarded. Run: tasuki onboard"
    exit 1
  fi

  local project_name
  project_name=$(basename "$project_dir")
  local date
  date=$(date '+%Y%m%d')
  local output="$project_dir/${project_name}-tasuki-config-${date}.tar.gz"

  echo ""
  echo -e "${BOLD}Tasuki Config Export${NC}"
  echo ""

  # Create temp dir with exportable files
  local tmp
  tmp=$(mktemp -d)
  local export_dir="$tmp/tasuki-config"
  mkdir -p "$export_dir"

  # Copy .tasuki/ contents (agents, rules, hooks, skills, settings)
  cp -r "$claude_dir/agents" "$export_dir/" 2>/dev/null || true
  cp -r "$claude_dir/rules" "$export_dir/" 2>/dev/null || true
  cp -r "$claude_dir/hooks" "$export_dir/" 2>/dev/null || true
  cp -r "$claude_dir/skills" "$export_dir/" 2>/dev/null || true
  cp "$claude_dir/settings.json" "$export_dir/" 2>/dev/null || true

  # Copy capability map
  mkdir -p "$export_dir/config"
  cp "$claude_dir/config/capability-map.yaml" "$export_dir/config/" 2>/dev/null || true

  # Copy .mcp.json
  cp "$project_dir/.mcp.json" "$export_dir/" 2>/dev/null || true

  # Copy TASUKI.md
  cp "$project_dir/TASUKI.md" "$export_dir/" 2>/dev/null || true

  # Copy memory vault (project knowledge)
  if [ -d "$project_dir/memory-vault" ]; then
    cp -r "$project_dir/memory-vault" "$export_dir/" 2>/dev/null || true
  fi

  # Copy project facts
  cp "$claude_dir/config/project-facts.md" "$export_dir/config/" 2>/dev/null || true

  # Create manifest
  cat > "$export_dir/manifest.json" << MEOF
{
  "exported_from": "$project_name",
  "exported_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "tasuki_version": "1.0.0",
  "agents": $(ls "$export_dir/agents/"*.md 2>/dev/null | wc -l),
  "rules": $(ls "$export_dir/rules/"*.md 2>/dev/null | wc -l),
  "hooks": $(ls "$export_dir/hooks/"*.sh 2>/dev/null | wc -l),
  "skills": $(ls -d "$export_dir/skills/"*/ 2>/dev/null | wc -l),
  "has_mcp": $([ -f "$export_dir/.mcp.json" ] && echo "true" || echo "false")
}
MEOF

  # Create tarball
  tar -czf "$output" -C "$tmp" tasuki-config
  rm -rf "$tmp"

  local size
  size=$(du -h "$output" | cut -f1)

  log_success "Exported: $(basename "$output") ($size)"
  echo ""

  # Summary
  echo -e "  ${BOLD}Contents:${NC}"
  echo -e "    Agents:   $(ls "$claude_dir/agents/"*.md 2>/dev/null | wc -l) files"
  echo -e "    Rules:    $(ls "$claude_dir/rules/"*.md 2>/dev/null | wc -l) files"
  echo -e "    Hooks:    $(ls "$claude_dir/hooks/"*.sh 2>/dev/null | wc -l) files"
  echo -e "    Skills:   $(ls -d "$claude_dir/skills/"*/ 2>/dev/null | wc -l) directories"
  echo -e "    MCP:      $([ -f "$project_dir/.mcp.json" ] && echo "yes" || echo "no")"
  echo -e "    TASUKI.md: $([ -f "$project_dir/TASUKI.md" ] && echo "yes" || echo "no")"
  echo ""
  echo -e "  ${BOLD}Share with team:${NC}"
  echo -e "    Send ${CYAN}$(basename "$output")${NC} to your teammate."
  echo -e "    They run: ${CYAN}tasuki import $(basename "$output")${NC}"
  echo ""
}

import_config() {
  local archive="$1"
  local project_dir="${2:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  if [ ! -f "$archive" ]; then
    log_error "File not found: $archive"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki Config Import${NC}"
  echo ""

  # Extract to temp
  local tmp
  tmp=$(mktemp -d)
  tar -xzf "$archive" -C "$tmp"

  local config_dir="$tmp/tasuki-config"

  if [ ! -d "$config_dir" ]; then
    log_error "Invalid tasuki config archive"
    rm -rf "$tmp"
    exit 1
  fi

  # Show manifest
  if [ -f "$config_dir/manifest.json" ]; then
    echo -e "  ${BOLD}Source:${NC} $(python3 -c "import json; print(json.load(open('$config_dir/manifest.json'))['exported_from'])" 2>/dev/null || echo "unknown")"
    echo -e "  ${BOLD}Date:${NC}   $(python3 -c "import json; print(json.load(open('$config_dir/manifest.json'))['exported_at'])" 2>/dev/null || echo "unknown")"
    echo ""
  fi

  # Check for existing config
  if [ -d "$claude_dir" ]; then
    log_warn "Existing .tasuki/ found — will merge (not overwrite)"
    echo ""
  fi

  # Import
  mkdir -p "$claude_dir"/{agents,rules,hooks,skills,config}

  local imported=0

  # Agents
  if [ -d "$config_dir/agents" ]; then
    for f in "$config_dir/agents"/*.md; do
      [ -f "$f" ] || continue
      local name
      name=$(basename "$f")
      if [ -f "$claude_dir/agents/$name" ]; then
        log_dim "  agents/$name — already exists (skipped)"
      else
        cp "$f" "$claude_dir/agents/$name"
        log_success "  agents/$name — imported"
        imported=$((imported + 1))
      fi
    done
  fi

  # Rules
  if [ -d "$config_dir/rules" ]; then
    for f in "$config_dir/rules"/*.md; do
      [ -f "$f" ] || continue
      local name
      name=$(basename "$f")
      if [ -f "$claude_dir/rules/$name" ]; then
        log_dim "  rules/$name — already exists (skipped)"
      else
        cp "$f" "$claude_dir/rules/$name"
        log_success "  rules/$name — imported"
        imported=$((imported + 1))
      fi
    done
  fi

  # Hooks
  if [ -d "$config_dir/hooks" ]; then
    for f in "$config_dir/hooks"/*.sh; do
      [ -f "$f" ] || continue
      local name
      name=$(basename "$f")
      cp "$f" "$claude_dir/hooks/$name"
      chmod +x "$claude_dir/hooks/$name"
      log_success "  hooks/$name — imported"
      imported=$((imported + 1))
    done
  fi

  # Skills
  if [ -d "$config_dir/skills" ]; then
    for d in "$config_dir/skills"/*/; do
      [ -d "$d" ] || continue
      local name
      name=$(basename "$d")
      if [ -d "$claude_dir/skills/$name" ]; then
        log_dim "  skills/$name — already exists (skipped)"
      else
        cp -r "$d" "$claude_dir/skills/$name"
        log_success "  skills/$name — imported"
        imported=$((imported + 1))
      fi
    done
  fi

  # Settings.json — merge permissions, don't overwrite
  if [ -f "$config_dir/settings.json" ] && [ ! -f "$claude_dir/settings.json" ]; then
    cp "$config_dir/settings.json" "$claude_dir/settings.json"
    log_success "  settings.json — imported"
    imported=$((imported + 1))
  fi

  # MCP — merge servers
  if [ -f "$config_dir/.mcp.json" ]; then
    if [ -f "$project_dir/.mcp.json" ] && command -v python3 &>/dev/null; then
      python3 << PYEOF
import json
with open("$project_dir/.mcp.json") as f:
    existing = json.load(f)
with open("$config_dir/.mcp.json") as f:
    imported = json.load(f)
merged = existing.get("mcpServers", {})
new_count = 0
for name, config in imported.get("mcpServers", {}).items():
    if name not in merged:
        merged[name] = config
        new_count += 1
existing["mcpServers"] = merged
with open("$project_dir/.mcp.json", "w") as f:
    json.dump(existing, f, indent=2)
print(f"  .mcp.json — merged ({new_count} new servers)")
PYEOF
    elif [ ! -f "$project_dir/.mcp.json" ]; then
      cp "$config_dir/.mcp.json" "$project_dir/.mcp.json"
      log_success "  .mcp.json — imported"
      imported=$((imported + 1))
    fi
  fi

  # Capability map
  if [ -f "$config_dir/config/capability-map.yaml" ] && [ ! -f "$claude_dir/config/capability-map.yaml" ]; then
    cp "$config_dir/config/capability-map.yaml" "$claude_dir/config/"
    log_success "  capability-map.yaml — imported"
    imported=$((imported + 1))
  fi

  # Memory vault — merge (don't overwrite existing nodes)
  if [ -d "$config_dir/memory-vault" ]; then
    mkdir -p "$project_dir/memory-vault"
    local vault_imported=0
    find "$config_dir/memory-vault" -name "*.md" -type f | while read -r vault_file; do
      local rel_path="${vault_file#$config_dir/memory-vault/}"
      local target="$project_dir/memory-vault/$rel_path"
      if [ ! -f "$target" ]; then
        mkdir -p "$(dirname "$target")"
        cp "$vault_file" "$target"
        vault_imported=$((vault_imported + 1))
      fi
    done
    log_success "  memory-vault — merged"
    imported=$((imported + 1))
  fi

  rm -rf "$tmp"

  echo ""
  log_success "Imported $imported components"
  echo ""
  echo -e "  Run ${CYAN}tasuki discover${NC} to rebuild capability map"
  echo -e "  Run ${CYAN}tasuki validate${NC} to verify config"
  echo ""
}

preview_config() {
  local archive="$1"

  if [ ! -f "$archive" ]; then
    log_error "File not found: $archive"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki Config Preview${NC}"
  echo -e "${DIM}$(basename "$archive")${NC}"
  echo ""

  tar -tzf "$archive" | sort | while read -r f; do
    # Skip directory entries
    [[ "$f" == */ ]] && continue
    local rel="${f#tasuki-config/}"
    echo -e "  ${GREEN}${rel}${NC}"
  done
  echo ""
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    export)  shift; export_config "$@" ;;
    import)  shift; import_config "$@" ;;
    preview) shift; preview_config "$@" ;;
    *)
      echo "Usage:"
      echo "  tasuki export [path]              Export config as .tar.gz"
      echo "  tasuki import <file.tar.gz> [path] Import config from teammate"
      echo "  tasuki preview <file.tar.gz>       Preview archive contents"
      ;;
  esac
fi
