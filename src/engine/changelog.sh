#!/bin/bash
# Tasuki Engine — Changelog Generator
# Auto-generates changelog from tasuki-plans/ + git commits.
# Usage: bash changelog.sh [/path/to/project] [since-date]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

generate_changelog() {
  local project_dir="${1:-.}"
  local since="${2:-}"
  project_dir="$(cd "$project_dir" && pwd)"

  echo ""
  echo -e "${BOLD}Tasuki Changelog Generator${NC}"
  echo -e "${DIM}══════════════════════════${NC}"
  echo ""

  local changelog="$project_dir/CHANGELOG.md"
  local date
  date=$(date '+%Y-%m-%d')
  local version="unreleased"

  # Get version from package.json or pyproject.toml
  if [ -f "$project_dir/package.json" ]; then
    version=$(grep -oE '"version":\s*"[^"]*"' "$project_dir/package.json" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unreleased")
  elif [ -f "$project_dir/pyproject.toml" ]; then
    version=$(grep -oE 'version\s*=\s*"[^"]*"' "$project_dir/pyproject.toml" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unreleased")
  fi

  local content=""

  # Header
  content="# Changelog

## [$version] — $date
"

  # From tasuki-plans (completed features)
  if [ -d "$project_dir/tasuki-plans" ]; then
    local has_plans=false
    for plan_dir in "$project_dir/tasuki-plans"/*/; do
      [ -d "$plan_dir" ] || continue
      local status_file="$plan_dir/status.md"
      local prd_file="$plan_dir/prd.md"
      local feature_name
      feature_name=$(basename "$plan_dir")

      # Get title from PRD
      local title="$feature_name"
      if [ -f "$prd_file" ]; then
        title=$(head -1 "$prd_file" | sed 's/^#\s*//' | sed 's/^PRD:\s*//')
      fi

      # Check status
      local status="planned"
      if [ -f "$status_file" ]; then
        status=$(grep -oE 'Current:\s*\w+' "$status_file" 2>/dev/null | sed 's/Current:\s*//' || echo "planned")
      fi

      if ! $has_plans; then
        content+="
### Features (from Tasuki Plans)
"
        has_plans=true
      fi

      case "$status" in
        done|completed) content+="- **$title** — completed
" ;;
        in-progress|active) content+="- **$title** — in progress
" ;;
        *) content+="- **$title** — $status
" ;;
      esac
    done
  fi

  # From git log
  if [ -d "$project_dir/.git" ]; then
    local git_log_args="--oneline --no-merges"
    if [ -n "$since" ]; then
      git_log_args="$git_log_args --since=$since"
    else
      git_log_args="$git_log_args -20"
    fi

    local commits
    commits=$(cd "$project_dir" && git log $git_log_args 2>/dev/null || true)

    if [ -n "$commits" ]; then
      # Categorize by conventional commit type
      local features="" fixes="" chores="" others=""

      while IFS= read -r line; do
        local msg="${line#* }"  # remove hash
        case "$msg" in
          feat:*|feat\(*) features+="- ${msg#*: }
" ;;
          fix:*|fix\(*)   fixes+="- ${msg#*: }
" ;;
          chore:*|docs:*|ci:*|style:*|refactor:*) chores+="- $msg
" ;;
          *)               others+="- $msg
" ;;
        esac
      done <<< "$commits"

      if [ -n "$features" ]; then
        content+="
### Added
$features"
      fi
      if [ -n "$fixes" ]; then
        content+="
### Fixed
$fixes"
      fi
      if [ -n "$chores" ] || [ -n "$others" ]; then
        content+="
### Changed
${chores}${others}"
      fi
    fi
  fi

  # Write or display
  if [ -f "$changelog" ]; then
    # Prepend to existing changelog
    local tmp
    tmp=$(mktemp)
    echo "$content" > "$tmp"
    echo "" >> "$tmp"
    echo "---" >> "$tmp"
    echo "" >> "$tmp"
    cat "$changelog" >> "$tmp"
    mv "$tmp" "$changelog"
    log_success "Updated: $changelog"
  else
    echo "$content" > "$changelog"
    log_success "Created: $changelog"
  fi

  echo ""
  # Preview
  echo "$content"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  generate_changelog "$@"
fi
