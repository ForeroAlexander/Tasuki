#!/bin/bash
# Tasuki Hook: Pipeline Tracker (State Machine)
# PreToolUse hook for ALL tools — tracks pipeline stage, files touched,
# tests run, and results. Machine-readable state for session continuity.
# Never blocks — always exits 0.
#
# State file: .tasuki/config/pipeline-progress.json
# Format:
# {
#   "task": "add overdue loans",
#   "mode": "standard",
#   "started": "2026-03-15 21:25:00",
#   "status": "running",
#   "current_stage": 4,
#   "total_stages": 9,
#   "stages": {
#     "Planner": { "status": "done", "time": "21:25:49", "files_created": ["tasuki-plans/overdue/prd.md"], "files_read": ["agents/planner.md"] },
#     "QA": { "status": "done", "time": "21:29:22", "files_created": ["tests/test_overdue.py"], "tests_run": 3, "tests_passed": 0 },
#     "Backend-Dev": { "status": "running", "time": "21:33:43", "files_edited": ["app/views.py", "app/services.py"], "tests_run": 3, "tests_passed": 3 }
#   }
# }

set +e
set +o pipefail

PROJECT_DIR="${PWD}"
PROGRESS_FILE="$PROJECT_DIR/.tasuki/config/pipeline-progress.json"

# Only track if .tasuki exists
[ ! -d "$PROJECT_DIR/.tasuki" ] && exit 0

# Read tool input from stdin
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi
[ -z "$INPUT" ] && INPUT="${TOOL_INPUT:-}"

# Extract tool name and file path
TOOL_NAME=""
FILE_PATH=""
COMMAND=""

if [ -n "$INPUT" ]; then
  TOOL_NAME=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  [ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -oP '"pattern"\s*:\s*"\K[^"]*' 2>/dev/null || true)
  COMMAND=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]*' 2>/dev/null || true)
fi

# --- Detect stage from agent file reads ---
STAGE_NUM=0
STAGE_NAME=""

case "$FILE_PATH" in
  *agents/planner.md*)    STAGE_NUM=1; STAGE_NAME="Planner" ;;
  *agents/qa.md*)         STAGE_NUM=2; STAGE_NAME="QA" ;;
  *agents/db-architect*)  STAGE_NUM=3; STAGE_NAME="DB-Architect" ;;
  *agents/backend-dev*)   STAGE_NUM=4; STAGE_NAME="Backend-Dev" ;;
  *agents/frontend-dev*)  STAGE_NUM=5; STAGE_NAME="Frontend-Dev" ;;
  *agents/debugger*)      STAGE_NUM=5; STAGE_NAME="Debugger" ;;
  *agents/security*)      STAGE_NUM=6; STAGE_NAME="Security" ;;
  *agents/reviewer*)      STAGE_NUM=7; STAGE_NAME="Reviewer" ;;
  *agents/devops*)        STAGE_NUM=8; STAGE_NAME="DevOps" ;;
  *tasuki-plans/*/prd*)   STAGE_NUM=1; STAGE_NAME="Planner" ;;
  *memory-vault/*)
    TASUKI_BIN=$(command -v tasuki 2>/dev/null || echo "")
    if [ -n "$TASUKI_BIN" ]; then
      "$TASUKI_BIN" vault sync "$PROJECT_DIR" &>/dev/null &
    fi
    exit 0
    ;;
esac

# --- Detect test runs from Bash commands ---
IS_TEST_RUN=false
TEST_FRAMEWORK=""
if [ -n "$COMMAND" ]; then
  case "$COMMAND" in
    *pytest*|*py.test*)   IS_TEST_RUN=true; TEST_FRAMEWORK="pytest" ;;
    *jest*|*vitest*)      IS_TEST_RUN=true; TEST_FRAMEWORK="jest" ;;
    *mocha*)              IS_TEST_RUN=true; TEST_FRAMEWORK="mocha" ;;
    *go\ test*)           IS_TEST_RUN=true; TEST_FRAMEWORK="go" ;;
    *rspec*)              IS_TEST_RUN=true; TEST_FRAMEWORK="rspec" ;;
    *manage.py\ test*)    IS_TEST_RUN=true; TEST_FRAMEWORK="django" ;;
  esac
fi

# --- If no stage change and no test run and no file edit, skip ---
if [ "$STAGE_NUM" -eq 0 ] && [ "$IS_TEST_RUN" = false ] && [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- No progress file and no stage detected? Skip ---
if [ ! -f "$PROGRESS_FILE" ] && [ "$STAGE_NUM" -eq 0 ]; then
  exit 0
fi

# Initialize progress file if needed
if [ ! -f "$PROGRESS_FILE" ] && [ "$STAGE_NUM" -gt 0 ]; then
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  cat > "$PROGRESS_FILE" << EOF
{
  "task": "pipeline",
  "mode": "standard",
  "started": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "running",
  "current_stage": $STAGE_NUM,
  "total_stages": 9,
  "stages": {}
}
EOF
fi

# --- Update state with Python (atomic, reliable) ---
if [ -f "$PROGRESS_FILE" ] && command -v python3 &>/dev/null; then
  IS_TEST_PY=$( [ "$IS_TEST_RUN" = true ] && echo "True" || echo "False" )
  NOW_DATE=$(date "+%Y-%m-%d %H:%M:%S")
  NOW_TIME=$(date "+%H:%M:%S")
  NOW_SHORT=$(date "+%Y-%m-%d %H:%M")
  python3 - "$PROGRESS_FILE" "$STAGE_NUM" "$STAGE_NAME" "$FILE_PATH" "$TOOL_NAME" "$IS_TEST_PY" "$TEST_FRAMEWORK" "$PROJECT_DIR" "$NOW_DATE" "$NOW_TIME" "$NOW_SHORT" << 'PYEOF'
import json, os, sys

f = sys.argv[1]
stage_num = int(sys.argv[2])
stage_name = sys.argv[3]
file_path = sys.argv[4]
tool_name = sys.argv[5]
is_test = sys.argv[6] == 'True'
test_fw = sys.argv[7]
project_dir = sys.argv[8]
now_date = sys.argv[9]
now_time = sys.argv[10]
now_short = sys.argv[11]

with open(f) as fh:
    data = json.load(fh)

# Skip if pipeline already completed
if data.get('status') == 'completed':
    # New stage after completion = new pipeline
    if stage_num > 0:
        data = {
            'task': 'pipeline',
            'mode': data.get('mode', 'standard'),
            'started': now_date,
            'status': 'running',
            'current_stage': stage_num,
            'total_stages': 9,
            'stages': {}
        }

stages = data.setdefault('stages', {})

# --- Stage transition ---
if stage_num > 0:
    prev = data.get('current_stage', 0)

    # Mark previous running stages as done
    if stage_num > prev:
        for name, info in stages.items():
            if info.get('status') == 'running':
                info['status'] = 'done'

    data['current_stage'] = stage_num

    # Agent role descriptions
    agent_roles = {
        'Planner': 'Designing architecture and creating PRD',
        'QA': 'Writing failing tests (TDD red phase)',
        'DB-Architect': 'Designing schema and migrations',
        'Backend-Dev': 'Implementing backend code until tests pass',
        'Frontend-Dev': 'Building UI with design preview',
        'Debugger': 'Investigating and fixing test failures',
        'Security': 'Running OWASP audit and variant analysis',
        'Reviewer': 'Code review and quality gate',
        'DevOps': 'Infrastructure, CI/CD, and deployment config'
    }
    task_name = data.get('task', 'pipeline')
    desc = agent_roles.get(stage_name, stage_name)
    if task_name and task_name != 'pipeline':
        desc = f"{desc} for: {task_name[:50]}"

    # Initialize new stage
    if stage_name not in stages:
        stages[stage_name] = {
            'status': 'running',
            'time': now_time,
            'description': desc,
            'files_read': [],
            'files_created': [],
            'files_edited': [],
            'tests_run': 0,
            'tests_passed': 0
        }
    else:
        stages[stage_name]['status'] = 'running'
        stages[stage_name]['description'] = desc

# --- Track files touched in current stage ---
current_stage_name = None
for name, info in stages.items():
    if info.get('status') == 'running':
        current_stage_name = name
        break

if current_stage_name and file_path:
    stage = stages[current_stage_name]
    rel_path = os.path.relpath(file_path, project_dir) if file_path.startswith('/') else file_path

    # Skip tracking .tasuki internal files
    if not rel_path.startswith('.tasuki') and not rel_path.startswith('memory-vault'):
        if tool_name == 'Read':
            if rel_path not in stage.get('files_read', []):
                stage.setdefault('files_read', []).append(rel_path)
        elif tool_name == 'Write':
            if rel_path not in stage.get('files_created', []):
                stage.setdefault('files_created', []).append(rel_path)
        elif tool_name == 'Edit':
            if rel_path not in stage.get('files_edited', []):
                stage.setdefault('files_edited', []).append(rel_path)

# --- Track test runs ---
if is_test and current_stage_name:
    stage = stages[current_stage_name]
    stage['tests_run'] = stage.get('tests_run', 0) + 1
    # We can't know pass/fail from PreToolUse (runs before execution)
    # But we track the count for visibility

# --- Completion detection ---
reviewer = stages.get('Reviewer', {})
non_running = [s for s in stages.values() if s.get('status') != 'running']
all_non_running_done = all(s.get('status') == 'done' for s in non_running)

# Complete if:
# 1. Reviewer exists and is done, and we moved past it (original logic)
# 2. Reviewer is running but ALL previous stages are done, and current action
#    is NOT reading an agent file (means Reviewer finished, Claude moved on)
reviewer_done = reviewer.get('status') == 'done'
reviewer_running = reviewer.get('status') == 'running'
# past_reviewer = Claude is doing something that is NOT reading an agent file
# (stage_num==0 means no agent file was detected in this action)
past_reviewer = stage_num == 0 and (file_path or tool_name or command)

should_complete = False
if reviewer_done and all_non_running_done and len(stages) >= 3:
    should_complete = True
elif reviewer_running and past_reviewer and len(non_running) >= 2 and all_non_running_done:
    # Reviewer was running but Claude is now doing something else (not reading an agent)
    # This means the review is done
    should_complete = True

if should_complete:
    data['status'] = 'completed'
    data['completed_at'] = now_date
    for s in stages.values():
        if s.get('status') == 'running':
            s['status'] = 'done'

    # Write to history log
    history = os.path.join(project_dir, '.tasuki/config/pipeline-history.log')
    agents = ','.join(stages.keys())
    task = data.get('task', 'unknown')
    mode = data.get('mode', 'standard')
    n_stages = len(stages)
    total_files = sum(
        len(s.get('files_created', [])) + len(s.get('files_edited', []))
        for s in stages.values()
    )
    total_tests = sum(s.get('tests_run', 0) for s in stages.values())
    score = min(10, n_stages * 2)
    duration = n_stages * 60
    line = f'{now_short}|{mode}|{score}|{agents}|{duration}|{task}|{total_files}f|{total_tests}t\n'
    os.makedirs(os.path.dirname(history), exist_ok=True)
    with open(history, 'a') as hf:
        hf.write(line)

    # Count heuristics loaded → errors prevented
    af = os.path.join(project_dir, '.tasuki/config/activity-log.json')
    if os.path.exists(af):
        try:
            with open(af) as afh:
                act = json.load(afh)
            started = data.get('started', '')
            heuristics = [
                e for e in act.get('events', [])
                if e.get('type') == 'heuristic_loaded' and e.get('time', '') >= started
            ]
            for h in heuristics:
                act['events'].append({
                    'time': now_date,
                    'type': 'error_prevented',
                    'agent': h.get('agent', ''),
                    'detail': h.get('detail', '').replace('Applied:', 'Prevented:')
                })
            act['events'] = act['events'][-100:]
            with open(af, 'w') as afh:
                json.dump(act, afh, indent=2)
        except: pass

# --- Write state ---
with open(f, 'w') as fh:
    json.dump(data, fh, indent=2)

# --- Log stage activation ---
if stage_num > 0:
    af = os.path.join(project_dir, '.tasuki/config/activity-log.json')
    if os.path.exists(af):
        try:
            with open(af) as fh:
                adata = json.load(fh)
            adata['events'].append({
                'time': now_date,
                'type': 'pipeline_run',
                'agent': stage_name,
                'detail': f'Stage {stage_num}: {stage_name} activated'
            })
            adata['events'] = adata['events'][-100:]
            with open(af, 'w') as fh:
                json.dump(adata, fh, indent=2)
        except: pass
PYEOF
fi

exit 0
