#!/bin/bash
# Tasuki Engine — Catalog Updater
# Fetches latest MCP servers and skills from npm registry and known sources.
# Updates the local catalog with new entries found.
#
# Usage: bash catalog-update.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CATALOG_FILE="$TASUKI_SRC/plugins.yaml"
REMOTE_CACHE="$TASUKI_ROOT/.cache/catalog"

update_catalog() {
  echo ""
  echo -e "${BOLD}Tasuki Catalog Update${NC}"
  echo -e "${DIM}═════════════════════${NC}"
  echo ""

  mkdir -p "$REMOTE_CACHE"

  # 1. Search npm for MCP servers
  log_info "Searching npm for MCP servers..."
  fetch_npm_mcps

  # 2. Check known MCP registries
  log_info "Checking known MCP sources..."
  fetch_known_mcps

  # 3. Search for Claude Code skills
  log_info "Searching for Claude Code skills..."
  fetch_skills

  # 4. Show what was found
  print_discoveries

  echo ""
  log_success "Catalog check complete."
  log_info "Run 'tasuki plugins' to see the full catalog."
  echo ""
}

fetch_npm_mcps() {
  local cache_file="$REMOTE_CACHE/npm-mcps.txt"

  # Search npm registry for mcp-server packages
  local search_terms=("mcp-server" "@modelcontextprotocol" "mcp-" "anthropic-mcp")

  > "$cache_file"

  for term in "${search_terms[@]}"; do
    local result
    result=$(curl -sf "https://registry.npmjs.org/-/v1/search?text=$term&size=20" 2>/dev/null || true)

    if [ -n "$result" ] && command -v python3 &>/dev/null; then
      python3 -c "
import json, sys
try:
    data = json.loads('''$result''')
    for obj in data.get('objects', []):
        pkg = obj.get('package', {})
        name = pkg.get('name', '')
        desc = pkg.get('description', '')[:80]
        version = pkg.get('version', '')
        print(f'{name}|{version}|{desc}')
except:
    pass
" >> "$cache_file" 2>/dev/null || true
    fi
  done

  local count
  count=$(sort -u "$cache_file" | wc -l)
  log_dim "  Found $count packages on npm"
}

fetch_known_mcps() {
  local cache_file="$REMOTE_CACHE/known-mcps.txt"

  # Hardcoded list of verified, production-quality MCP servers
  # This list is updated when tasuki itself is updated
  cat > "$cache_file" << 'EOF'
@modelcontextprotocol/server-postgres|stdio|PostgreSQL database access with schema inspection
@modelcontextprotocol/server-sqlite|stdio|SQLite database operations and analysis
@modelcontextprotocol/server-filesystem|stdio|Secure file operations with access controls
@modelcontextprotocol/server-playwright|stdio|Browser automation for E2E testing
@modelcontextprotocol/server-puppeteer|stdio|Browser automation and web scraping
@upstash/context7-mcp@latest|stdio|Up-to-date documentation for 9000+ libraries
@bytebase/dbhub|stdio|Multi-database access (Postgres, MySQL, SQLite)
@anthropic-ai/mcp-server-playwright@latest|stdio|Official Anthropic Playwright server
stitch-mcp|stdio|Google Stitch UI preview before coding
task-master-ai@latest|stdio|Task management and project orchestration
semgrep-mcp|uvx|Static analysis and security scanning
mongodb-lens|stdio|MongoDB database management and querying
mcp-server-duckdb|pip|DuckDB analytics database access
k8s-mcp-server|pip|Kubernetes cluster operations
chroma-mcp|pip|ChromaDB vector database for RAG
elasticsearch-mcp-server|pip|Elasticsearch full-text search
mcp-server-bigquery|pip|Google BigQuery data warehouse
postman-mcp-server|http|Postman API testing integration
brave-search-mcp-server|stdio|Brave web search API
mermaid-mcp|stdio|Generate 22+ diagram types
@cloudflare/mcp-server-cloudflare|stdio|Cloudflare Workers, KV, R2, D1
EOF

  log_dim "  $(wc -l < "$cache_file") verified MCP servers in known list"
}

fetch_skills() {
  local cache_file="$REMOTE_CACHE/known-skills.txt"

  # Known high-quality Claude Code skills
  cat > "$cache_file" << 'EOF'
ui-ux-pro-max|nextlevelbuilder/ui-ux-pro-max-skill|UI/UX design intelligence (161 rules, 67 styles, 57 fonts)
commit-skill|anthropics/claude-code|Structured git commit workflow
review-pr-skill|anthropics/claude-code|Pull request review workflow
EOF

  log_dim "  $(wc -l < "$cache_file") known skills"
}

print_discoveries() {
  echo ""
  echo -e "${BOLD}Available MCP Servers (verified):${NC}"
  echo ""

  if [ -f "$REMOTE_CACHE/known-mcps.txt" ]; then
    while IFS='|' read -r package transport desc; do
      [ -z "$package" ] && continue
      # Check if already in our catalog
      if grep -q "$package" "$CATALOG_FILE" 2>/dev/null; then
        echo -e "  ${DIM}✓ $package — already in catalog${NC}"
      else
        echo -e "  ${CYAN}+ $package${NC} ($transport)"
        echo -e "    ${DIM}$desc${NC}"
      fi
    done < "$REMOTE_CACHE/known-mcps.txt"
  fi

  echo ""
  echo -e "${BOLD}New from npm (not yet in catalog):${NC}"
  echo ""

  if [ -f "$REMOTE_CACHE/npm-mcps.txt" ]; then
    sort -u "$REMOTE_CACHE/npm-mcps.txt" | while IFS='|' read -r name version desc; do
      [ -z "$name" ] && continue
      if ! grep -q "$name" "$CATALOG_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}$name${NC} v$version"
        echo -e "    ${DIM}$desc${NC}"
      fi
    done | head -40
  fi

  echo ""
  echo -e "${BOLD}To install a discovered MCP:${NC}"
  echo -e "  tasuki install mcp <name>"
  echo ""
  echo -e "${BOLD}To add a new MCP to the catalog permanently:${NC}"
  echo -e "  Edit: $CATALOG_FILE"
  echo ""
}

# --- Main ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  update_catalog "$@"
fi
