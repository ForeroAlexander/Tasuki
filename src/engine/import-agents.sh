#!/bin/bash
# Tasuki Engine — Import External Agents
# Reads agents/skills/rules from another framework (WatchTower, custom .claude/, etc.)
# and merges their domain knowledge with Tasuki's pipeline structure.
#
# Usage: bash import-agents.sh <source_dir> [target_project_dir]
# Examples:
#   bash import-agents.sh /path/to/.claude/agents/         # import agents
#   bash import-agents.sh /path/to/.claude/                # import everything

set +e
set +o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

import_from_directory() {
  local source_dir="${1:-.}"
  local project_dir="${2:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  # Validate source
  if [ ! -d "$source_dir" ]; then
    log_error "Source directory not found: $source_dir"
    exit 1
  fi
  source_dir="$(cd "$source_dir" && pwd)"

  # Validate target has tasuki
  if [ ! -d "$project_dir/.tasuki" ]; then
    log_error "Target project not onboarded. Run: tasuki onboard $project_dir"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki — Import External Knowledge${NC}"
  echo -e "═══════════════════════════════════"
  echo ""
  echo -e "  Source: ${CYAN}$source_dir${NC}"
  echo -e "  Target: ${CYAN}$project_dir${NC}"
  echo ""

  local imported_agents=0
  local imported_skills=0
  local imported_rules=0
  local imported_hooks=0
  local imported_memories=0

  # --- Import Agents ---
  local agent_dirs=("$source_dir/agents" "$source_dir")
  for agent_dir in "${agent_dirs[@]}"; do
    if [ -d "$agent_dir" ]; then
      for agent_file in "$agent_dir"/*.md; do
        [ ! -f "$agent_file" ] && continue
        local filename=$(basename "$agent_file")
        local agent_name="${filename%.md}"

        # Skip non-agent files
        case "$agent_name" in
          README|MEMORY|index|*.bak) continue ;;
        esac

        # Check if this is actually an agent file (has frontmatter or agent-like content)
        if ! grep -qE "^#.*—|^description:|^tools:|You are" "$agent_file" 2>/dev/null; then
          continue
        fi

        # Check if tasuki already has this agent
        local tasuki_agent="$project_dir/.tasuki/agents/$agent_name.md"

        if [ -f "$tasuki_agent" ]; then
          # Merge: extract domain knowledge from source and inject into tasuki agent
          merge_agent "$agent_file" "$tasuki_agent" "$agent_name" "$project_dir"
        else
          # New agent not in tasuki — import as custom agent
          import_new_agent "$agent_file" "$agent_name" "$project_dir"
        fi
        imported_agents=$((imported_agents + 1))
      done
      break  # Only process first matching directory
    fi
  done

  # --- Import Skills ---
  local skill_dirs=("$source_dir/skills" "$source_dir/../skills")
  for skill_dir in "${skill_dirs[@]}"; do
    if [ -d "$skill_dir" ]; then
      for skill_path in "$skill_dir"/*/; do
        [ ! -d "$skill_path" ] && continue
        local skill_name=$(basename "$skill_path")
        local target_skill="$project_dir/.tasuki/skills/$skill_name"

        if [ ! -d "$target_skill" ]; then
          cp -r "$skill_path" "$target_skill"
          log_dim "  imported skill: $skill_name"
          imported_skills=$((imported_skills + 1))
        else
          log_dim "  skill exists, merging: $skill_name"
          # Append unique content from source skill
          if [ -f "$skill_path/SKILL.md" ] && [ -f "$target_skill/SKILL.md" ]; then
            merge_skill "$skill_path/SKILL.md" "$target_skill/SKILL.md" "$skill_name"
          fi
          imported_skills=$((imported_skills + 1))
        fi
      done
      break
    fi
  done

  # --- Import Rules ---
  local rule_dirs=("$source_dir/rules" "$source_dir/../rules")
  for rule_dir in "${rule_dirs[@]}"; do
    if [ -d "$rule_dir" ]; then
      for rule_file in "$rule_dir"/*.md; do
        [ ! -f "$rule_file" ] && continue
        local rule_name=$(basename "$rule_file")
        local target_rule="$project_dir/.tasuki/rules/$rule_name"

        if [ ! -f "$target_rule" ]; then
          cp "$rule_file" "$target_rule"
          log_dim "  imported rule: $rule_name"
          imported_rules=$((imported_rules + 1))
        fi
      done
      break
    fi
  done

  # --- Import Hooks ---
  local hook_dirs=("$source_dir/hooks" "$source_dir/../hooks")
  for hook_dir in "${hook_dirs[@]}"; do
    if [ -d "$hook_dir" ]; then
      for hook_file in "$hook_dir"/*.sh; do
        [ ! -f "$hook_file" ] && continue
        local hook_name=$(basename "$hook_file")
        local target_hook="$project_dir/.tasuki/hooks/$hook_name"

        # Don't overwrite tasuki core hooks
        case "$hook_name" in
          pipeline-tracker.sh|pipeline-trigger.sh|force-agent-read.sh|force-planner-first.sh|tdd-guard.sh|security-check.sh|protect-files.sh) continue ;;
        esac

        if [ ! -f "$target_hook" ]; then
          cp "$hook_file" "$target_hook"
          chmod +x "$target_hook"
          log_dim "  imported hook: $hook_name"
          imported_hooks=$((imported_hooks + 1))
        fi
      done
      break
    fi
  done

  # --- Import Memory (agent-memory directories) ---
  local memory_dirs=("$source_dir/agent-memory" "$source_dir/../agent-memory")
  for mem_dir in "${memory_dirs[@]}"; do
    if [ -d "$mem_dir" ]; then
      for mem_agent_dir in "$mem_dir"/*/; do
        [ ! -d "$mem_agent_dir" ] && continue
        local mem_agent=$(basename "$mem_agent_dir")

        for mem_file in "$mem_agent_dir"*.md; do
          [ ! -f "$mem_file" ] && continue
          local mem_name=$(basename "$mem_file")

          # Import as heuristic into vault
          import_memory_to_vault "$mem_file" "$mem_agent" "$project_dir"
          imported_memories=$((imported_memories + 1))
        done
      done
      break
    fi
  done

  # --- Import MCP servers from existing .mcp.json ---
  local source_mcp="$source_dir/../.mcp.json"
  [ ! -f "$source_mcp" ] && source_mcp="$project_dir/.mcp.json.bak"
  if [ -f "$source_mcp" ] && command -v python3 &>/dev/null; then
    local target_mcp="$project_dir/.mcp.json"
    if [ -f "$target_mcp" ]; then
      python3 - "$source_mcp" "$target_mcp" << 'PYEOF'
import json, sys

source_mcp = sys.argv[1]
target_mcp = sys.argv[2]

with open(source_mcp) as f:
    source = json.load(f)
with open(target_mcp) as f:
    target = json.load(f)

source_servers = source.get('mcpServers', {})
target_servers = target.get('mcpServers', {})

imported = 0
for name, config in source_servers.items():
    if name not in target_servers:
        target_servers[name] = config
        print(f"  imported MCP: {name}")
        imported += 1

if imported > 0:
    target['mcpServers'] = target_servers
    with open(target_mcp, 'w') as f:
        json.dump(target, f, indent=2)
    print(f"  {imported} MCP server(s) merged into .mcp.json")
PYEOF
    fi
  fi

  echo ""
  echo -e "${BOLD}Import Complete${NC}"
  echo -e "═══════════════"
  echo ""
  echo -e "  Agents:   ${GREEN}$imported_agents${NC}"
  echo -e "  Skills:   ${GREEN}$imported_skills${NC}"
  echo -e "  Rules:    ${GREEN}$imported_rules${NC}"
  echo -e "  Hooks:    ${GREEN}$imported_hooks${NC}"
  echo -e "  Memories: ${GREEN}$imported_memories${NC}"
  echo ""

  if [ $imported_agents -gt 0 ]; then
    echo -e "  ${DIM}Your agents now have domain knowledge from the source project.${NC}"
    echo -e "  ${DIM}Tasuki's pipeline structure, hooks, and memory protocol are preserved.${NC}"
    echo ""

    # Offer to clean up source files
    local source_parent
    source_parent=$(dirname "$source_dir")
    local source_name
    source_name=$(basename "$source_dir")

    # Detect if source is a .claude/ directory or similar AI tool config
    local cleanup_targets=()
    [ -d "$project_dir/.claude/agents" ] && cleanup_targets+=("$project_dir/.claude/agents")
    [ -d "$project_dir/.claude/agent-memory" ] && cleanup_targets+=("$project_dir/.claude/agent-memory")
    [ -d "$project_dir/.claude/skills" ] && cleanup_targets+=("$project_dir/.claude/skills")
    [ -d "$project_dir/.claude/rules" ] && cleanup_targets+=("$project_dir/.claude/rules")
    [ -d "$project_dir/.claude/hooks" ] && cleanup_targets+=("$project_dir/.claude/hooks")
    [ -d "$project_dir/.claude/pipeline-state" ] && cleanup_targets+=("$project_dir/.claude/pipeline-state")

    if [ ${#cleanup_targets[@]} -gt 0 ]; then
      echo -e "  ${BOLD}Old framework files detected:${NC}"
      for t in "${cleanup_targets[@]}"; do
        echo -e "    ${DIM}$(basename "$t")/${NC}"
      done
      echo ""

      if [ -t 0 ]; then
        echo -n "  Remove old framework files? Tasuki has absorbed their knowledge. (y/n, Enter=y): "
        read -r cleanup_answer
        cleanup_answer="${cleanup_answer:-y}"

        if [ "$cleanup_answer" = "y" ] || [ "$cleanup_answer" = "Y" ]; then
          for t in "${cleanup_targets[@]}"; do
            rm -rf "$t"
            log_dim "  removed: $(basename "$t")/"
          done
          echo ""
          log_success "Old framework files removed. Tasuki is now your single pipeline."
        else
          echo ""
          echo -e "  ${DIM}Kept old files. You can remove them manually later.${NC}"
          echo -e "  ${DIM}Note: having two sets of agents may cause conflicts.${NC}"
        fi
      else
        echo -e "  ${DIM}Run interactively to remove old files, or remove manually:${NC}"
        for t in "${cleanup_targets[@]}"; do
          echo -e "    rm -rf $t"
        done
      fi
      echo ""
    fi
  fi
}

merge_agent() {
  local source_file="$1"
  local tasuki_file="$2"
  local agent_name="$3"
  local project_dir="$4"

  if ! command -v python3 &>/dev/null; then
    log_warn "  python3 not found — skipping merge for $agent_name"
    return
  fi

  python3 - "$source_file" "$tasuki_file" "$agent_name" "$project_dir" << 'PYEOF'
import sys, re, os

source_file = sys.argv[1]
tasuki_file = sys.argv[2]
agent_name = sys.argv[3]
project_dir = sys.argv[4]

with open(source_file) as f:
    source = f.read()
with open(tasuki_file) as f:
    tasuki = f.read()

# Extract domain-specific sections from source
# Look for: paths, patterns, conventions, architecture knowledge
extracted = []

# Extract file paths mentioned (app/backend/app/routers/ etc.)
paths = re.findall(r'(?:app|src|lib|pkg)/[\w/.-]+', source)
if paths:
    unique_paths = list(dict.fromkeys(paths))[:20]
    extracted.append("## Domain Knowledge (imported)\n")
    extracted.append("Key paths in this project:\n")
    for p in unique_paths:
        extracted.append(f"- `{p}`\n")
    extracted.append("\n")

# Extract table/model references
tables = re.findall(r'(?:Table|table|model|Model):\s*(\w+)', source)
if tables:
    unique_tables = list(dict.fromkeys(tables))[:15]
    extracted.append("Database tables referenced:\n")
    for t in unique_tables:
        extracted.append(f"- `{t}`\n")
    extracted.append("\n")

# Extract grep patterns (useful search patterns)
greps = re.findall(r'(?:Grep|grep).*?pattern="([^"]+)"', source)
if greps:
    extracted.append("Useful search patterns:\n")
    for g in greps[:10]:
        extracted.append(f"- `{g}`\n")
    extracted.append("\n")

# Extract "No Es Tu Trabajo" / delegation rules
delegation_match = re.search(r'(?:No Es Tu Trabajo|Not Your Job|Delegate).*?\n((?:\|.*\n)+)', source)
if delegation_match:
    extracted.append("Delegation rules (from source):\n")
    extracted.append(delegation_match.group(0).strip() + "\n\n")

# Extract architecture principles
arch_match = re.search(r'(?:Architecture Principles|Architectural|Design Principles).*?\n((?:- .*\n)+)', source)
if arch_match:
    extracted.append("Architecture principles (from source):\n")
    extracted.append(arch_match.group(0).strip() + "\n\n")

# Extract security/auth patterns
auth_patterns = re.findall(r'(?:require_role|get_current_user|auth|multi.tenant|client_id|RLS).*', source)
if auth_patterns:
    unique_auth = list(dict.fromkeys(auth_patterns))[:10]
    extracted.append("Auth/security patterns:\n")
    for a in unique_auth:
        extracted.append(f"- `{a.strip()}`\n")
    extracted.append("\n")

# Extract specific instructions for this agent type
agent_instructions = re.findall(r'(?:Para|For)\s+(?:' + agent_name + r'|Dev|QA|DBA|FrontDev).*?```(.*?)```', source, re.DOTALL | re.IGNORECASE)
if agent_instructions:
    extracted.append("Specific instructions from source project:\n```\n")
    for inst in agent_instructions[:3]:
        extracted.append(inst.strip() + "\n")
    extracted.append("```\n\n")

if extracted:
    # Insert before the last section (Handoff) in the tasuki agent
    insert_point = tasuki.rfind("## Handoff")
    if insert_point == -1:
        insert_point = len(tasuki)

    domain_block = "\n---\n\n" + "".join(extracted)
    merged = tasuki[:insert_point] + domain_block + "\n" + tasuki[insert_point:]

    with open(tasuki_file, 'w') as f:
        f.write(merged)

    print(f"  merged agent: {agent_name} (+{len(extracted)} domain sections)")
else:
    print(f"  agent: {agent_name} (no domain knowledge extracted)")
PYEOF
}

merge_skill() {
  local source_skill="$1"
  local target_skill="$2"
  local skill_name="$3"

  # Simple merge: append unique sections from source that don't exist in target
  local source_sections
  source_sections=$(grep "^## " "$source_skill" 2>/dev/null || true)
  local target_sections
  target_sections=$(grep "^## " "$target_skill" 2>/dev/null || true)

  while IFS= read -r section; do
    [ -z "$section" ] && continue
    if ! echo "$target_sections" | grep -qF "$section"; then
      # Extract section content from source and append to target
      local section_escaped
      section_escaped=$(echo "$section" | sed 's/[.*+?^${}()|[\]\\]/\\&/g')
      echo "" >> "$target_skill"
      sed -n "/^${section_escaped}/,/^## /p" "$source_skill" | head -n -1 >> "$target_skill"
      log_dim "    merged section: $section"
    fi
  done <<< "$source_sections"
}

import_new_agent() {
  local source_file="$1"
  local agent_name="$2"
  local project_dir="$3"

  # Copy the agent and add Tasuki pipeline structure
  local target="$project_dir/.tasuki/agents/$agent_name.md"
  cp "$source_file" "$target"

  # Check if it already has Handoff/Memory sections
  if ! grep -q "## Handoff" "$target" 2>/dev/null; then
    cat >> "$target" << 'EOF'

---

## Handoff

At the end of your stage, produce:

```
## Handoff — {Agent Name}
- **Completed**: {what you did}
- **Files modified**: {list}
- **Next agent**: {who's next in the pipeline}
- **Context**: {critical info for the next agent}
```

## Memory Protocol

At the end of significant work, persist learnings to the memory vault.

**Format**:
```
## {date} — {Short description}
**Pattern**: {What was learned}
**Evidence**: `{file:line}` — {observation}
**Scope**: [[{linked agents}]]
**Prevention**: {How to avoid this in the future}
```
EOF
  fi

  log_dim "  imported new agent: $agent_name"
}

import_memory_to_vault() {
  local mem_file="$1"
  local agent_name="$2"
  local project_dir="$3"

  local vault_dir="$project_dir/memory-vault/heuristics"
  mkdir -p "$vault_dir"

  # Read memory file and convert entries to vault heuristics
  if command -v python3 &>/dev/null; then
    python3 - "$mem_file" "$agent_name" "$vault_dir" << 'PYEOF'
import sys, re, os

mem_file = sys.argv[1]
agent_name = sys.argv[2]
vault_dir = sys.argv[3]

with open(mem_file) as f:
    content = f.read()

# Find memory entries (## date — description format)
entries = re.findall(r'## (\d{4}-\d{2}-\d{2}) — (.+?)\n(.*?)(?=\n## |\Z)', content, re.DOTALL)

for date, title, body in entries:
    slug = re.sub(r'[^a-z0-9]+', '-', title.lower().strip()).strip('-')[:50]
    outfile = os.path.join(vault_dir, f"{slug}.md")

    if not os.path.exists(outfile):
        with open(outfile, 'w') as f:
            f.write(f"---\ntype: heuristic\nconfidence: high\nimported_from: {agent_name}\nlast_validated: {date}\napplied_count: 1\n---\n\n")
            f.write(body.strip() + "\n")
            # Add wikilink to agent
            if f"[[{agent_name}]]" not in body:
                f.write(f"\n**Scope**: [[{agent_name}]]\n")
        print(f"    vault: {slug} (from {agent_name})")

PYEOF
  fi
}

# --- Main ---
import_from_directory "$@"
