#!/bin/bash
# Tasuki Engine — Pipeline Progress
# Tracks and displays pipeline stage progress.
# Used by TASUKI.md Stage 9 to write, and by dashboard to read.
#
# File: .tasuki/config/pipeline-progress.json
# Usage: source this file, then call progress functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail
set +u

PROGRESS_FILE=""

init_progress() {
  local project_dir="${1:-.}"
  PROGRESS_FILE="$project_dir/.tasuki/config/pipeline-progress.json"
  mkdir -p "$(dirname "$PROGRESS_FILE")"
}

# Start a new pipeline run
progress_start() {
  local project_dir="${1:-.}"
  local task="$2"
  local mode="${3:-standard}"
  local total_stages="${4:-9}"

  init_progress "$project_dir"

  cat > "$PROGRESS_FILE" << EOF
{
  "task": "$task",
  "mode": "$mode",
  "started": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "running",
  "current_stage": 1,
  "total_stages": $total_stages,
  "stages": {}
}
EOF
}

# Update current stage
progress_update() {
  local project_dir="${1:-.}"
  local stage_num="$2"
  local stage_name="$3"
  local status="${4:-running}"  # running, done, skipped, failed

  init_progress "$project_dir"

  if command -v python3 &>/dev/null && [ -f "$PROGRESS_FILE" ]; then
    python3 << PYEOF
import json
with open("$PROGRESS_FILE") as f:
    data = json.load(f)
data["current_stage"] = $stage_num
data["stages"]["$stage_name"] = {"status": "$status", "time": "$(date '+%H:%M:%S')"}
# Mark previous running stages as done
for name, info in data.get("stages", {}).items():
    if info.get("status") == "running" and name != "$stage_name":
        info["status"] = "done"
if "$status" == "done":
    data["current_stage"] = $stage_num + 1
with open("$PROGRESS_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
  fi
}

# Complete the pipeline
progress_complete() {
  local project_dir="${1:-.}"

  init_progress "$project_dir"

  if command -v python3 &>/dev/null && [ -f "$PROGRESS_FILE" ]; then
    python3 << PYEOF
import json
with open("$PROGRESS_FILE") as f:
    data = json.load(f)
data["status"] = "completed"
data["completed"] = "$(date '+%Y-%m-%d %H:%M:%S')"
with open("$PROGRESS_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
  fi
}

# Show progress bar in terminal
show_progress() {
  local project_dir="${1:-.}"

  init_progress "$project_dir"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo -e "  ${DIM}No pipeline running${NC}"
    return
  fi

  if command -v python3 &>/dev/null; then
    python3 << PYEOF
import json

with open("$PROGRESS_FILE") as f:
    data = json.load(f)

task = data.get("task", "unknown")
mode = data.get("mode", "standard")
status = data.get("status", "unknown")
current = data.get("current_stage", 0)
total = data.get("total_stages", 9)
stages = data.get("stages", {})

# Auto-detect completion: Reviewer done + nothing running
has_reviewer = "Reviewer" in stages
has_running = any(s.get("status") == "running" for s in stages.values())
if has_reviewer and not has_running:
    status = "completed"
    data["status"] = "completed"
    for s in stages.values():
        if s.get("status") == "running":
            s["status"] = "done"
    # Write history if not already written for this task
    import os, datetime
    history_path = os.path.join(os.path.dirname("$PROGRESS_FILE"), "pipeline-history.log")
    already_logged = False
    if os.path.exists(history_path):
        with open(history_path) as hf:
            already_logged = task in hf.read()
    if not already_logged:
        agent_names = ",".join(stages.keys())
        n = len(stages)
        score = min(10, n * 2)
        duration = n * 60
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        with open(history_path, "a") as hf:
            hf.write(f"{now}|{mode}|{score}|{agent_names}|{duration}|{task}\\n")
    # Update progress file
    with open("$PROGRESS_FILE", "w") as f:
        json.dump(data, f, indent=2)

# Progress bar
filled = int((current / total) * 20) if total > 0 else 0
bar = "█" * filled + "░" * (20 - filled)
pct = int((current / total) * 100)

# Colors (ANSI)
GREEN = "\\033[0;32m"
YELLOW = "\\033[1;33m"
CYAN = "\\033[0;36m"
DIM = "\\033[2m"
BOLD = "\\033[1m"
NC = "\\033[0m"

color = GREEN if status == "completed" else YELLOW

print(f"  {BOLD}Pipeline: {task}{NC}")
print(f"  {color}{bar}{NC} {pct}% ({current}/{total})")
print(f"  {DIM}Mode: {mode} | Status: {status}{NC}")

if stages:
    print(f"  {DIM}Stages:{NC}")
    for name, info in stages.items():
        icon = "✓" if info["status"] == "done" else "→" if info["status"] == "running" else "○"
        status_str = info['status']
        time_str = f" ({info.get('time', '')})" if info.get('time') else ''

        # Show files and tests per stage
        details = []
        created = info.get('files_created', [])
        edited = info.get('files_edited', [])
        tests = info.get('tests_run', 0)
        if created:
            details.append(f"{len(created)} created")
        if edited:
            details.append(f"{len(edited)} edited")
        if tests > 0:
            details.append(f"{tests} tests")

        detail_str = f" — {', '.join(details)}" if details else ''
        desc = info.get('description', '')
        desc_str = f" {DIM}{desc}{NC}" if desc and info['status'] == 'running' else ''
        print(f"    {icon} {name} ({status_str}){time_str}{detail_str}{desc_str}")

    # Summary
    total_created = sum(len(s.get('files_created', [])) for s in stages.values())
    total_edited = sum(len(s.get('files_edited', [])) for s in stages.values())
    total_tests = sum(s.get('tests_run', 0) for s in stages.values())
    if total_created + total_edited + total_tests > 0:
        print(f"  {DIM}────{NC}")
        print(f"  {DIM}Files: {total_created} created, {total_edited} edited | Tests: {total_tests} runs{NC}")
PYEOF
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-show}" in
    start)    shift; progress_start "$@" ;;
    update)   shift; progress_update "$@" ;;
    complete) shift; progress_complete "$@" ;;
    show)     shift; show_progress "$@" ;;
  esac
fi
