#!/bin/bash
# Tasuki Engine — Project Init
# Scaffolds a new project from a template, then runs onboard automatically.
# Usage: bash init.sh <stack> <project-name> [path] [description]
#   or:  bash init.sh --list  (to list available stacks)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

STACKS_FILE="$TASUKI_SRC/stacks.yaml"

# --- List available stacks ---
list_stacks() {
  echo ""
  echo -e "${BOLD}Available Project Templates${NC}"
  echo -e "${DIM}═══════════════════════════${NC}"
  echo ""

  local in_stacks=false
  local current_name=""
  local current_display=""
  local current_desc=""
  local current_lang=""
  local current_deploy=""

  while IFS= read -r line; do
    if echo "$line" | grep -qE '^stacks:'; then
      in_stacks=true
      continue
    fi

    if $in_stacks; then
      # Stack entry (2-space indent)
      if echo "$line" | grep -qE '^  [a-z].*:$'; then
        # Print previous
        if [ -n "$current_name" ]; then
          printf "  ${GREEN}%-12s${NC} %-30s ${DIM}[%s, deploy: %s]${NC}\n" "$current_name" "$current_display" "$current_lang" "$current_deploy"
          echo -e "              ${DIM}$current_desc${NC}"
          echo ""
        fi
        current_name=$(echo "$line" | sed 's/^\s*//' | sed 's/:$//')
        current_display=""
        current_desc=""
        current_lang=""
        current_deploy=""
      fi

      # Fields
      echo "$line" | grep -qE '^\s+name:' && current_display=$(echo "$line" | sed 's/.*name:\s*//' | sed 's/"//g')
      echo "$line" | grep -qE '^\s+description:' && current_desc=$(echo "$line" | sed 's/.*description:\s*//' | sed 's/"//g')
      echo "$line" | grep -qE '^\s+lang:' && current_lang=$(echo "$line" | sed 's/.*lang:\s*//' | sed 's/"//g')
      echo "$line" | grep -qE '^\s+deploy:' && current_deploy=$(echo "$line" | sed 's/.*deploy:\s*//' | sed 's/"//g')
    fi
  done < "$STACKS_FILE"

  # Print last
  if [ -n "$current_name" ]; then
    printf "  ${GREEN}%-12s${NC} %-30s ${DIM}[%s, deploy: %s]${NC}\n" "$current_name" "$current_display" "$current_lang" "$current_deploy"
    echo -e "              ${DIM}$current_desc${NC}"
    echo ""
  fi

  echo -e "${BOLD}Usage:${NC}"
  echo -e "  tasuki init <stack> <project-name> [path] [\"description\"]"
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo -e "  tasuki init nextjs my-app"
  echo -e "  tasuki init fastapi my-api ~/projects"
  echo -e "  tasuki init landing my-site . \"My awesome landing page\""
  echo ""
}

# --- Init project ---
init_project() {
  local stack="$1"
  local project_name="$2"
  local parent_dir="${3:-.}"
  local description="${4:-A new $stack project}"

  # Validate inputs
  if [ -z "$stack" ] || [ -z "$project_name" ]; then
    log_error "Usage: tasuki init <stack> <project-name> [path] [\"description\"]"
    echo ""
    echo "Run 'tasuki init --list' to see available stacks."
    exit 1
  fi

  # Check stack exists in catalog
  if ! grep -qE "^  ${stack}:" "$STACKS_FILE" 2>/dev/null; then
    log_error "Unknown stack: $stack"
    echo ""
    echo "Available stacks:"
    grep -E '^  [a-z].*:$' "$STACKS_FILE" | sed 's/^\s*/  /' | sed 's/:$//'
    echo ""
    echo "Run 'tasuki init --list' for details."
    exit 1
  fi

  # Resolve project directory
  parent_dir="$(cd "$parent_dir" && pwd)"
  local project_dir="$parent_dir/$project_name"

  if [ -d "$project_dir" ]; then
    log_error "Directory already exists: $project_dir"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       Tasuki — Project Init          ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Stack:${NC}       $stack"
  echo -e "  ${BOLD}Project:${NC}     $project_name"
  echo -e "  ${BOLD}Location:${NC}    $project_dir"
  echo -e "  ${BOLD}Description:${NC} $description"
  echo ""

  # Step 1: Create directory structure
  log_step "Step 1: Creating project structure"
  echo ""
  mkdir -p "$project_dir"

  create_structure "$stack" "$project_dir"

  # Step 2: Write files from templates
  log_step "Step 2: Writing project files"
  echo ""
  write_files "$stack" "$project_dir" "$project_name" "$description"

  # Step 3: Initialize git
  log_step "Step 3: Initializing git repository"
  echo ""
  cd "$project_dir" && git init -q
  log_dim "  git init"

  # Step 4: Run post-init commands
  local post_init
  post_init=$(extract_field "$stack" "post_init")
  if [ -n "$post_init" ] && [ "$post_init" != "null" ]; then
    log_step "Step 4: Running post-init setup"
    echo ""
    log_dim "  $post_init"
    cd "$project_dir" && eval "$post_init" 2>&1 | while IFS= read -r line; do
      echo -e "  ${DIM}$line${NC}"
    done || true
    echo ""
  fi

  # Step 5: Auto-onboard
  log_step "Step 5: Running Tasuki onboard"
  echo ""
  bash "$SCRIPT_DIR/onboard.sh" "$project_dir"

  # Step 6 is handled by onboard (vault + facts + discover)

  # Final summary
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║      Project Ready!                  ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}cd${NC} $project_dir"
  echo ""

  # Deploy hint based on stack
  local deploy
  deploy=$(extract_field "$stack" "deploy")
  case "$deploy" in
    vercel)
      echo -e "  ${BOLD}Deploy:${NC} npx vercel"
      ;;
    docker)
      echo -e "  ${BOLD}Deploy:${NC} docker compose up -d"
      ;;
  esac
  echo ""
}

# --- Extract the structure list for a stack ---
create_structure() {
  local stack="$1" project_dir="$2"
  local in_stack=false
  local in_structure=false

  while IFS= read -r line; do
    if echo "$line" | grep -qE "^  ${stack}:$"; then
      in_stack=true
      continue
    fi
    # Next stack starts
    if $in_stack && echo "$line" | grep -qE '^  [a-z].*:$'; then
      break
    fi

    if $in_stack && echo "$line" | grep -qE '^\s+structure:'; then
      in_structure=true
      continue
    fi

    if $in_stack && $in_structure; then
      if echo "$line" | grep -qE '^\s+- '; then
        local filepath
        filepath=$(echo "$line" | sed 's/^\s*- //')
        local dir
        dir=$(dirname "$filepath")
        mkdir -p "$project_dir/$dir"

        # Create .gitkeep files immediately
        if [ "$(basename "$filepath")" = ".gitkeep" ]; then
          touch "$project_dir/$filepath"
        fi

        log_dim "  $filepath"
      elif echo "$line" | grep -qE '^\s+[a-z]'; then
        # Left the structure section
        break
      fi
    fi
  done < "$STACKS_FILE"
}

# --- Write file contents from the files: section ---
write_files() {
  local stack="$1" project_dir="$2" project_name="$3" description="$4"
  local in_stack=false
  local in_files=false
  local current_file=""
  local current_content=""
  local file_count=0

  while IFS= read -r line; do
    if echo "$line" | grep -qE "^  ${stack}:$"; then
      in_stack=true
      continue
    fi
    # Next stack starts
    if $in_stack && echo "$line" | grep -qE '^  [a-z].*:$'; then
      break
    fi

    if $in_stack && echo "$line" | grep -qE '^\s{4}files:'; then
      in_files=true
      continue
    fi

    # Exit files section when we hit another 4-space key that's not a filename
    if $in_stack && $in_files; then
      # File name line: "filename": |
      if echo "$line" | grep -qE '^\s{6}"[^"]+":'; then
        # Write previous file if exists
        if [ -n "$current_file" ]; then
          write_single_file "$project_dir" "$current_file" "$current_content" "$project_name" "$description"
          file_count=$((file_count + 1))
        fi
        current_file=$(echo "$line" | grep -oE '"[^"]+"' | head -1 | sed 's/"//g')
        current_content=""
        continue
      fi

      # Content line (8+ spaces of indent)
      if echo "$line" | grep -qE '^\s{8}'; then
        local content_line
        content_line=$(echo "$line" | sed 's/^        //')
        if [ -n "$current_content" ]; then
          current_content="$current_content
$content_line"
        else
          current_content="$content_line"
        fi
        continue
      fi

      # Non-4-indent, non-file section — check if leaving files
      if echo "$line" | grep -qE '^\s{4}[a-z_]+:' && ! echo "$line" | grep -qE '^\s{6}'; then
        break
      fi
    fi
  done < "$STACKS_FILE"

  # Write last file
  if [ -n "$current_file" ]; then
    write_single_file "$project_dir" "$current_file" "$current_content" "$project_name" "$description"
    file_count=$((file_count + 1))
  fi

  log_info "$file_count files written"
  echo ""
}

write_single_file() {
  local project_dir="$1" filepath="$2" content="$3" project_name="$4" description="$5"

  # Replace placeholders
  content=$(echo "$content" | sed "s/{{PROJECT_NAME}}/$project_name/g" | sed "s/{{PROJECT_DESCRIPTION}}/$description/g")

  local dir
  dir=$(dirname "$filepath")
  mkdir -p "$project_dir/$dir"
  echo "$content" > "$project_dir/$filepath"
  log_dim "  $filepath"
}

# --- Extract a simple field from a stack entry ---
extract_field() {
  local stack="$1" field="$2"
  local in_stack=false

  while IFS= read -r line; do
    if echo "$line" | grep -qE "^  ${stack}:$"; then
      in_stack=true
      continue
    fi
    if $in_stack && echo "$line" | grep -qE '^  [a-z].*:$'; then
      break
    fi
    if $in_stack && echo "$line" | grep -qE "^\s+${field}:"; then
      echo "$line" | sed "s/.*${field}:\s*//" | sed 's/"//g' | sed 's/|//' | tr -d '[:space:]'
      return
    fi
  done < "$STACKS_FILE"
}

# --- Main ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --list|-l|list)
      list_stacks
      ;;
    "")
      log_error "Usage: tasuki init <stack> <project-name> [path] [\"description\"]"
      echo ""
      echo "Run 'tasuki init --list' to see available stacks."
      exit 1
      ;;
    *)
      init_project "$@"
      ;;
  esac
fi
