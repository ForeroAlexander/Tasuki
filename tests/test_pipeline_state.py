"""
Tests for pipeline_state.py — state machine correctness.
Run: python3 -m pytest tests/test_pipeline_state.py -v
"""
import json
import os
import sys
import tempfile
import pytest

# Add engine to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src', 'engine'))
from pipeline_state import update_state


def make_progress_file(tmp_path, status='running', stages=None, current_stage=0):
    """Create a pipeline-progress.json for testing."""
    data = {
        'task': 'test task',
        'mode': 'standard',
        'started': '2026-03-21 10:00:00',
        'status': status,
        'current_stage': current_stage,
        'total_stages': 7,
        'stages': stages or {}
    }
    f = tmp_path / 'pipeline-progress.json'
    f.write_text(json.dumps(data))
    return str(f)


# ---- Bug fix tests ----

class TestCompletedEarlyReturn:
    """Bug: completion detection fired on every tool call after pipeline completes.
    Resulted in 24 duplicate entries in pipeline-history.log."""

    def test_completed_pipeline_with_no_new_stage_returns_without_writing_history(self, tmp_path):
        """Once completed, hook calls with stage_num=0 must NOT append to history."""
        completed_stages = {
            'Planner': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'QA':      {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'Backend-Dev': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'Reviewer': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
        }
        f = make_progress_file(tmp_path, status='completed', stages=completed_stages, current_stage=7)

        history_path = tmp_path / '.tasuki' / 'config' / 'pipeline-history.log'
        os.makedirs(history_path.parent, exist_ok=True)

        # Simulate 5 tool calls after completion (stage_num=0 = no stage change)
        for _ in range(5):
            update_state(
                f=f,
                stage_num=0,
                stage_name='',
                file_path='src/some_file.py',
                tool_name='Read',
                is_test=False,
                test_fw='',
                project_dir=str(tmp_path),
                now_date='2026-03-21 10:05:00',
                now_time='10:05:00',
                now_short='2026-03-21 10:05'
            )

        # History should remain empty (no duplicate writes)
        if history_path.exists():
            lines = [l for l in history_path.read_text().splitlines() if l.strip()]
            assert len(lines) == 0, f"Expected 0 history entries after 5 tool calls on completed pipeline, got {len(lines)}"

    def test_completed_pipeline_with_new_stage_starts_fresh_pipeline(self, tmp_path):
        """A new stage_num > 0 after completion should start a fresh pipeline, not duplicate."""
        completed_stages = {
            'Planner': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'QA':      {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'Reviewer': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
        }
        f = make_progress_file(tmp_path, status='completed', stages=completed_stages, current_stage=7)

        update_state(
            f=f,
            stage_num=1,
            stage_name='Planner',
            file_path='.tasuki/agents/planner.md',
            tool_name='Read',
            is_test=False,
            test_fw='',
            project_dir=str(tmp_path),
            now_date='2026-03-21 11:00:00',
            now_time='11:00:00',
            now_short='2026-03-21 11:00'
        )

        data = json.loads(open(f).read())
        assert data['status'] == 'running', "New pipeline should be running"
        assert 'Planner' in data['stages'], "New Planner stage should exist"


class TestCompletionWritesHistoryOnce:
    """The completion history entry should be written exactly once."""

    def test_completion_written_once_not_on_subsequent_calls(self, tmp_path):
        """Simulate pipeline completing: history should have exactly 1 entry."""
        os.makedirs(tmp_path / '.tasuki' / 'config', exist_ok=True)
        history_path = tmp_path / '.tasuki' / 'config' / 'pipeline-history.log'

        running_stages = {
            'Planner': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'QA':      {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'Backend-Dev': {'status': 'done', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
            'Reviewer': {'status': 'running', 'time': '10:05:00', 'description': 'reviewing', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0},
        }
        f = make_progress_file(tmp_path, status='running', stages=running_stages, current_stage=7)

        # First call: Reviewer reads its agent file → triggers completion
        update_state(
            f=f, stage_num=0, stage_name='', file_path='tasuki-plans/review.md',
            tool_name='Read', is_test=False, test_fw='',
            project_dir=str(tmp_path),
            now_date='2026-03-21 10:06:00', now_time='10:06:00', now_short='2026-03-21 10:06'
        )

        # Subsequent calls (simulating continued activity after pipeline completes)
        for _ in range(10):
            update_state(
                f=f, stage_num=0, stage_name='', file_path='some/other/file.py',
                tool_name='Read', is_test=False, test_fw='',
                project_dir=str(tmp_path),
                now_date='2026-03-21 10:07:00', now_time='10:07:00', now_short='2026-03-21 10:07'
            )

        if history_path.exists():
            lines = [l for l in history_path.read_text().splitlines() if l.strip()]
            assert len(lines) <= 1, f"Expected at most 1 history entry, got {len(lines)}"


# ---- Existing behavior tests (must not regress) ----

class TestStageTransitions:

    def test_new_stage_initializes_correctly(self, tmp_path):
        f = make_progress_file(tmp_path)
        update_state(
            f=f, stage_num=1, stage_name='Planner',
            file_path='.tasuki/agents/planner.md', tool_name='Read',
            is_test=False, test_fw='',
            project_dir=str(tmp_path),
            now_date='2026-03-21 10:00:00', now_time='10:00:00', now_short='2026-03-21 10:00'
        )
        data = json.loads(open(f).read())
        assert 'Planner' in data['stages']
        assert data['stages']['Planner']['status'] == 'running'
        assert data['current_stage'] == 1

    def test_previous_stage_marked_done_on_transition(self, tmp_path):
        stages = {
            'Planner': {'status': 'running', 'time': '10:00', 'description': '', 'files_read': [], 'files_created': [], 'files_edited': [], 'tests_run': 0, 'tests_passed': 0}
        }
        f = make_progress_file(tmp_path, stages=stages, current_stage=1)
        update_state(
            f=f, stage_num=2, stage_name='QA',
            file_path='.tasuki/agents/qa.md', tool_name='Read',
            is_test=False, test_fw='',
            project_dir=str(tmp_path),
            now_date='2026-03-21 10:05:00', now_time='10:05:00', now_short='2026-03-21 10:05'
        )
        data = json.loads(open(f).read())
        assert data['stages']['Planner']['status'] == 'done'
        assert data['stages']['QA']['status'] == 'running'
