#!/bin/bash
# Tasuki Engine — Activity Log
# Tracks what Tasuki does for the user — makes the invisible visible.
# Shows: heuristics loaded, errors prevented, bugs avoided, hooks blocked.
#
# File: .tasuki/config/activity-log.json
# Usage: source this file, then call activity functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

ACTIVITY_FILE=""

init_activity() {
  local project_dir="${1:-.}"
  ACTIVITY_FILE="$project_dir/.tasuki/config/activity-log.json"
  mkdir -p "$(dirname "$ACTIVITY_FILE")"
  if [ ! -f "$ACTIVITY_FILE" ]; then
    echo '{"events":[]}' > "$ACTIVITY_FILE"
  fi
}

# Log an activity event
activity_log() {
  local project_dir="${1:-.}"
  local type="$2"       # heuristic_loaded, error_prevented, hook_blocked, memory_read, pipeline_run
  local agent="$3"
  local detail="$4"

  init_activity "$project_dir"

  if command -v python3 &>/dev/null; then
    python3 << PYEOF
import json
with open("$ACTIVITY_FILE") as f:
    data = json.load(f)
data["events"].append({
    "time": "$(date '+%Y-%m-%d %H:%M:%S')",
    "type": "$type",
    "agent": "$agent",
    "detail": "$detail"
})
# Keep last 100 events
data["events"] = data["events"][-100:]
with open("$ACTIVITY_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
  fi
}

# Show activity summary
activity_show() {
  local project_dir="${1:-.}"
  init_activity "$project_dir"

  echo ""
  echo -e "${BOLD}Tasuki Activity — What Tasuki Did For You${NC}"
  echo -e "${DIM}══════════════════════════════════════════${NC}"
  echo ""

  if [ ! -f "$ACTIVITY_FILE" ] || ! command -v python3 &>/dev/null; then
    echo -e "  ${DIM}No activity recorded yet.${NC}"
    echo ""
    return
  fi

  python3 << 'PYEOF'
import json

with open("ACTIVITY_FILE_PATH") as f:
    data = json.load(f)

events = data.get("events", [])
if not events:
    print("  No activity recorded yet.")
    print()
    exit()

# Count by type
counts = {}
for e in events:
    t = e.get("type", "unknown")
    counts[t] = counts.get(t, 0) + 1

# Icons
icons = {
    "heuristic_loaded": "📚",
    "error_prevented": "🛡️",
    "hook_blocked": "🚫",
    "memory_read": "🧠",
    "pipeline_run": "⚙️",
    "bug_avoided": "🐛",
}

GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
DIM = "\033[2m"
BOLD = "\033[1m"
NC = "\033[0m"

# Summary
print(f"  {BOLD}Impact Summary:{NC}")
if "error_prevented" in counts:
    print(f"    {GREEN}{counts['error_prevented']} errors prevented{NC} — mistakes not repeated thanks to memory")
if "heuristic_loaded" in counts:
    print(f"    {CYAN}{counts['heuristic_loaded']} heuristics applied{NC} — learned rules used by agents")
if "hook_blocked" in counts:
    print(f"    {YELLOW}{counts['hook_blocked']} unsafe edits blocked{NC} — TDD guard + security hooks")
if "pipeline_run" in counts:
    print(f"    {GREEN}{counts['pipeline_run']} pipeline runs{NC}")
if "bug_avoided" in counts:
    print(f"    {GREEN}{counts['bug_avoided']} bugs avoided{NC} — past incidents prevented repetition")
print()

# Recent events
print(f"  {BOLD}Recent Activity:{NC}")
for e in reversed(events[-10:]):
    icon = icons.get(e["type"], "•")
    agent = e.get("agent", "")
    detail = e.get("detail", "")
    time = e.get("time", "")[-8:]  # HH:MM:SS
    agent_str = f" [{agent}]" if agent else ""
    print(f"    {DIM}{time}{NC} {icon}{agent_str} {detail}")
print()
PYEOF
}

# Generate activity data for dashboard
activity_json() {
  local project_dir="${1:-.}"
  init_activity "$project_dir"

  if [ -f "$ACTIVITY_FILE" ]; then
    cat "$ACTIVITY_FILE"
  else
    echo '{"events":[]}'
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-show}" in
    show) shift; activity_show "$@" ;;
    log)  shift; activity_log "$@" ;;
    json) shift; activity_json "$@" ;;
    *) echo "Usage: activity-log.sh <show|log|json> [args]" ;;
  esac
fi
