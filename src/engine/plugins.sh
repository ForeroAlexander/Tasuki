#!/bin/bash
# Tasuki Engine — Plugin System
# Install, uninstall, and list plugins (skills, agents, MCP servers).
# Usage: plugins.sh <action> <type> <name> [project_path]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PLUGINS_CATALOG="$TASUKI_SRC/plugins.yaml"

# --- List plugins ---
list_plugins() {
  local filter="${1:-all}"

  echo ""
  echo -e "${BOLD}Tasuki Plugin Catalog${NC}"
  echo -e "${DIM}═════════════════════${NC}"
  echo ""

  if [ "$filter" = "all" ] || [ "$filter" = "skill" ] || [ "$filter" = "skills" ]; then
    echo -e "${BOLD}Skills:${NC}"
    list_section "skills"
    echo ""
  fi

  if [ "$filter" = "all" ] || [ "$filter" = "agent" ] || [ "$filter" = "agents" ]; then
    echo -e "${BOLD}Agents:${NC}"
    list_section "agents"
    echo ""
  fi

  if [ "$filter" = "all" ] || [ "$filter" = "mcp" ]; then
    echo -e "${BOLD}MCP Servers:${NC}"
    list_section "mcp"
    echo ""
  fi
}

list_section() {
  local section="$1"
  local in_section=false
  local current_name=""
  local current_desc=""
  local current_builtin=""

  while IFS= read -r line; do
    # Section header
    if echo "$line" | grep -qE "^${section}:"; then
      in_section=true
      continue
    fi

    # Another top-level section starts
    if $in_section && echo "$line" | grep -qE '^[a-z]+:$' && ! echo "$line" | grep -qE '^\s'; then
      # Print last item
      if [ -n "$current_name" ]; then
        print_plugin_item "$current_name" "$current_desc" "$current_builtin"
      fi
      break
    fi

    if $in_section; then
      # Plugin name (2-space indent, ends with colon)
      if echo "$line" | grep -qE '^  [a-z].*:$'; then
        # Print previous item
        if [ -n "$current_name" ]; then
          print_plugin_item "$current_name" "$current_desc" "$current_builtin"
        fi
        current_name=$(echo "$line" | sed 's/^\s*//' | sed 's/:$//')
        current_desc=""
        current_builtin=""
      fi

      # Description
      if echo "$line" | grep -qE '^\s+description:'; then
        current_desc=$(echo "$line" | sed 's/.*description:\s*//' | sed 's/^"\(.*\)"$/\1/')
      fi

      # Builtin flag
      if echo "$line" | grep -qE '^\s+builtin:'; then
        current_builtin=$(echo "$line" | sed 's/.*builtin:\s*//')
      fi
    fi
  done < "$PLUGINS_CATALOG"

  # Print last item if we hit EOF
  if [ -n "$current_name" ]; then
    print_plugin_item "$current_name" "$current_desc" "$current_builtin"
  fi
}

print_plugin_item() {
  local name="$1" desc="$2" builtin="$3"
  local tag=""
  if [ "$builtin" = "true" ]; then
    tag="${DIM}[builtin]${NC}"
  else
    tag="${CYAN}[install]${NC}"
  fi
  printf "  ${GREEN}%-18s${NC} %s %b\n" "$name" "$desc" "$tag"
}

# --- Install plugin ---
install_plugin() {
  local plugin_type="$1"
  local plugin_name="$2"
  local project_dir="$3"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  # Validate
  if [ -z "$plugin_type" ] || [ -z "$plugin_name" ]; then
    log_error "Usage: tasuki install <skill|agent|mcp> <name>"
    echo ""
    echo "  Examples:"
    echo "    tasuki install skill gen-openapi"
    echo "    tasuki install agent mobile-dev"
    echo "    tasuki install mcp playwright"
    exit 1
  fi

  # Normalize type
  case "$plugin_type" in
    skill|skills) plugin_type="skill" ;;
    agent|agents) plugin_type="agent" ;;
    mcp) plugin_type="mcp" ;;
    *)
      log_error "Unknown plugin type: $plugin_type"
      log_error "Valid types: skill, agent, mcp"
      exit 1
      ;;
  esac

  # Check if project is onboarded
  if [ ! -d "$claude_dir" ]; then
    log_error "Project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  case "$plugin_type" in
    skill) install_skill "$plugin_name" "$project_dir" ;;
    agent)
      install_agent "$plugin_name" "$project_dir"
      # Auto-regenerate capability map after installing an agent
      regenerate_capability_map "$project_dir"
      ;;
    mcp)
      install_mcp "$plugin_name" "$project_dir"
      suggest_pipeline_stage "$plugin_name"
      ;;
  esac
}

suggest_pipeline_stage() {
  local mcp_name="$1"

  local stage=""
  local agent=""

  case "$mcp_name" in
    # Database MCPs → DBA + Debugger
    postgres|sqlite|mongodb|duckdb|elasticsearch|bigquery)
      stage="Stage 3 (DB Architect) + Stage 5.5 (Debugger)"
      agent="db-architect, debugger"
      ;;
    # Testing MCPs → QA + Frontend
    playwright|puppeteer)
      stage="Stage 2 (QA E2E) + Stage 5 (Frontend visual testing)"
      agent="qa, frontend-dev"
      ;;
    # Design MCPs → Frontend
    figma|stitch)
      stage="Stage 5a (Frontend design preview)"
      agent="frontend-dev"
      ;;
    # Security MCPs → Security
    semgrep|snyk)
      stage="Stage 6 (Security audit)"
      agent="security"
      ;;
    # Monitoring MCPs → Debugger + DevOps
    sentry)
      stage="Stage 5.5 (Debugger) + Stage 8 (DevOps health check)"
      agent="debugger, devops"
      ;;
    # Task management → Planner
    taskmaster-ai|taskmaster)
      stage="Stage 1b (Taskmaster)"
      agent="planner"
      ;;
    # GitHub → Reviewer + DevOps
    github)
      stage="Stage 7 (Reviewer PR) + Stage 8 (DevOps CI)"
      agent="reviewer, devops"
      ;;
    # Documentation → All
    context7|docfork)
      stage="All stages (documentation lookup)"
      agent="all agents"
      ;;
    *)
      return  # Unknown MCP, no suggestion
      ;;
  esac

  if [ -n "$stage" ]; then
    echo ""
    log_info "Pipeline connection:"
    log_dim "  Stage: $stage"
    log_dim "  Agents: $agent"
    log_dim "  The agents above can now use this MCP in their respective stages."
  fi
}

regenerate_capability_map() {
  local project_dir="$1"
  if [ -d "$project_dir/.tasuki/agents" ]; then
    source "$SCRIPT_DIR/discover.sh"
    discover_agents "$project_dir"
    generate_capability_map "$project_dir" >/dev/null 2>&1
    log_info "Capability map updated — agent auto-discovered"
  fi
}

install_skill() {
  local name="$1" project_dir="$2"
  local claude_dir="$project_dir/.tasuki"
  local skill_dir="$claude_dir/skills/$name"

  # Check if already installed
  if [ -d "$skill_dir" ]; then
    log_warn "Skill '$name' is already installed."
    return 0
  fi

  # Check if it's a builtin (copy from templates)
  if [ -d "$TASUKI_TEMPLATES/skills/$name" ]; then
    mkdir -p "$skill_dir"
    cp "$TASUKI_TEMPLATES/skills/$name/SKILL.md" "$skill_dir/SKILL.md"
    log_success "Installed builtin skill: $name"
    return 0
  fi

  # Check catalog for template
  local template
  template=$(extract_plugin_template "skills" "$name")

  if [ -n "$template" ]; then
    mkdir -p "$skill_dir"
    echo "$template" > "$skill_dir/SKILL.md"
    log_success "Installed skill: $name"
    log_dim "  Location: $skill_dir/SKILL.md"
  else
    log_error "Skill '$name' not found in catalog."
    log_info "Run 'tasuki plugins skills' to see available skills."
    exit 1
  fi
}

install_agent() {
  local name="$1" project_dir="$2"
  local claude_dir="$project_dir/.tasuki"
  local agent_file="$claude_dir/agents/$name.md"

  # Check if already installed
  if [ -f "$agent_file" ]; then
    log_warn "Agent '$name' is already installed."
    return 0
  fi

  # Check if it's a builtin (copy from templates)
  if [ -f "$TASUKI_TEMPLATES/agents/$name.md" ]; then
    cp "$TASUKI_TEMPLATES/agents/$name.md" "$agent_file"
    log_success "Installed builtin agent: $name"
    return 0
  fi

  # Check catalog for template
  local template
  template=$(extract_plugin_template "agents" "$name")

  if [ -n "$template" ]; then
    # Replace {{PROJECT_NAME}} with actual project name
    local project_name
    project_name=$(basename "$project_dir")
    echo "$template" | sed "s/{{PROJECT_NAME}}/$project_name/g" > "$agent_file"
    log_success "Installed agent: $name"
    log_dim "  Location: $agent_file"

    # Also add to registry awareness
    log_info "Agent installed. Update TASUKI.md to include it in the pipeline if needed."
  else
    log_error "Agent '$name' not found in catalog."
    log_info "Run 'tasuki plugins agents' to see available agents."
    exit 1
  fi
}

install_mcp() {
  local name="$1" project_dir="$2"
  local mcp_file="$project_dir/.mcp.json"

  # Read MCP info from catalog
  local package="" transport="" url=""
  local in_mcp=false
  local in_target=false

  while IFS= read -r line; do
    if echo "$line" | grep -qE '^mcp:'; then
      in_mcp=true
      continue
    fi
    if $in_mcp && echo "$line" | grep -qE "^  ${name}:"; then
      in_target=true
      continue
    fi
    if $in_mcp && $in_target; then
      if echo "$line" | grep -qE '^\s+package:'; then
        package=$(echo "$line" | sed 's/.*package:\s*//' | sed 's/"//g')
      fi
      if echo "$line" | grep -qE '^\s+transport:'; then
        transport=$(echo "$line" | sed 's/.*transport:\s*//' | sed 's/"//g')
      fi
      if echo "$line" | grep -qE '^\s+url:'; then
        url=$(echo "$line" | sed 's/.*url:\s*//' | sed 's/"//g')
      fi
      # Next entry starts
      if echo "$line" | grep -qE '^  [a-z]' && ! echo "$line" | grep -qE '^\s{4}'; then
        break
      fi
    fi
  done < "$PLUGINS_CATALOG"

  if [ -z "$package" ] && [ -z "$url" ]; then
    log_error "MCP server '$name' not found in catalog."
    log_info "Run 'tasuki plugins mcp' to see available MCP servers."
    exit 1
  fi

  # Ensure .mcp.json exists
  if [ ! -f "$mcp_file" ]; then
    echo '{"mcpServers":{}}' > "$mcp_file"
  fi

  # Check if already installed
  if $HAS_JQ; then
    if jq -e ".mcpServers.\"$name\"" "$mcp_file" &>/dev/null; then
      log_warn "MCP server '$name' is already installed."
      return 0
    fi
  fi

  # Build the server entry
  local server_json=""
  if [ "$transport" = "stdio" ] && [ -n "$package" ]; then
    server_json="{\"type\":\"stdio\",\"command\":\"npx\",\"args\":[\"-y\",\"$package\"]}"
  elif [ "$transport" = "http" ] && [ -n "$url" ]; then
    server_json="{\"type\":\"http\",\"url\":\"$url\"}"
  else
    log_error "Could not determine MCP server configuration for '$name'."
    exit 1
  fi

  # Add to .mcp.json
  if $HAS_JQ; then
    local tmp
    tmp=$(mktemp)
    jq ".mcpServers.\"$name\" = $server_json" "$mcp_file" > "$tmp"
    mv "$tmp" "$mcp_file"
  else
    # Fallback: simple text insertion before the closing }}
    local tmp
    tmp=$(mktemp)
    # Remove last two lines (closing braces), add entry, re-add braces
    head -n -2 "$mcp_file" > "$tmp"
    # Check if there are existing entries (need comma)
    if grep -q '"type"' "$mcp_file" 2>/dev/null; then
      echo "    ,\"$name\": $server_json" >> "$tmp"
    else
      echo "    \"$name\": $server_json" >> "$tmp"
    fi
    echo '  }' >> "$tmp"
    echo '}' >> "$tmp"
    mv "$tmp" "$mcp_file"
  fi

  log_success "Installed MCP server: $name"
  log_dim "  Package: ${package:-$url}"
  log_dim "  Transport: $transport"

  # Show setup instructions for MCPs that need credentials
  show_mcp_setup "$name"
}

# --- MCP setup instructions ---
show_mcp_setup() {
  local name="$1"
  echo ""

  case "$name" in
    sentry)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Create account at https://sentry.io"
      echo "    2. Go to Settings → API Keys → Create New Token"
      echo "    3. Set environment variable:"
      echo "       export SENTRY_AUTH_TOKEN=your_token_here"
      echo "    4. Add to your .env file for persistence"
      ;;
    figma)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Go to https://www.figma.com/developers/api"
      echo "    2. Create a personal access token"
      echo "    3. Set environment variable:"
      echo "       export FIGMA_ACCESS_TOKEN=your_token_here"
      echo "    4. Add to your .env file for persistence"
      ;;
    stitch)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Install stitch-mcp: npm install -g stitch-mcp"
      echo "    2. Configure your project in Stitch dashboard"
      echo "    3. No environment variables needed (uses npx)"
      ;;
    semgrep)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Install uvx: pip install uvx  (or pipx install uvx)"
      echo "    2. No account needed — runs locally"
      echo "    3. For cloud rules: export SEMGREP_APP_TOKEN=your_token"
      ;;
    postgres|postgresql)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Ensure PostgreSQL is running"
      echo "    2. Update the DSN in .mcp.json:"
      echo "       postgresql://user:pass@localhost:5432/your_db"
      echo "    3. Or set: export DATABASE_URL=postgresql://..."
      ;;
    mongodb|mongo)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Ensure MongoDB is running"
      echo "    2. Set: export MONGODB_URI=mongodb://localhost:27017/your_db"
      ;;
    chromadb|chroma)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Install ChromaDB: pip install chromadb"
      echo "    2. Start server: chroma run --path ./chroma_data"
      echo "    3. No account needed — runs locally"
      ;;
    cloudflare)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Create account at https://dash.cloudflare.com"
      echo "    2. Go to My Profile → API Tokens → Create Token"
      echo "    3. Set: export CLOUDFLARE_API_TOKEN=your_token"
      echo "    4. Set: export CLOUDFLARE_ACCOUNT_ID=your_account_id"
      ;;
    kubernetes|k8s)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Ensure kubectl is configured (~/.kube/config)"
      echo "    2. Verify access: kubectl cluster-info"
      echo "    3. No additional tokens needed"
      ;;
    brave-search|brave)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Get API key at https://brave.com/search/api/"
      echo "    2. Set: export BRAVE_API_KEY=your_key"
      ;;
    elasticsearch)
      echo -e "  ${BOLD}Setup required:${NC}"
      echo "    1. Ensure Elasticsearch is running"
      echo "    2. Set: export ELASTICSEARCH_URL=http://localhost:9200"
      echo "    3. For cloud: export ELASTIC_API_KEY=your_key"
      ;;
    *)
      echo -e "  ${DIM}No additional setup needed — ready to use.${NC}"
      ;;
  esac

  echo ""
  echo -e "  ${DIM}Restart your AI tool to load the new MCP server.${NC}"
}

# --- Uninstall plugin ---
uninstall_plugin() {
  local plugin_type="$1"
  local plugin_name="$2"
  local project_dir="$3"
  project_dir="$(cd "$project_dir" && pwd)"
  local claude_dir="$project_dir/.tasuki"

  if [ -z "$plugin_type" ] || [ -z "$plugin_name" ]; then
    log_error "Usage: tasuki uninstall <skill|agent|mcp> <name>"
    exit 1
  fi

  case "$plugin_type" in
    skill|skills)
      local skill_dir="$claude_dir/skills/$plugin_name"
      if [ -d "$skill_dir" ]; then
        rm -rf "$skill_dir"
        log_success "Uninstalled skill: $plugin_name"
      else
        log_warn "Skill '$plugin_name' is not installed."
      fi
      ;;
    agent|agents)
      local agent_file="$claude_dir/agents/$plugin_name.md"
      if [ -f "$agent_file" ]; then
        rm "$agent_file"
        log_success "Uninstalled agent: $plugin_name"
        regenerate_capability_map "$project_dir"
      else
        log_warn "Agent '$plugin_name' is not installed."
      fi
      ;;
    mcp)
      local mcp_file="$project_dir/.mcp.json"
      if [ -f "$mcp_file" ] && $HAS_JQ; then
        if jq -e ".mcpServers.\"$plugin_name\"" "$mcp_file" &>/dev/null; then
          local tmp
          tmp=$(mktemp)
          jq "del(.mcpServers.\"$plugin_name\")" "$mcp_file" > "$tmp"
          mv "$tmp" "$mcp_file"
          log_success "Uninstalled MCP server: $plugin_name"
        else
          log_warn "MCP server '$plugin_name' is not installed."
        fi
      else
        log_warn "Cannot uninstall MCP without jq. Remove manually from .mcp.json"
      fi
      ;;
    *)
      log_error "Unknown plugin type: $plugin_type (valid: skill, agent, mcp)"
      exit 1
      ;;
  esac
}

# --- Extract template from catalog ---
extract_plugin_template() {
  local section="$1" name="$2"
  local in_section=false
  local in_target=false
  local in_template=false
  local template=""

  while IFS= read -r line; do
    if echo "$line" | grep -qE "^${section}:"; then
      in_section=true
      continue
    fi

    # Another top-level section
    if $in_section && echo "$line" | grep -qE '^[a-z]+:$'; then
      break
    fi

    if $in_section && echo "$line" | grep -qE "^  ${name}:$"; then
      in_target=true
      continue
    fi

    if $in_target; then
      # Next plugin entry
      if echo "$line" | grep -qE '^  [a-z].*:$' && ! echo "$line" | grep -qE '^\s{4}'; then
        break
      fi

      if echo "$line" | grep -qE '^\s+template:\s*\|'; then
        in_template=true
        continue
      fi

      if $in_template; then
        # Template lines have 6+ spaces of indent
        if echo "$line" | grep -qE '^\s{6}'; then
          local content
          content=$(echo "$line" | sed 's/^      //')
          if [ -n "$template" ]; then
            template="$template
$content"
          else
            template="$content"
          fi
        elif [ -z "$line" ]; then
          template="$template
"
        else
          break
        fi
      fi
    fi
  done < "$PLUGINS_CATALOG"

  echo "$template"
}

# --- Main dispatch ---
action="${1:-}"
shift || true

case "$action" in
  list)    list_plugins "$@" ;;
  install) install_plugin "$@" ;;
  uninstall) uninstall_plugin "$@" ;;
  *)
    log_error "Usage: plugins.sh <list|install|uninstall> [args...]"
    exit 1
    ;;
esac
