#!/bin/bash
# Tasuki Engine — Error Memory
# Records mistakes so agents don't repeat them.
# Each error becomes a "DO NOT" rule that loads in Project Facts.
#
# When an agent makes a mistake:
#   tasuki error "Used print() instead of logger" --agent backend-dev
#
# This creates:
#   memory-vault/errors/used-print-instead-of-logger.md
#   AND appends to project-facts.md "Do NOT" section
#
# Usage:
#   bash errors.sh add "description" [--agent name] [/path/to/project]
#   bash errors.sh list [/path/to/project]
#   bash errors.sh clear [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

error_add() {
  local description=""
  local agent="unknown"
  local project_dir="."

  # Parse args
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) shift; agent="${1:-unknown}" ;;
      --) shift; break ;;
      -*) ;;
      *)
        if [ -z "$description" ]; then
          description="$1"
        else
          project_dir="$1"
        fi
        ;;
    esac
    shift
  done

  if [ -z "$description" ]; then
    log_error "Usage: tasuki error \"description of the mistake\" --agent backend-dev"
    exit 1
  fi

  project_dir="$(cd "$project_dir" && pwd)"
  local errors_dir="$project_dir/memory-vault/errors"
  mkdir -p "$errors_dir"

  # Generate slug
  local slug
  slug=$(echo "$description" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-50)

  local date
  date=$(date '+%Y-%m-%d')

  # Create error node in vault
  local error_file="$errors_dir/$slug.md"
  cat > "$error_file" << EOF
# Error: $description

Type: Error
Created: $date
Agent: [[$agent]]

## What Happened
$description

## Rule
DO NOT: $description

## Prevention
This was recorded to prevent repetition. All agents should check project-facts.md before acting.

## Related
- [[$agent]]
EOF

  # Regenerate project facts to include this error
  if [ -f "$SCRIPT_DIR/facts.sh" ]; then
    source "$SCRIPT_DIR/facts.sh"
    generate_facts "$project_dir" 2>/dev/null
  fi

  log_success "Error recorded: $slug"
  log_dim "  Rule: DO NOT — $description"
  log_dim "  Agent: $agent"
  log_dim "  File: $error_file"
  echo ""
}

error_list() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local errors_dir="$project_dir/memory-vault/errors"

  echo ""
  echo -e "${BOLD}Error Memory${NC}"
  echo -e "${DIM}════════════${NC}"
  echo ""

  if [ ! -d "$errors_dir" ] || [ "$(find "$errors_dir" -name "*.md" 2>/dev/null | wc -l)" -eq 0 ]; then
    echo -e "  ${DIM}No errors recorded yet.${NC}"
    echo -e "  ${DIM}When agents make mistakes, record them:${NC}"
    echo -e "  ${CYAN}tasuki error \"description\" --agent backend-dev${NC}"
    echo ""
    return
  fi

  for f in "$errors_dir"/*.md; do
    [ -f "$f" ] || continue
    local name
    name=$(basename "$f" .md)
    local date
    date=$(grep "^Created:" "$f" 2>/dev/null | sed 's/Created:\s*//')
    local agent
    agent=$(grep "^Agent:" "$f" 2>/dev/null | sed 's/Agent:\s*//' | sed 's/\[\[//;s/\]\]//')
    local rule
    rule=$(grep "^DO NOT:" "$f" 2>/dev/null | head -1)

    echo -e "  ${RED}*${NC} ${BOLD}$rule${NC}"
    echo -e "    ${DIM}$date — agent: $agent${NC}"
    echo ""
  done
}

error_clear() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local errors_dir="$project_dir/memory-vault/errors"

  if [ -d "$errors_dir" ]; then
    local count
    count=$(find "$errors_dir" -name "*.md" 2>/dev/null | wc -l)
    rm -f "$errors_dir"/*.md
    log_success "Cleared $count error(s)"

    # Regenerate facts
    if [ -f "$SCRIPT_DIR/facts.sh" ]; then
      source "$SCRIPT_DIR/facts.sh"
      generate_facts "$project_dir" 2>/dev/null
    fi
  fi
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-list}" in
    add)   shift; error_add "$@" ;;
    list)  shift; error_list "$@" ;;
    clear) shift; error_clear "$@" ;;
    *)
      echo "Usage:"
      echo "  tasuki error \"mistake description\" --agent name"
      echo "  tasuki errors                              List recorded errors"
      echo "  tasuki errors clear                        Clear all errors"
      ;;
  esac
fi
