#!/bin/bash
# Tasuki Engine — Multi-AI Adapter
# Generates configuration for any supported AI coding assistant.
# Translates from Tasuki's universal format to the target's expected structure.
#
# Usage:
#   bash adapt.sh <target> [/path/to/project]
#   bash adapt.sh --list
#   bash adapt.sh all [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ADAPTERS_DIR="$TASUKI_SRC/adapters"
source "$ADAPTERS_DIR/base.sh"
source "$ADAPTERS_DIR/model-map.sh"

adapt_project() {
  local target="$1"
  local project_dir="${2:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  # Validate target
  if ! is_valid_target "$target"; then
    log_error "Unknown target: $target"
    echo ""
    list_targets
    exit 1
  fi

  # Need Claude config as base (source of truth)
  if [ ! -d "$project_dir/.tasuki" ] && [ "$target" != "claude" ]; then
    log_warn "No .tasuki/ config found. Running onboard first..."
    bash "$SCRIPT_DIR/onboard.sh" "$project_dir"
  fi

  echo ""
  echo -e "${BOLD}Tasuki — Generate for: ${CYAN}$target${NC}"
  echo ""

  if [ "$target" = "all" ]; then
    for t in "${ALL_TARGETS[@]}"; do
      echo -e "${BOLD}[$t]${NC}"
      local adapter_file="$ADAPTERS_DIR/${t}.sh"
      if [ -f "$adapter_file" ]; then
        source "$adapter_file"
        generate_config "$project_dir"
        # Translate model names to target platform
        translate_models_for_target "$t" "$project_dir"
      fi
      echo ""
    done

    echo -e "${DIM}─────────────────${NC}"
    log_success "Generated for ${#ALL_TARGETS[@]} AI tools"
    echo ""
    echo -e "  Your project now works with:"
    for t in "${ALL_TARGETS[@]}"; do
      source "$ADAPTERS_DIR/${t}.sh"
      local info
      info=$(get_adapter_info)
      local tool_name
      tool_name=$(echo "$info" | cut -d'|' -f3)
      local output_format
      output_format=$(echo "$info" | cut -d'|' -f2)
      echo -e "    ${GREEN}*${NC} ${BOLD}$tool_name${NC} ${DIM}($output_format)${NC}"
    done
  else
    local adapter_file="$ADAPTERS_DIR/${target}.sh"
    if [ -f "$adapter_file" ]; then
      source "$adapter_file"
      generate_config "$project_dir"
      translate_models_for_target "$target" "$project_dir"
    else
      log_error "Adapter not found: $adapter_file"
      exit 1
    fi
  fi

  echo ""
}

translate_models_for_target() {
  local target="$1"
  local project_dir="$2"

  # Skip claude — it's the source, already has correct models
  [ "$target" = "claude" ] && return

  local target_dir
  target_dir=$(get_target_dir "$target")

  # Find all generated .md files and translate model references
  local search_dirs=()
  [ -n "$target_dir" ] && [ -d "$project_dir/$target_dir" ] && search_dirs+=("$project_dir/$target_dir")

  # Also translate root files
  for root_file in "$project_dir/.cursorrules" "$project_dir/.windsurfrules" "$project_dir/AGENTS.md" "$project_dir/GEMINI.md"; do
    [ -f "$root_file" ] && translate_file_models "$target" "$root_file"
  done

  # Translate files in target directory
  for dir in "${search_dirs[@]}"; do
    find "$dir" -name "*.md" -type f 2>/dev/null | while read -r file; do
      translate_file_models "$target" "$file"
    done
  done

  local thinking execution
  thinking=$(translate_model "$target" "opus")
  execution=$(translate_model "$target" "sonnet")
  log_dim "    models: thinking=$thinking, execution=$execution"
}

list_targets() {
  echo -e "${BOLD}Supported AI Tools:${NC}"
  echo ""

  for t in "${ALL_TARGETS[@]}"; do
    local adapter_file="$ADAPTERS_DIR/${t}.sh"
    if [ -f "$adapter_file" ]; then
      source "$adapter_file"
      local info
      info=$(get_adapter_info)
      local name output tool
      name=$(echo "$info" | cut -d'|' -f1)
      output=$(echo "$info" | cut -d'|' -f2)
      tool=$(echo "$info" | cut -d'|' -f3)
      printf "  ${GREEN}%-12s${NC} %-40s ${DIM}%s${NC}\n" "$name" "$output" "$tool"
    fi
  done

  echo ""
  echo -e "  ${CYAN}all${NC}          Generate for all targets at once"
  echo ""
  echo -e "${BOLD}Usage:${NC}"
  echo -e "  tasuki onboard . --target cursor"
  echo -e "  tasuki onboard . --target all"
  echo -e "  tasuki adapt codex ."
  echo ""
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --list|-l|list)
      list_targets
      ;;
    "")
      log_error "Usage: adapt.sh <target|--list> [path]"
      list_targets
      ;;
    *)
      adapt_project "$@"
      ;;
  esac
fi
