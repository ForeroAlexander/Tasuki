#!/bin/bash
# Tasuki Adapter — Claude Code
# Generates CLAUDE.md + Agent Teams config when available.
#
# Two modes:
#   1. Legacy: CLAUDE.md with sequential pipeline instructions (works everywhere)
#   2. Agent Teams: Team lead CLAUDE.md + teammate configs + TeammateIdle/TaskCompleted hooks
#
# Agent Teams activates automatically when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

ADAPTERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

generate_config() {
  local project_dir="$1"

  if [ ! -f "$project_dir/TASUKI.md" ]; then
    log_warn "  No TASUKI.md found — skipping Claude adapter"
    return
  fi

  # Check if Agent Teams should be enabled
  if should_enable_agent_teams "$project_dir"; then
    generate_agent_teams_config "$project_dir"
  else
    generate_legacy_config "$project_dir"
  fi
}

# --- Legacy mode (sequential pipeline in single context) ---
generate_legacy_config() {
  local project_dir="$1"

  sed \
    -e 's/→ \*\*Invoke: \([a-z-]*\) agent\*\*/```\nAgent(subagent_type="\1")\n```/g' \
    -e 's/invoke the \*\*\([a-z-]*\)\*\* agent/`Agent(subagent_type="\1")`/g' \
    -e 's/Invoke \([a-z-]*\) agent with:/Agent(subagent_type="\1", prompt=/g' \
    "$project_dir/TASUKI.md" > "$project_dir/CLAUDE.md"

  log_dim "  CLAUDE.md (legacy mode — sequential pipeline)"
}

# --- Agent Teams mode (real multi-agent orchestration) ---

should_enable_agent_teams() {
  local project_dir="$1"

  # Explicit opt-out: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 disables Agent Teams
  if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "0" ]; then
    return 1
  fi

  # Check project settings for explicit opt-out
  local settings="$project_dir/.claude/settings.local.json"
  if [ -f "$settings" ]; then
    local env_val
    env_val=$(python3 -c "
import json, sys
try:
    with open('$settings') as f:
        data = json.load(f)
    print(data.get('env', {}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS', ''))
except:
    print('')
" 2>/dev/null)
    [ "$env_val" = "0" ] && return 1
  fi

  # Agent Teams is the default for Claude adapter — always enable unless opted out
  return 0
}

generate_agent_teams_config() {
  local project_dir="$1"

  log_dim "  Agent Teams mode detected — generating team config..."

  # 1. Generate team lead CLAUDE.md
  generate_team_lead_claude_md "$project_dir"

  # 2. Enable Agent Teams env var in settings
  enable_agent_teams_env "$project_dir"

  # 3. Add TeammateIdle + TaskCompleted hooks to settings
  add_team_hooks "$project_dir"

  # 4. Copy team hook scripts
  copy_team_hooks "$project_dir"

  log_success "  Claude Agent Teams: team lead + $(count_teammates "$project_dir") teammates configured"
}

generate_team_lead_claude_md() {
  local project_dir="$1"
  local output="$project_dir/CLAUDE.md"
  local project_name
  project_name=$(basename "$project_dir")

  # Read project name from config if available
  if [ -f "$project_dir/.tasuki/config/project-facts.md" ]; then
    local pn
    pn=$(grep -oP 'project_name:\s*\K.*' "$project_dir/.tasuki/config/project-facts.md" 2>/dev/null | head -1 | tr -d ' ' || true)
    # Fallback: extract from heading "# Project Facts — name"
    [ -z "$pn" ] && pn=$(head -1 "$project_dir/.tasuki/config/project-facts.md" 2>/dev/null | sed 's/.*— //' || true)
    [ -n "$pn" ] && project_name="$pn"
  fi

  # Build teammate list from agent files
  local teammates=""
  local teammate_instructions=""

  if [ -d "$project_dir/.tasuki/agents" ]; then
    for agent_file in "$project_dir/.tasuki/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name model_tier claude_model desc domains
      name=$(basename "$agent_file" .md)

      # Skip non-teammate agents
      case "$name" in
        onboard|planner) continue ;;
      esac

      # Extract frontmatter
      model_tier=$(grep "^model:" "$agent_file" 2>/dev/null | head -1 | sed 's/^model:\s*//' | tr -d ' ')
      desc=$(grep "^description:" "$agent_file" 2>/dev/null | head -1 | sed 's/^description:\s*//' )
      domains=$(grep "^domains:" "$agent_file" 2>/dev/null | head -1 | sed 's/^domains:\s*//')

      # Map model tier to Claude model ID
      case "$model_tier" in
        opus)   claude_model="opus" ;;
        haiku)  claude_model="haiku" ;;
        *)      claude_model="sonnet" ;;
      esac

      teammates="$teammates\n| **$name** | $claude_model | $desc |"
      teammate_instructions="$teammate_instructions
### $name
- **Model:** $claude_model
- **Domains:** $domains
- **Instructions file:** \`.tasuki/agents/$name.md\`
- **Description:** $desc
- **When to spawn:** When the pipeline reaches this agent's stage
"
    done
  fi

  cat > "$output" << CLAUDEMD
# $project_name — Team Lead Instructions

You are the **Team Lead** (Planner) for this project. You orchestrate a team of specialized AI teammates using Claude Agent Teams.

**IMPORTANT:** You do NOT execute tasks yourself (except planning). You create tasks and assign them to teammates. Each teammate has its own context window and model.

## Your Role

1. Receive the user's request
2. Read \`.tasuki/agents/planner.md\` for your full planning instructions
3. Analyze the task and create a plan
4. Create tasks and assign them to the right teammates
5. Monitor progress, provide feedback, resolve blockers
6. Summarize results when all tasks complete

## Your Teammates
| Name | Model | Description |
|------|-------|-------------|$(echo -e "$teammates")

## How to Work With Teammates

### Spawning
When you need a teammate, describe their task clearly. Each teammate will load their own instructions from \`.tasuki/agents/{name}.md\`.

Example: "QA, write failing tests for the new /api/reports endpoint. Requirements: 401 without token, 403 for wrong role, 200 with pagination."

### Task Assignment
Create tasks with clear acceptance criteria. Teammates self-coordinate via the shared task list.

### Communication
- **Direct message**: Send specific instructions to one teammate
- **Broadcast**: Use sparingly — costs scale with team size
- **Task list**: All teammates see shared task status and dependencies

## Pipeline Order

Execute the pipeline in this order. Each stage must complete before the next starts.

1. **You (Planner)** — Analyze, design, create the plan
2. **qa** — Write failing tests (TDD red phase)
3. **db-architect** — Schema changes and migrations (if needed)
4. **backend-dev** — Implement backend (make tests pass)
5. **frontend-dev** — Implement frontend (if needed)
6. **security** — OWASP audit (always runs)
7. **reviewer** — Quality gate (approve or request changes)
8. **devops** — Deploy (if needed)

**Debugger** is reactive — only spawn when tests fail.

## Before You Plan

Load context (this is mandatory):
1. Read \`.tasuki/agents/planner.md\` — your full instructions
2. Read \`.tasuki/config/project-facts.md\` — verified stack info
3. Read \`tasuki-plans/index.md\` — previous plans
4. Check \`memory-vault/decisions/\` — past architectural decisions

## Quality Gates

Hooks enforce quality automatically:
- **TeammateIdle**: Runs tests + security checks before a teammate can go idle
- **TaskCompleted**: Validates acceptance criteria before marking a task done
- **tdd-guard**: Blocks implementation code if tests don't exist yet
- **security-check**: Blocks security anti-patterns in all file edits
- **protect-files**: Blocks edits to .env, secrets/, lock files

## Teammate Details
$teammate_instructions

## Completion

When all tasks are done:
1. Summarize what was built, modified, and tested
2. List any manual steps needed (env vars, migrations, docker restart)
3. Record lessons learned in \`memory-vault/\` if there was a non-obvious insight

## Rules (Non-Negotiable)

1. **Sequential pipeline**: Each stage completes before the next starts
2. **Backend before frontend**: The API is the contract
3. **TDD mandatory**: Tests exist before implementation
4. **Security always runs**: No exceptions
5. **Reviewer is the gate**: Nothing ships without approval
6. **You plan, teammates execute**: Stay in your lane
CLAUDEMD

  log_dim "    CLAUDE.md (team lead mode)"
}

count_teammates() {
  local project_dir="$1"
  local count=0

  if [ -d "$project_dir/.tasuki/agents" ]; then
    for agent_file in "$project_dir/.tasuki/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      local name
      name=$(basename "$agent_file" .md)
      case "$name" in onboard|planner) continue ;; esac
      count=$((count + 1))
    done
  fi

  echo "$count"
}

enable_agent_teams_env() {
  local project_dir="$1"
  local settings="$project_dir/.claude/settings.local.json"

  mkdir -p "$project_dir/.claude"

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, os

f = '$settings'
data = {}
if os.path.exists(f):
    with open(f) as fh:
        try: data = json.load(fh)
        except: data = {}

env = data.setdefault('env', {})
env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'

with open(f, 'w') as fh:
    json.dump(data, fh, indent=2)
" 2>/dev/null
    log_dim "    Agent Teams env var enabled in settings"
  fi
}

add_team_hooks() {
  local project_dir="$1"
  local settings="$project_dir/.claude/settings.local.json"

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, os

f = '$settings'
data = {}
if os.path.exists(f):
    with open(f) as fh:
        try: data = json.load(fh)
        except: data = {}

hooks = data.setdefault('hooks', {})

# TeammateIdle hook
hooks['TeammateIdle'] = [{
    'hooks': [{
        'type': 'command',
        'command': '$project_dir/.tasuki/hooks/teammate-idle.sh'
    }]
}]

# TaskCompleted hook
hooks['TaskCompleted'] = [{
    'hooks': [{
        'type': 'command',
        'command': '$project_dir/.tasuki/hooks/task-completed.sh'
    }]
}]

with open(f, 'w') as fh:
    json.dump(data, fh, indent=2)
" 2>/dev/null
    log_dim "    TeammateIdle + TaskCompleted hooks added"
  fi
}

copy_team_hooks() {
  local project_dir="$1"
  local hooks_dir="$project_dir/.tasuki/hooks"

  mkdir -p "$hooks_dir"

  # Copy from templates if they exist
  local templates_dir="$ADAPTERS_DIR/../templates/hooks"
  if [ -f "$templates_dir/teammate-idle.sh" ]; then
    cp "$templates_dir/teammate-idle.sh" "$hooks_dir/teammate-idle.sh"
    chmod +x "$hooks_dir/teammate-idle.sh"
  fi
  if [ -f "$templates_dir/task-completed.sh" ]; then
    cp "$templates_dir/task-completed.sh" "$hooks_dir/task-completed.sh"
    chmod +x "$hooks_dir/task-completed.sh"
  fi

  log_dim "    Team hooks copied to .tasuki/hooks/"
}

get_adapter_info() {
  echo "claude|CLAUDE.md + .tasuki/ + Agent Teams|Claude Code"
}
