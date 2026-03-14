#!/bin/bash
# Tasuki Engine — Memory Vault (Knowledge Graph)
# A structured memory system where each memory is a node, and wikilinks create edges.
# Replaces the flat agent-memory/ system with a graph-navigable vault.
#
# Node types: agents, skills, bugs, heuristics, lessons, architecture, tools, decisions
# Each node is a separate .md file with wikilinks [[like-this]] to other nodes.
#
# Usage: source this file, then call vault functions
#   or:  bash vault.sh <init|add|search|stats> [args...]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

# --- Initialize vault ---
vault_init() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ -d "$vault" ] && [ -f "$vault/index.md" ]; then
    log_dim "  memory-vault/ already exists"
    return 0
  fi

  log_info "Initializing memory vault..."

  # Create node type directories
  mkdir -p "$vault"/{agents,skills,bugs,heuristics,lessons,architecture,tools,decisions,stack}

  # Create index
  local project_name
  project_name=$(basename "$project_dir")
  local date
  date=$(date '+%Y-%m-%d')

  cat > "$vault/index.md" << EOF
# Memory Vault — $project_name

Knowledge graph for the $project_name project. Each file is a node, [[wikilinks]] are edges.

## Node Types

| Type | Path | Purpose |
|------|------|---------|
| Agents | agents/ | Agent capabilities, what they own, what they've learned |
| Skills | skills/ | Available skills and when to use them |
| Bugs | bugs/ | Bug reports with root cause, fix, and prevention |
| Heuristics | heuristics/ | Reusable rules learned from experience |
| Lessons | lessons/ | Insights gained from implementation |
| Architecture | architecture/ | System design decisions and patterns |
| Tools | tools/ | Frameworks, libraries, MCPs in use |
| Decisions | decisions/ | Technical decisions with context and reasoning |
| Stack | stack/ | Technology stack nodes (languages, frameworks, DBs) |

## How to Navigate

- Open in Obsidian for visual graph navigation
- Use \`tasuki vault search <term>\` to find nodes
- Use \`tasuki vault stats\` to see graph metrics
- Wikilinks \`[[node-name]]\` connect related knowledge

## Recent Activity
<!-- Auto-updated when nodes are added -->

_Created: ${date}_
EOF

  # Seed agent nodes from installed agents
  seed_agent_nodes "$project_dir"

  # Seed stack nodes from detection
  seed_stack_nodes "$project_dir"

  # Seed tool nodes from MCPs
  seed_tool_nodes "$project_dir"

  # Seed initial heuristics (universal best practices)
  seed_heuristics "$vault"

  log_success "  Memory vault initialized"
}

# --- Seed agent nodes ---
seed_agent_nodes() {
  local project_dir="$1"
  local vault="$project_dir/memory-vault"

  if [ ! -d "$project_dir/.tasuki/agents" ]; then
    return
  fi

  for agent_file in "$project_dir/.tasuki/agents"/*.md; do
    [ -f "$agent_file" ] || continue
    local name
    name=$(basename "$agent_file" .md)
    [ "$name" = "onboard" ] && continue

    local node="$vault/agents/${name}.md"
    [ -f "$node" ] && continue

    # Read domains from frontmatter
    local domains=""
    domains=$(grep "^domains:" "$agent_file" 2>/dev/null | head -1 | sed 's/^domains:\s*//' | sed 's/\[//;s/\]//')
    local model=""
    model=$(grep "^model:" "$agent_file" 2>/dev/null | head -1 | sed 's/^model:\s*//')

    cat > "$node" << EOF
# $name

Type: Agent
Model: $model

## Responsibilities
$domains

## Uses
$(generate_tool_links "$name")

## Skills
$(generate_skill_links "$name")

## Lessons Learned
<!-- Added automatically by the agent after tasks -->

## Bugs Found
<!-- Links to bug nodes discovered by this agent -->

## Heuristics
<!-- Links to heuristic nodes this agent follows -->
EOF
    log_dim "  agents/$name"
  done
}

generate_tool_links() {
  local agent="$1"
  case "$agent" in
    backend-dev)  echo "- [[fastapi]]
- [[postgres]]
- [[context7-mcp]]" ;;
    frontend-dev) echo "- [[figma-mcp]]
- [[stitch-mcp]]
- [[playwright-mcp]]" ;;
    db-architect) echo "- [[postgres]]
- [[postgres-mcp]]" ;;
    security)     echo "- [[semgrep-mcp]]
- [[sentry-mcp]]" ;;
    devops)       echo "- [[docker]]
- [[github-mcp]]
- [[sentry-mcp]]" ;;
    debugger)     echo "- [[sentry-mcp]]
- [[postgres-mcp]]" ;;
    planner)      echo "- [[taskmaster-mcp]]" ;;
    reviewer)     echo "- [[semgrep-mcp]]
- [[context7-mcp]]" ;;
    qa)           echo "- [[playwright-mcp]]
- [[context7-mcp]]" ;;
    *)            echo "- (none)" ;;
  esac
}

generate_skill_links() {
  local agent="$1"
  case "$agent" in
    frontend-dev) echo "- [[ui-design]]
- [[ui-ux-pro-max]]" ;;
    planner)      echo "- [[tasuki-plans]]" ;;
    *)            echo "- [[context-compress]]" ;;
  esac
}

# --- Seed stack nodes ---
seed_stack_nodes() {
  local project_dir="$1"
  local vault="$project_dir/memory-vault"

  # Read from capability map or detection
  if [ -f "$project_dir/.tasuki/config/capability-map.yaml" ]; then
    # Create nodes for detected tech
    local techs=()

    # Check for common stack elements from generated files
    grep -l "fastapi\|django\|express\|nextjs\|rails\|gin" "$project_dir/.tasuki/agents"/*.md 2>/dev/null | while read -r f; do
      true  # just checking existence
    done

    # Create based on what we find in TASUKI.md
    if [ -f "$project_dir/TASUKI.md" ]; then
      grep -oE 'fastapi|django|express|nextjs|sveltekit|rails|gin|postgres|mysql|mongodb|redis|docker' "$project_dir/TASUKI.md" 2>/dev/null | sort -u | while read -r tech; do
        local node="$vault/stack/${tech}.md"
        [ -f "$node" ] && continue
        cat > "$node" << EOF
# $tech

Type: Stack

## Used By
$(grep -rl "$tech" "$project_dir/.tasuki/agents/" 2>/dev/null | while read -r f; do echo "- [[$(basename "$f" .md)]]"; done)

## Related Heuristics
<!-- Links to heuristics specific to this technology -->

## Known Issues
<!-- Links to bugs related to this technology -->
EOF
        log_dim "  stack/$tech"
      done
    fi
  fi
}

# --- Seed tool nodes (MCPs) ---
seed_tool_nodes() {
  local project_dir="$1"
  local vault="$project_dir/memory-vault"

  if [ ! -f "$project_dir/.mcp.json" ]; then
    return
  fi

  # Parse MCP names from .mcp.json
  grep -oE '"[a-z0-9_-]+"[[:space:]]*:' "$project_dir/.mcp.json" 2>/dev/null | grep -v "mcpServers\|type\|command\|args\|url\|env\|timeout" | sed 's/"//g;s/://' | sed 's/[[:space:]]//g' | while read -r mcp; do
    [ -z "$mcp" ] && continue
    local node="$vault/tools/${mcp}-mcp.md"
    [ -f "$node" ] && continue

    cat > "$node" << EOF
# ${mcp} MCP

Type: Tool
Category: MCP Server

## Purpose
$(get_mcp_purpose "$mcp")

## Used By
$(get_mcp_agents "$mcp")

## Configuration
Defined in \`.mcp.json\`
EOF
    log_dim "  tools/${mcp}-mcp"
  done
}

get_mcp_purpose() {
  case "$1" in
    context7)     echo "Up-to-date documentation for frameworks and libraries" ;;
    github)       echo "GitHub integration — PRs, issues, actions, releases" ;;
    sentry)       echo "Error tracking, monitoring, and incident alerting" ;;
    semgrep)      echo "Static analysis and security pattern scanning" ;;
    taskmaster-ai|taskmaster) echo "Task management and project orchestration" ;;
    postgres)     echo "Direct database access for schema inspection and queries" ;;
    figma)        echo "Design specs, colors, typography from Figma files" ;;
    stitch)       echo "UI preview with Google Stitch before coding" ;;
    playwright)   echo "Browser automation for E2E testing" ;;
    *)            echo "MCP server: $1" ;;
  esac
}

get_mcp_agents() {
  case "$1" in
    context7)     echo "- [[planner]]
- [[backend-dev]]
- [[frontend-dev]]
- [[qa]]" ;;
    github)       echo "- [[reviewer]]
- [[devops]]" ;;
    sentry)       echo "- [[debugger]]
- [[devops]]" ;;
    semgrep)      echo "- [[security]]
- [[reviewer]]" ;;
    taskmaster*)  echo "- [[planner]]" ;;
    postgres)     echo "- [[db-architect]]
- [[debugger]]" ;;
    figma)        echo "- [[frontend-dev]]" ;;
    stitch)       echo "- [[frontend-dev]]" ;;
    playwright)   echo "- [[qa]]
- [[frontend-dev]]" ;;
    *)            echo "- (configure in agent templates)" ;;
  esac
}

# --- Seed universal heuristics ---
seed_heuristics() {
  local vault="$1"

  # Only seed if empty
  if [ "$(find "$vault/heuristics" -name "*.md" 2>/dev/null | wc -l)" -gt 0 ]; then
    return
  fi

  local seed_date
  seed_date=$(date '+%Y-%m-%d')

  # Write heuristics via Python to avoid heredoc/bash expansion issues
  python3 - "$vault" "$seed_date" << 'PYEOF'
import sys, os
vault = sys.argv[1]
seed_date = sys.argv[2]
hdir = os.path.join(vault, 'heuristics')
os.makedirs(hdir, exist_ok=True)

files = {
"always-index-lookup-columns.md": f"""# Always Index Lookup Columns

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[db-architect]]
- [[backend-dev]]
- [[reviewer]]

## Rule
Every column used in WHERE, JOIN, or ORDER BY clauses must have a database index.

## Reason
Queries without indexes cause full table scans. On tables with >10K rows, this means seconds instead of milliseconds.

## Anti-Pattern
```
-- No index on email → full table scan
SELECT * FROM users WHERE email = 'user@example.com';
```

## Correct Pattern
```
CREATE INDEX idx_users_email ON users(email);
```

## Related
- [[postgres]]
""",

"never-trust-client-input.md": f"""# Never Trust Client Input

Type: Heuristic
Severity: CRITICAL
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[backend-dev]]
- [[security]]
- [[reviewer]]

## Rule
Validate and sanitize ALL user input at the API boundary. Never pass raw input to queries, file operations, or shell commands.

## Enforcement
The Security agent runs OWASP checks. The security-check hook scans for common injection patterns.

## Related
- [[always-use-parameterized-queries]]
- [[security]]
""",

"always-use-parameterized-queries.md": f"""# Always Use Parameterized Queries

Type: Heuristic
Severity: CRITICAL
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[db-architect]]
- [[backend-dev]]
- [[security]]

## Rule
Never use string interpolation or concatenation in SQL queries. Always use parameterized bindings.

## Anti-Pattern
```
# VULNERABLE — SQL injection
db.execute(f"SELECT * FROM users WHERE id = {{user_id}}")
```

## Correct Pattern
```
# SAFE — parameterized
db.execute("SELECT * FROM users WHERE id = :id", {{"id": user_id}})
```

## Related
- [[never-trust-client-input]]
- [[postgres]]
""",

"tests-before-code.md": f"""# Tests Before Code (TDD)

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[qa]]
- [[backend-dev]]
- [[frontend-dev]]
- [[reviewer]]

## Rule
Write failing tests FIRST, then implement code to make them pass. Never the other way around.

## Reason
- Forces you to think about behavior before implementation
- Catches regressions automatically
- Serves as living documentation
- Prevents untestable code

## Enforcement
The TDD Guard hook (tdd-guard.sh) blocks edits to implementation files if no test file exists.

## Related
- [[qa]]
""",

"handle-all-ui-states.md": f"""# Handle All UI States

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[frontend-dev]]
- [[reviewer]]

## Rule
Every UI component must handle ALL states: loading, error, empty, success, disabled.

## Anti-Pattern
```
// Only shows data — crashes or shows blank on error/loading
<UserList users={{data}} />
```

## Correct Pattern
```
if loading: <Skeleton />
else if error: <ErrorMessage />
else if data.length === 0: <EmptyState />
else: <UserList users={{data}} />
```

## Related
- [[ui-design]]
- [[ui-ux-pro-max]]
"""
}

for name, content in files.items():
    with open(os.path.join(hdir, name), 'w') as f:
        f.write(content.strip() + '\n')
PYEOF

  if [ $? -ne 0 ]; then
    log_warn "  Failed to seed heuristics (python3 required)"
  fi

  log_dim "  5 universal heuristics seeded"
}


# --- Add a note to the vault ---
vault_add() {
  local project_dir="${1:-.}"
  local node_type="$2"    # bugs, lessons, heuristics, decisions, architecture
  local slug="$3"         # kebab-case name
  local title="$4"        # Human-readable title
  local content="$5"      # Markdown body with [[wikilinks]]

  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"
  local node="$vault/$node_type/$slug.md"

  if [ -z "$node_type" ] || [ -z "$slug" ]; then
    log_error "Usage: vault add <type> <slug> <title> <content>"
    log_error "Types: bugs, lessons, heuristics, decisions, architecture"
    return 1
  fi

  mkdir -p "$vault/$node_type"

  local date
  date=$(date '+%Y-%m-%d')

  cat > "$node" << EOF
# $title

Type: $(echo "$node_type" | sed 's/s$//' | sed 's/^./\U&/')
Created: $date
Confidence: high
Last-Validated: $date
Applied-Count: 0

$content
EOF

  # Update index with recent activity
  if [ -f "$vault/index.md" ]; then
    local entry="- [$date] [[$slug]] ($node_type)"
    # Append after "## Recent Activity"
    if grep -q "## Recent Activity" "$vault/index.md" 2>/dev/null; then
      sed -i "/## Recent Activity/a\\$entry" "$vault/index.md"
    fi
  fi

  log_success "Added: $node_type/$slug"
  log_dim "  $node"
}

# --- Search the vault ---
vault_search() {
  local project_dir="${1:-.}"
  local query="$2"

  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ -z "$query" ]; then
    log_error "Usage: vault search <query>"
    return 1
  fi

  echo ""
  echo -e "${BOLD}Vault Search: $query${NC}"
  echo ""

  # Search file content
  local results
  results=$(grep -rl "$query" "$vault" --include="*.md" 2>/dev/null || true)

  if [ -z "$results" ]; then
    echo -e "  ${DIM}No results found${NC}"
    return
  fi

  echo "$results" | while read -r file; do
    local rel_path="${file#$vault/}"
    local title
    title=$(head -1 "$file" | sed 's/^#\s*//')
    local type
    type=$(echo "$rel_path" | cut -d/ -f1)
    echo -e "  ${GREEN}$type/${NC} ${BOLD}$title${NC}"
    echo -e "  ${DIM}$rel_path${NC}"

    # Show matching lines
    grep -n "$query" "$file" 2>/dev/null | head -3 | while read -r line; do
      echo -e "    ${DIM}$line${NC}"
    done
    echo ""
  done
}

# --- Graph expansion (contextual reasoning) ---
# Expands a node by following wikilinks N levels deep.
# Returns related memories the agent didn't explicitly ask for.
# Usage: vault_expand <project_dir> <node-name> [depth]
vault_expand() {
  local project_dir="${1:-.}"
  local node="$2"
  local depth="${3:-}"

  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ -z "$node" ]; then
    log_error "Usage: vault expand <node-name> [depth]"
    return 1
  fi

  if [ ! -d "$vault" ]; then
    return 0
  fi

  # Auto-detect depth and confidence filter from project mode
  local mode_file="$project_dir/.tasuki/config/mode"
  local mode="standard"
  [ -f "$mode_file" ] && mode=$(cat "$mode_file" 2>/dev/null || echo "standard")

  if [ -z "$depth" ]; then
    case "$mode" in
      fast)    depth=0 ;;
      serious) depth=2 ;;
      *)       depth=1 ;;
    esac
  fi

  # Confidence filter: fast=high only, standard=high+experimental, serious=all
  local confidence_filter="high,experimental"
  case "$mode" in
    fast)    confidence_filter="high" ;;
    serious) confidence_filter="high,experimental,deprecated" ;;
    *)       confidence_filter="high,experimental" ;;
  esac

  # Build graph in memory first (one pass), then BFS — O(V+E)
  python3 << PYEOF
import os, re
from collections import defaultdict, deque

vault = "$vault"
start = "$node"
max_depth = $depth
allowed_confidence = set("$confidence_filter".split(","))

# --- Step 1: Build graph in memory (single os.walk) ---
nodes = {}       # name → {type, summary, links, confidence}
reverse = defaultdict(set)  # name → set of nodes that reference it

for root, dirs, files in os.walk(vault):
    for f in files:
        if not f.endswith('.md') or f == 'index.md':
            continue
        fpath = os.path.join(root, f)
        fname = f.replace('.md', '')
        rel = os.path.relpath(fpath, vault)
        ntype = rel.split('/')[0]

        try:
            with open(fpath) as fh:
                content = fh.read()
        except:
            continue

        # Extract confidence level
        confidence = 'high'  # default
        conf_match = re.search(r'Confidence:\s*(\w+)', content)
        if conf_match:
            confidence = conf_match.group(1).lower()

        # Extract applied count
        applied = 0
        applied_match = re.search(r'Applied-Count:\s*(\d+)', content)
        if applied_match:
            applied = int(applied_match.group(1))

        # Extract summary (first non-header, non-metadata line)
        lines = [l.strip() for l in content.split('\n')
                 if l.strip() and not l.startswith('#') and l.strip() != '---'
                 and not l.startswith('Type:') and not l.startswith('Confidence:')
                 and not l.startswith('Last-Validated:') and not l.startswith('Applied-Count:')
                 and not l.startswith('Severity:') and not l.startswith('Created:')]
        summary = lines[0][:120] if lines else fname

        # Extract outgoing wikilinks
        links = set(re.findall(r'\[\[([a-z0-9_-]+)\]\]', content))

        nodes[fname] = {
            'type': ntype, 'summary': summary, 'links': links,
            'confidence': confidence, 'applied': applied
        }

        # Build reverse index
        for link in links:
            reverse[link].add(fname)

# --- Step 2: BFS traversal from start node — O(V+E) ---
visited = set()
queue = deque([(start, 0)])
results = []

while queue:
    current, depth = queue.popleft()
    if current in visited or depth > max_depth:
        continue
    visited.add(current)

    # Get neighbors: outgoing links + nodes that reference this one
    neighbors = set()
    if current in nodes:
        neighbors |= nodes[current]['links']
    neighbors |= reverse.get(current, set())

    for neighbor in neighbors:
        if neighbor in visited:
            continue
        if neighbor in nodes:
            n = nodes[neighbor]
            # Filter by confidence
            if n['confidence'] not in allowed_confidence:
                continue
            conf_badge = ''
            if n['confidence'] == 'experimental':
                conf_badge = ' [experimental]'
            elif n['confidence'] == 'deprecated':
                conf_badge = ' [deprecated]'
            applied_badge = f" (applied {n['applied']}x)" if n['applied'] > 0 else ''
            results.append({
                'type': n['type'],
                'name': neighbor,
                'summary': n['summary'],
                'confidence': n['confidence'],
                'badge': conf_badge + applied_badge,
                'depth': depth + 1
            })
        if depth + 1 < max_depth:
            queue.append((neighbor, depth + 1))

# --- Step 3: Output ---
# Deduplicate and exclude start node
seen = set()
unique = []
for r in results:
    if r['name'] not in seen and r['name'] != start:
        seen.add(r['name'])
        unique.append(r)

if unique:
    print(f"  Graph expansion for [[{start}]] (depth={max_depth}, mode={allowed_confidence}):")
    for r in sorted(unique, key=lambda x: (x['depth'], x['type'])):
        indent = "    " + ("  " * r['depth'])
        print(f"{indent}[{r['type']}] {r['name']}: {r['summary']}{r['badge']}")

    # Log heuristics loaded to activity + increment Applied-Count
    af = os.path.join("$project_dir", ".tasuki/config/activity-log.json")
    heuristics_loaded = [r for r in unique if r['type'] == 'heuristics']

    # Filter: only count heuristics that directly reference the calling agent
    # A heuristic with [[backend-dev]] counts for backend-dev, not for frontend-dev
    applied_heuristics = []
    for h in heuristics_loaded:
        hfile = None
        for root, dirs, files in os.walk("$vault"):
            for f in files:
                if f == h['name'] + '.md':
                    hfile = os.path.join(root, f)
                    break
            if hfile: break
        if hfile:
            try:
                with open(hfile) as fh:
                    hcontent = fh.read()
                # Only count if heuristic directly references this agent
                if '[[' + start + ']]' in hcontent:
                    applied_heuristics.append(h)
                    h['_direct'] = True
                else:
                    h['_direct'] = False
            except:
                h['_direct'] = False
        else:
            h['_direct'] = False

    if applied_heuristics and os.path.exists(af):
        import json as jjson
        try:
            with open(af) as fh:
                adata = jjson.load(fh)
            for h in applied_heuristics:
                adata['events'].append({
                    'time': __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    'type': 'heuristic_loaded',
                    'agent': start,
                    'detail': f"Applied: {h['name']} — {h['summary'][:60]}"
                })
            adata['events'] = adata['events'][-100:]
            with open(af, 'w') as fh:
                jjson.dump(adata, fh, indent=2)
        except: pass

    # Increment Applied-Count only for directly relevant heuristics
    for h in applied_heuristics:
        hfile = None
        for root, dirs, files in os.walk("$vault"):
            for f in files:
                if f == h['name'] + '.md':
                    hfile = os.path.join(root, f)
                    break
            if hfile: break
        if hfile:
            try:
                with open(hfile) as fh:
                    content = fh.read()
                m = __import__('re').search(r'Applied-Count:\s*(\d+)', content)
                if m:
                    count = int(m.group(1)) + 1
                    content = __import__('re').sub(r'Applied-Count:\s*\d+', f'Applied-Count: {count}', content)
                    with open(hfile, 'w') as fh:
                        fh.write(content)
            except: pass
PYEOF
}

# --- Update confidence of a memory ---
# Usage: vault_confidence <project_dir> <node-name> <high|experimental|deprecated>
vault_confidence() {
  local project_dir="${1:-.}"
  local node_name="$2"
  local new_confidence="$3"

  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ -z "$node_name" ] || [ -z "$new_confidence" ]; then
    log_error "Usage: vault confidence <node-name> <high|experimental|deprecated>"
    return 1
  fi

  case "$new_confidence" in
    high|experimental|deprecated) ;;
    *) log_error "Invalid confidence: $new_confidence (use: high, experimental, deprecated)"; return 1 ;;
  esac

  # Find the file
  local node_file
  node_file=$(find "$vault" -name "$node_name.md" 2>/dev/null | head -1)

  if [ -z "$node_file" ]; then
    log_error "Node not found: $node_name"
    return 1
  fi

  # Update confidence and last-validated
  local today
  today=$(date '+%Y-%m-%d')

  if grep -q "Confidence:" "$node_file" 2>/dev/null; then
    sed -i "s/Confidence:.*/Confidence: $new_confidence/" "$node_file"
  else
    sed -i "/^Type:/a Confidence: $new_confidence" "$node_file"
  fi

  if grep -q "Last-Validated:" "$node_file" 2>/dev/null; then
    sed -i "s/Last-Validated:.*/Last-Validated: $today/" "$node_file"
  else
    sed -i "/Confidence:/a Last-Validated: $today" "$node_file"
  fi

  log_success "Updated $node_name → confidence: $new_confidence"
}

# --- Increment applied count (called by agents after using a heuristic) ---
vault_applied() {
  local project_dir="${1:-.}"
  local node_name="$2"

  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  local node_file
  node_file=$(find "$vault" -name "$node_name.md" 2>/dev/null | head -1)
  [ -z "$node_file" ] && return 0

  if grep -q "Applied-Count:" "$node_file" 2>/dev/null; then
    local current
    current=$(grep "Applied-Count:" "$node_file" | grep -oP '\d+' || echo "0")
    local new_count=$((current + 1))
    sed -i "s/Applied-Count:.*/Applied-Count: $new_count/" "$node_file"
  fi
}

# --- Auto-decay: demote/promote memories based on age and usage ---
# Runs as part of vault sync or doctor. No cron needed.
# Rules:
#   high + 90 days no validate/apply → experimental
#   experimental + 60 days → deprecated
#   deprecated + 30 days → archived (moved to memory-vault/archive/)
#   experimental + applied 3+ times → promoted to high
vault_decay() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  [ ! -d "$vault" ] && return 0

  local today
  today=$(date '+%Y-%m-%d')
  local changes=0

  python3 << PYEOF
import os, re, sys
from datetime import datetime, timedelta

vault = "$vault"
today = datetime.strptime("$today", "%Y-%m-%d")
changes = 0
promoted = 0
archived = 0

# Thresholds
HIGH_TO_EXPERIMENTAL_DAYS = 90
EXPERIMENTAL_TO_DEPRECATED_DAYS = 60
DEPRECATED_TO_ARCHIVE_DAYS = 30
PROMOTE_THRESHOLD = 3  # applied count to promote experimental → high

archive_dir = os.path.join(vault, "archive")

for root, dirs, files in os.walk(vault):
    # Skip archive directory
    if "archive" in root:
        continue
    for f in files:
        if not f.endswith('.md') or f == 'index.md':
            continue
        fpath = os.path.join(root, f)
        fname = f.replace('.md', '')
        rel = os.path.relpath(fpath, vault)
        ntype = rel.split('/')[0]

        # Only decay heuristics, bugs, lessons, decisions
        if ntype not in ('heuristics', 'bugs', 'lessons', 'decisions'):
            continue

        try:
            with open(fpath) as fh:
                content = fh.read()
        except:
            continue

        # Parse metadata
        conf_match = re.search(r'Confidence:\s*(\w+)', content)
        confidence = conf_match.group(1).lower() if conf_match else 'high'

        date_match = re.search(r'Last-Validated:\s*(\d{4}-\d{2}-\d{2})', content)
        if date_match:
            last_validated = datetime.strptime(date_match.group(1), "%Y-%m-%d")
        else:
            # Use file mtime as fallback
            last_validated = datetime.fromtimestamp(os.path.getmtime(fpath))

        applied_match = re.search(r'Applied-Count:\s*(\d+)', content)
        applied = int(applied_match.group(1)) if applied_match else 0

        days_since = (today - last_validated).days
        new_confidence = confidence

        # --- Promotion: experimental with 3+ applies → high ---
        if confidence == 'experimental' and applied >= PROMOTE_THRESHOLD:
            new_confidence = 'high'
            promoted += 1

        # --- Demotion based on age ---
        elif confidence == 'high' and days_since > HIGH_TO_EXPERIMENTAL_DAYS:
            new_confidence = 'experimental'
            changes += 1

        elif confidence == 'experimental' and days_since > EXPERIMENTAL_TO_DEPRECATED_DAYS:
            new_confidence = 'deprecated'
            changes += 1

        elif confidence == 'deprecated' and days_since > DEPRECATED_TO_ARCHIVE_DAYS:
            # Archive: move to memory-vault/archive/
            os.makedirs(archive_dir, exist_ok=True)
            dest = os.path.join(archive_dir, f)
            os.rename(fpath, dest)
            archived += 1
            print(f"  archived: {ntype}/{fname} (deprecated for {days_since} days)")
            continue

        # Update file if confidence changed
        if new_confidence != confidence:
            if 'Confidence:' in content:
                content = re.sub(r'Confidence:\s*\w+', f'Confidence: {new_confidence}', content)
            else:
                content = content.replace('Type:', f'Confidence: {new_confidence}\nType:', 1)

            # Update Last-Validated on promotion
            if new_confidence == 'high' and confidence == 'experimental':
                content = re.sub(r'Last-Validated:\s*\d{4}-\d{2}-\d{2}',
                                 f'Last-Validated: {today.strftime("%Y-%m-%d")}', content)

            with open(fpath, 'w') as fh:
                fh.write(content)

            direction = "promoted" if new_confidence == 'high' else "demoted"
            print(f"  {direction}: {ntype}/{fname} ({confidence} → {new_confidence}, {days_since}d since validation, {applied}x applied)")

total = changes + promoted + archived
if total == 0:
    print("  All memories up to date. No decay needed.")
else:
    print(f"  Summary: {changes} demoted, {promoted} promoted, {archived} archived")
PYEOF
}

# --- Vault stats ---
vault_stats() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ ! -d "$vault" ]; then
    log_error "No memory vault found. Run: tasuki onboard"
    return 1
  fi

  echo ""
  echo -e "${BOLD}Memory Vault Statistics${NC}"
  echo -e "${DIM}═══════════════════════${NC}"
  echo ""

  local total_nodes=0
  local total_links=0

  for type_dir in "$vault"/*/; do
    [ -d "$type_dir" ] || continue
    local type_name
    type_name=$(basename "$type_dir")
    local count
    count=$(find "$type_dir" -name "*.md" 2>/dev/null | wc -l)
    total_nodes=$((total_nodes + count))

    if [ "$count" -gt 0 ]; then
      echo -e "  ${GREEN}$count${NC} ${BOLD}$type_name${NC}"
    fi
  done

  # Count wikilinks
  total_links=$(grep -roE '\[\[[a-z0-9_-]+\]\]' "$vault" --include="*.md" 2>/dev/null | wc -l || echo 0)

  echo ""
  echo -e "  ${BOLD}Total nodes:${NC} $total_nodes"
  echo -e "  ${BOLD}Total links:${NC} $total_links"

  # Most connected nodes
  echo ""
  echo -e "  ${BOLD}Most connected nodes:${NC}"
  grep -roEh '\[\[[a-z0-9_-]+\]\]' "$vault" --include="*.md" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | while read -r count node; do
    node=$(echo "$node" | sed 's/\[\[//;s/\]\]//')
    echo -e "    ${GREEN}$count${NC} links → $node"
  done
  echo ""
}

# --- RAG Deep Memory Integration ---
# Syncs wikilink memories to RAG MCP for deep context retrieval.
# Wikilinks = fast index (always loaded, ~16 tokens per memory)
# RAG = deep memory (queried on-demand when agent needs full context)

vault_rag_sync() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"
  local json_file="$project_dir/.tasuki/config/rag-sync-batch.jsonl"

  if [ ! -d "$vault" ]; then
    log_error "No memory vault found. Run: tasuki vault init"
    return 1
  fi

  # Run auto-decay before syncing
  log_info "Running memory decay check..."
  vault_decay "$project_dir"

  # Check if rag-memory-mcp is configured
  local mcp_file="$project_dir/.mcp.json"
  if [ ! -f "$mcp_file" ] || ! grep -q "rag-memory" "$mcp_file" 2>/dev/null; then
    log_warn "RAG MCP not configured. Adding rag-memory-mcp..."
    vault_rag_setup "$project_dir"
  fi

  log_info "Syncing to RAG deep memory..."
  echo ""
  mkdir -p "$(dirname "$json_file")"
  > "$json_file"  # clear previous sync

  local synced=0

  # ── 1. MEMORY VAULT (wikilinks + full content) ──
  log_dim "  Indexing memory vault..."
  for node_file in $(find "$vault" -name "*.md" -not -name "index.md" 2>/dev/null); do
    [ -f "$node_file" ] || continue
    local rel_path node_type node_name tags
    rel_path=$(realpath --relative-to="$vault" "$node_file")
    node_type=$(dirname "$rel_path")
    node_name=$(basename "$node_file" .md)
    tags=$(grep -oE '\[\[[a-z0-9_-]+\]\]' "$node_file" 2>/dev/null | sed 's/\[\[//;s/\]\]//' | sort -u | tr '\n' ',' | sed 's/,$//')

    python3 -c "
import json, sys
content = open('$node_file').read()
entry = {'id': 'vault/$node_type/$node_name', 'type': '$node_type', 'name': '$node_name', 'tags': '$tags', 'content': content}
print(json.dumps(entry))
" >> "$json_file" 2>/dev/null
    synced=$((synced + 1))
  done
  log_dim "    $synced memories"

  # ── 2. DATABASE SCHEMA (tables, columns, relations) ──
  local schema_count=0
  log_dim "  Indexing database schema..."

  # Find model files: models.py, models/*.py, or any .py with Column/Model/Base
  python3 - "$project_dir" "$json_file" << 'PYEOF'
import os, sys, json, re

project = sys.argv[1]
json_file = sys.argv[2]
count = 0

exclude = {'node_modules', '.git', '__pycache__', '.venv', 'venv', '.tasuki', 'memory-vault'}

for root, dirs, files in os.walk(project):
    dirs[:] = [d for d in dirs if d not in exclude]
    for f in files:
        if not f.endswith('.py'): continue
        fpath = os.path.join(root, f)
        rel = os.path.relpath(fpath, project)

        # Match model files by path or content
        is_model = False
        if '/models/' in rel or '/models.py' in rel or '/entities/' in rel:
            is_model = True

        if not is_model:
            continue

        try:
            content = open(fpath).read()
        except:
            continue

        # Verify it actually has model definitions
        if not re.search(r'class \w+.*(?:Base|Model|db\.Model|DeclarativeBase)', content):
            continue

        models = re.findall(r'class (\w+)\(', content)
        columns = re.findall(r'Column\((\w+)', content)
        app_name = os.path.basename(os.path.dirname(fpath))

        entry = {
            'id': f'schema/{app_name}/{f.replace(".py","")}',
            'type': 'schema',
            'name': f'{app_name}/{f}' if f != 'models.py' else f'{app_name} models',
            'tags': ','.join(models[:10]),
            'content': content[:3000]
        }
        with open(json_file, 'a') as jf:
            jf.write(json.dumps(entry) + '\n')
        count += 1

# Also index recent migrations (last 10)
mig_files = []
for root, dirs, files in os.walk(project):
    dirs[:] = [d for d in dirs if d not in exclude]
    if 'migrations' in root or 'alembic' in root or 'versions' in root:
        for f in sorted(files):
            if f.endswith('.py') and f != '__init__.py':
                mig_files.append(os.path.join(root, f))

for fpath in mig_files[-10:]:
    try:
        content = open(fpath).read()[:2000]
    except:
        continue
    mig_name = os.path.basename(fpath).replace('.py', '')
    entry = {
        'id': f'schema/migrations/{mig_name}',
        'type': 'migration',
        'name': mig_name,
        'tags': 'schema,migration,database',
        'content': content
    }
    with open(json_file, 'a') as jf:
        jf.write(json.dumps(entry) + '\n')
    count += 1

PYEOF
  # Re-count from file
  schema_count=$(grep -cE '"type": "schema"|"type": "migration"' "$json_file" 2>/dev/null || echo "0")
  schema_count=$(echo "$schema_count" | tr -dc '0-9')
  schema_count=${schema_count:-0}
  synced=$((synced + schema_count))
  log_dim "    $schema_count schema files"

  # ── 3. API ROUTES (endpoints, views, serializers) ──
  local api_count=0
  log_dim "  Indexing API endpoints..."

  python3 - "$project_dir" "$json_file" << 'PYEOF'
import os, sys, json, re

project = sys.argv[1]
json_file = sys.argv[2]
count = 0

exclude = {'node_modules', '.git', '__pycache__', '.venv', 'venv', '.tasuki', 'memory-vault'}

for root, dirs, files in os.walk(project):
    dirs[:] = [d for d in dirs if d not in exclude]
    for f in files:
        if not f.endswith('.py') and not f.endswith('.ts'): continue
        fpath = os.path.join(root, f)
        rel = os.path.relpath(fpath, project)

        # Match API files by path
        is_api = False
        if any(p in rel for p in ['/routers/', '/views/', '/routes/', '/controllers/', '/endpoints/', '/serializers/', '/schemas/']):
            is_api = True

        if not is_api:
            continue

        try:
            content = open(fpath).read()
        except:
            continue

        # Verify it has route/endpoint definitions
        if not re.search(r'@router\.|@app\.|APIRouter|@Get|@Post|@Put|@Delete|class.*View|class.*Serializer', content):
            continue

        # Extract endpoints
        endpoints = re.findall(r'(?:@router|@app)\.\w+\(["\']([^"\']+)', content)
        app_name = os.path.basename(os.path.dirname(fpath))
        api_type = f.replace('.py', '').replace('.ts', '')

        entry = {
            'id': f'api/{app_name}/{api_type}',
            'type': 'api',
            'name': f'{app_name}/{api_type}',
            'tags': 'api,' + ','.join(endpoints[:5]),
            'content': content[:3000]
        }
        with open(json_file, 'a') as jf:
            jf.write(json.dumps(entry) + '\n')
        count += 1

PYEOF
  api_count=$(grep -c '"type": "api"' "$json_file" 2>/dev/null || echo "0")
  api_count=$(echo "$api_count" | tr -dc '0-9')
  api_count=${api_count:-0}
  synced=$((synced + api_count))
  log_dim "    $api_count API files"

  # ── 4. PIPELINE PLANS (PRDs, decisions) ──
  local plan_count=0
  log_dim "  Indexing pipeline plans..."

  for plan_file in $(find "$project_dir/tasuki-plans" -name "*.md" 2>/dev/null); do
    [ -f "$plan_file" ] || continue
    local plan_name
    plan_name=$(basename "$plan_file" .md)
    local feature_dir
    feature_dir=$(basename "$(dirname "$plan_file")")
    python3 -c "
import json
content = open('$plan_file').read()[:3000]
entry = {
    'id': 'plan/$feature_dir/$plan_name',
    'type': 'plan',
    'name': '$feature_dir — $plan_name',
    'tags': 'plan,$feature_dir,planner',
    'content': content
}
print(json.dumps(entry))
" >> "$json_file" 2>/dev/null
    plan_count=$((plan_count + 1))
  done
  synced=$((synced + plan_count))
  log_dim "    $plan_count plan files"

  # ── 5. GIT HISTORY (recent diffs as context) ──
  local git_count=0
  if [ -d "$project_dir/.git" ]; then
    log_dim "  Indexing recent git history..."
    python3 - "$project_dir" "$json_file" << 'PYEOF'
import subprocess, json, sys, os

project = sys.argv[1]
json_file = sys.argv[2]
os.chdir(project)

try:
    log = subprocess.run(['git', 'log', '--oneline', '-20'], capture_output=True, text=True, cwd=project)
    for line in log.stdout.strip().split('\n'):
        if not line.strip(): continue
        parts = line.split(' ', 1)
        sha = parts[0]
        msg = parts[1] if len(parts) > 1 else ''
        # Get diff stat
        try:
            diff = subprocess.run(['git', 'diff', f'{sha}~1', sha, '--stat'], capture_output=True, text=True, cwd=project)
            stat = diff.stdout[:1000]
        except:
            stat = ''
        if not stat: continue
        entry = {
            'id': f'git/{sha}',
            'type': 'commit',
            'name': f'{sha} — {msg[:80]}',
            'tags': 'git,commit,history',
            'content': f'{msg}\n\n{stat}'
        }
        with open(json_file, 'a') as f:
            f.write(json.dumps(entry) + '\n')
except:
    pass
PYEOF
    git_count=$(grep -c '"type": "commit"' "$json_file" 2>/dev/null || echo "0")
    synced=$((synced + git_count))
    log_dim "    $git_count commits"
  fi

  # ── 6. CONFIG FILES (settings, env structure, docker) ──
  local config_count=0
  log_dim "  Indexing config files..."

  for cfg_file in $(find "$project_dir" -maxdepth 2 \( -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o -name "docker-compose*" -o -name "Dockerfile" -o -name "*.ini" -o -name "pyproject.toml" -o -name "package.json" \) -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/.tasuki/*" 2>/dev/null | head -15); do
    [ -f "$cfg_file" ] || continue
    local cfg_name
    cfg_name=$(basename "$cfg_file")
    python3 -c "
import json
content = open('$cfg_file').read()[:2000]
entry = {
    'id': 'config/$cfg_name',
    'type': 'config',
    'name': '$cfg_name',
    'tags': 'config,infrastructure',
    'content': content
}
print(json.dumps(entry))
" >> "$json_file" 2>/dev/null
    config_count=$((config_count + 1))
  done
  synced=$((synced + config_count))
  log_dim "    $config_count config files"

  # ── SUMMARY ──
  echo ""
  log_success "RAG deep memory: $synced entries indexed"
  log_dim "  Database: .tasuki/config/rag-sync-batch.jsonl"
  echo ""
  echo -e "  ${BOLD}What's indexed:${NC}"
  echo -e "    ${GREEN}Memories${NC}     — heuristics, bugs, lessons, decisions"
  echo -e "    ${CYAN}Schema${NC}       — models, migrations, tables, columns"
  echo -e "    ${YELLOW}API${NC}          — views, routes, serializers, endpoints"
  echo -e "    ${BOLD}Plans${NC}        — PRDs, status, architectural decisions"
  echo -e "    ${DIM}Git${NC}          — recent commits and diffs"
  echo -e "    ${DIM}Config${NC}       — docker, settings, package.json"
  echo ""
  echo -e "  ${BOLD}How agents use it:${NC}"
  echo -e "    ${DIM}Layer 1: Wikilinks → always loaded → 4-line rule (~16 tokens)${NC}"
  echo -e "    ${DIM}Layer 2: RAG query → on-demand → full context (schema, diffs, incidents)${NC}"
  echo ""
}

vault_rag_setup() {
  local project_dir="${1:-.}"
  local mcp_file="$project_dir/.mcp.json"

  # Add rag-memory-mcp to .mcp.json
  if [ -f "$mcp_file" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$mcp_file') as f:
    data = json.load(f)
servers = data.get('mcpServers', {})
if 'rag-memory' not in servers:
    servers['rag-memory'] = {
        'command': 'npx',
        'args': ['-y', 'rag-memory-mcp'],
        'env': {
            'MEMORY_DB_PATH': '$project_dir/.tasuki/config/rag-memory.db'
        }
    }
    data['mcpServers'] = servers
    with open('$mcp_file', 'w') as f:
        json.dump(data, f, indent=2)
    print('  rag-memory-mcp added to .mcp.json')
else:
    print('  rag-memory-mcp already configured')
" 2>/dev/null
  fi
}

vault_rag_query() {
  local project_dir="${1:-.}"
  local query="$2"

  if [ -z "$query" ]; then
    echo "Usage: tasuki vault query \"search term\""
    return 1
  fi

  local batch_file="$project_dir/.tasuki/config/rag-sync-batch.jsonl"

  if [ ! -f "$batch_file" ]; then
    log_warn "No RAG data. Run: tasuki vault sync"
    return 1
  fi

  log_info "Searching RAG deep memory: \"$query\""
  echo ""

  # Search using python for reliable JSON parsing
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys

query = '$query'.lower()
results = []
with open('$batch_file') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            entry = json.loads(line)
            # Search in name, tags, content, type
            searchable = ' '.join([
                entry.get('name', ''),
                entry.get('tags', ''),
                entry.get('content', '')[:500],
                entry.get('type', '')
            ]).lower()
            if query in searchable:
                results.append(entry)
        except json.JSONDecodeError:
            continue

if not results:
    print('  No results found. Try different keywords.')
else:
    for r in results[:8]:
        typ = r.get('type', '?')
        name = r.get('name', 'unknown')
        rid = r.get('id', '')
        tags = r.get('tags', '')
        # Color by type
        colors = {'schema': '36', 'api': '33', 'plan': '35', 'config': '2', 'commit': '2'}
        c = colors.get(typ, '32')
        print(f'  \033[0;{c}m[{typ}]\033[0m \033[1m{name}\033[0m \033[2m({rid})\033[0m')
        if tags:
            print(f'    \033[2mlinks: {tags}\033[0m')
        # Show snippet of content
        content = r.get('content', '')
        snippet = ' '.join(content.split()[:20])
        if snippet:
            print(f'    \033[2m{snippet}...\033[0m')
" 2>/dev/null
  fi
  echo ""
}

# --- Team sync: push/pull shared knowledge via git ---
# Only syncs: heuristics, decisions, lessons (generalizable patterns)
# Does NOT sync: bugs, errors, agents, tools (context-specific)
# Uses a dedicated branch: tasuki-knowledge

SYNC_TYPES=("heuristics" "decisions" "lessons")

vault_push() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ ! -d "$vault" ]; then
    log_error "No memory vault found. Run: tasuki onboard"
    return 1
  fi

  # Check we're in a git repo
  if ! git -C "$project_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    log_error "Not a git repository. vault push requires git."
    return 1
  fi

  local current_branch
  current_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null)
  local knowledge_branch="tasuki-knowledge"

  echo ""
  echo -e "${BOLD}Tasuki Vault Push${NC}"
  echo -e "${DIM}Syncing shared knowledge to $knowledge_branch branch${NC}"
  echo ""

  # Create knowledge branch if it doesn't exist
  if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$knowledge_branch" 2>/dev/null; then
    # Create orphan branch (no shared history with main)
    git -C "$project_dir" checkout --orphan "$knowledge_branch" &>/dev/null
    git -C "$project_dir" rm -rf . &>/dev/null 2>&1
    git -C "$project_dir" commit --allow-empty -m "Initialize tasuki-knowledge branch" &>/dev/null
    git -C "$project_dir" checkout "$current_branch" &>/dev/null
    log_dim "  Created branch: $knowledge_branch"
  fi

  # Copy shareable memories to a temp dir
  local temp_dir
  temp_dir=$(mktemp -d)
  local copied=0

  for type in "${SYNC_TYPES[@]}"; do
    if [ -d "$vault/$type" ]; then
      local count=0
      mkdir -p "$temp_dir/$type"
      for f in "$vault/$type"/*.md; do
        [ -f "$f" ] || continue
        local fname
        fname=$(basename "$f")

        # Skip -team suffix files (temporary merge artifacts)
        case "$fname" in
          *-team.md) continue ;;
        esac

        # Only push high confidence memories
        if grep -q "Confidence: high" "$f" 2>/dev/null || ! grep -q "Confidence:" "$f" 2>/dev/null; then
          cp "$f" "$temp_dir/$type/"
          count=$((count + 1))
          copied=$((copied + 1))
        fi
      done
      if [ "$count" -gt 0 ]; then
        log_dim "  $type: $count memories"
      fi
    fi
  done

  if [ "$copied" -eq 0 ]; then
    log_warn "  No shareable memories to push"
    rm -rf "$temp_dir"
    return 0
  fi

  # Switch to knowledge branch, copy files, commit, switch back
  git -C "$project_dir" stash &>/dev/null 2>&1
  git -C "$project_dir" checkout "$knowledge_branch" &>/dev/null

  # Copy memories
  for type in "${SYNC_TYPES[@]}"; do
    if [ -d "$temp_dir/$type" ]; then
      mkdir -p "$project_dir/$type"
      cp "$temp_dir/$type"/*.md "$project_dir/$type/" 2>/dev/null
      git -C "$project_dir" add "$type/" &>/dev/null
    fi
  done

  # Commit
  local author
  author=$(git -C "$project_dir" config user.name 2>/dev/null || echo "unknown")
  local commit_msg="vault push: $copied memories from $author ($(date '+%Y-%m-%d %H:%M'))"

  if git -C "$project_dir" diff --cached --quiet 2>/dev/null; then
    log_dim "  No changes to push (already up to date)"
  else
    git -C "$project_dir" commit -m "$commit_msg" &>/dev/null
    log_success "  Pushed $copied memories to $knowledge_branch"

    # Push to remote if it exists
    if git -C "$project_dir" remote get-url origin &>/dev/null 2>&1; then
      git -C "$project_dir" push origin "$knowledge_branch" &>/dev/null 2>&1 && \
        log_dim "  Pushed to remote" || \
        log_warn "  Could not push to remote (push manually: git push origin $knowledge_branch)"
    fi
  fi

  # Switch back
  git -C "$project_dir" checkout "$current_branch" &>/dev/null
  git -C "$project_dir" stash pop &>/dev/null 2>&1

  rm -rf "$temp_dir"
  echo ""
}

vault_pull() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local vault="$project_dir/memory-vault"

  if [ ! -d "$vault" ]; then
    log_error "No memory vault found. Run: tasuki onboard"
    return 1
  fi

  if ! git -C "$project_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    log_error "Not a git repository. vault pull requires git."
    return 1
  fi

  local knowledge_branch="tasuki-knowledge"

  echo ""
  echo -e "${BOLD}Tasuki Vault Pull${NC}"
  echo -e "${DIM}Pulling shared knowledge from $knowledge_branch branch${NC}"
  echo ""

  # Fetch from remote first
  if git -C "$project_dir" remote get-url origin &>/dev/null 2>&1; then
    git -C "$project_dir" fetch origin "$knowledge_branch" &>/dev/null 2>&1 && \
      log_dim "  Fetched from remote" || true
  fi

  # Check if knowledge branch exists
  if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$knowledge_branch" 2>/dev/null && \
     ! git -C "$project_dir" show-ref --verify --quiet "refs/remotes/origin/$knowledge_branch" 2>/dev/null; then
    log_warn "  No $knowledge_branch branch found. Run vault push first."
    return 0
  fi

  local current_branch
  current_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null)
  local pulled=0
  local skipped=0

  # Extract files from knowledge branch without switching
  for type in "${SYNC_TYPES[@]}"; do
    # List files in the knowledge branch for this type
    local files
    files=$(git -C "$project_dir" ls-tree --name-only "$knowledge_branch:$type" 2>/dev/null || \
            git -C "$project_dir" ls-tree --name-only "origin/$knowledge_branch:$type" 2>/dev/null || true)

    [ -z "$files" ] && continue

    mkdir -p "$vault/$type"

    echo "$files" | while read -r fname; do
      [ -z "$fname" ] && continue
      local dest="$vault/$type/$fname"

      # Get remote content
      local remote_content
      remote_content=$(git -C "$project_dir" show "$knowledge_branch:$type/$fname" 2>/dev/null || \
                      git -C "$project_dir" show "origin/$knowledge_branch:$type/$fname" 2>/dev/null || true)
      [ -z "$remote_content" ] && continue

      # If local file exists, use keep-both strategy
      if [ -f "$dest" ]; then
        local local_content
        local_content=$(cat "$dest")

        # If identical, skip
        if [ "$local_content" = "$remote_content" ]; then
          skipped=$((skipped + 1))
          continue
        fi

        # Different content — keep both
        # Save remote with -team suffix
        local base_name="${fname%.md}"
        local team_dest="$vault/$type/${base_name}-team.md"
        echo "$remote_content" > "$team_dest"
        log_dim "    conflict: $type/$fname — kept both (local + ${base_name}-team.md)"
        pulled=$((pulled + 1))
        continue
      fi

      # No local file — pull directly
      echo "$remote_content" > "$dest"
      pulled=$((pulled + 1))
    done
  done

  if [ "$pulled" -gt 0 ]; then
    log_success "  Pulled $pulled memories from team"
  fi
  if [ "$skipped" -gt 0 ]; then
    log_dim "  Skipped $skipped (local version is newer)"
  fi
  if [ "$pulled" -eq 0 ] && [ "$skipped" -eq 0 ]; then
    log_dim "  Already up to date"
  fi

  echo ""
}

# --- Main ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  action="${1:-}"
  shift || true

  case "$action" in
    init)    vault_init "$@" ;;
    add)     vault_add "$@" ;;
    search)  vault_search "$@" ;;
    expand)  vault_expand "$@" ;;
    confidence) vault_confidence "$@" ;;
    decay)   vault_decay "$@" ;;
    push)    vault_push "$@" ;;
    pull)    vault_pull "$@" ;;
    stats)   vault_stats "$@" ;;
    sync)    vault_rag_sync "$@" ;;
    query)   vault_rag_query "${1:-.}" "$2" ;;
    *)
      echo "Usage: vault.sh <init|add|search|expand|confidence|decay|push|pull|stats|sync|query> [args...]"
      echo ""
      echo "  init   [path]                Initialize memory vault"
      echo "  add    [path] <type> <slug> <title> <content>"
      echo "  search [path] <query>        Search vault nodes"
      echo "  stats  [path]                Show vault statistics"
      exit 1
      ;;
  esac
fi
