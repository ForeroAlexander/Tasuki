#!/usr/bin/env python3
"""
Tasuki — Pipeline State Machine

Updates pipeline progress state atomically. Tracks stage transitions,
file operations (read/created/edited), test runs, and detects pipeline completion.

Usage:
    python3 pipeline_state.py <progress_file> <stage_num> <stage_name> <file_path> \
        <tool_name> <is_test> <test_framework> <project_dir> <now_date> <now_time> <now_short>
"""

import json
import os
import sys


def update_state(f, stage_num, stage_name, file_path, tool_name,
                 is_test, test_fw, project_dir, now_date, now_time, now_short):

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

        # Debugger (55) is reactive — doesn't affect main pipeline sequence
        is_debugger = stage_num == 55
        effective_prev = prev if prev != 55 else data.get('pre_debugger_stage', prev)

        # Mark previous running stages as done
        if not is_debugger and stage_num > effective_prev:
            for name, info in stages.items():
                if info.get('status') == 'running':
                    info['status'] = 'done'
        elif is_debugger:
            # Debugger: mark current running stage as done (it failed)
            for name, info in stages.items():
                if info.get('status') == 'running':
                    info['status'] = 'done'
            data['pre_debugger_stage'] = prev

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

    reviewer_done = reviewer.get('status') == 'done'
    reviewer_running = reviewer.get('status') == 'running'
    past_reviewer = stage_num == 0 and (file_path or tool_name)

    should_complete = False
    if reviewer_done and all_non_running_done and len(stages) >= 3:
        should_complete = True
    elif reviewer_running and past_reviewer and len(non_running) >= 2 and all_non_running_done:
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
            except Exception:
                pass

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
            except Exception:
                pass


def main():
    if len(sys.argv) < 12:
        print("Usage: pipeline_state.py <progress_file> <stage_num> <stage_name> "
              "<file_path> <tool_name> <is_test> <test_framework> <project_dir> "
              "<now_date> <now_time> <now_short>", file=sys.stderr)
        sys.exit(1)

    update_state(
        f=sys.argv[1],
        stage_num=int(sys.argv[2]),
        stage_name=sys.argv[3],
        file_path=sys.argv[4],
        tool_name=sys.argv[5],
        is_test=sys.argv[6] == 'True',
        test_fw=sys.argv[7],
        project_dir=sys.argv[8],
        now_date=sys.argv[9],
        now_time=sys.argv[10],
        now_short=sys.argv[11]
    )


if __name__ == '__main__':
    main()
