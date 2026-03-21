"""
Tests for spend.py — real cost tracking from Claude Code JSONL sessions.

Run: python3 -m pytest tests/test_spend.py -v

TDD RED PHASE: The implementation (src/engine/spend.py) does NOT exist yet.
All tests here are expected to FAIL until backend-dev implements the module.
"""
import json
import os
import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

# Add src/engine to path so we can import spend
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src', 'engine'))

# This import will fail (ModuleNotFoundError) until spend.py is created — that's the red phase.
import spend


# ---------------------------------------------------------------------------
# Helpers / factories
# ---------------------------------------------------------------------------

def make_jsonl_line(
    msg_type='assistant',
    model='claude-sonnet-4-6',
    timestamp='2026-03-21T10:00:00.000Z',
    input_tokens=100,
    output_tokens=200,
    cache_read=50,
    cache_create=10,
):
    """Return a JSON string representing one JSONL line as Claude Code writes it."""
    return json.dumps({
        'type': msg_type,
        'timestamp': timestamp,
        'message': {
            'role': msg_type if msg_type != 'assistant' else 'assistant',
            'model': model,
            'usage': {
                'input_tokens': input_tokens,
                'output_tokens': output_tokens,
                'cache_read_input_tokens': cache_read,
                'cache_creation_input_tokens': cache_create,
            },
        },
    })


def write_jsonl(path, lines):
    """Write a list of raw strings to a .jsonl file, one per line."""
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


# ---------------------------------------------------------------------------
# 1. encode_project_path
# ---------------------------------------------------------------------------

class TestEncodeProjectPath:
    """Unit tests for encode_project_path(project_dir)."""

    def test_standard_path_replaces_slashes_with_dashes(self):
        """'/home/user/myproject' should become '-home-user-myproject'."""
        assert spend.encode_project_path('/home/user/myproject') == '-home-user-myproject'

    def test_tasuki_project_path(self):
        """'/home/forero/tasuki' should become '-home-forero-tasuki'."""
        assert spend.encode_project_path('/home/forero/tasuki') == '-home-forero-tasuki'

    def test_trailing_slash_is_stripped(self):
        """Trailing slash must be removed before encoding."""
        assert spend.encode_project_path('/home/user/myproject/') == '-home-user-myproject'

    def test_root_path(self):
        """Root '/' should encode to '-'."""
        assert spend.encode_project_path('/') == '-'

    def test_single_level_path(self):
        """'/tmp' should become '-tmp'."""
        assert spend.encode_project_path('/tmp') == '-tmp'

    def test_deep_path(self):
        """Deep nesting is encoded correctly."""
        assert spend.encode_project_path('/a/b/c/d') == '-a-b-c-d'


# ---------------------------------------------------------------------------
# 2. find_jsonl_dir
# ---------------------------------------------------------------------------

class TestFindJsonlDir:
    """Unit tests for find_jsonl_dir(project_dir).

    We monkeypatch Path.home() so the function uses tmp_path as the home
    directory, keeping tests hermetic and independent of the real filesystem.
    """

    def _make_primary_dir(self, home: Path, encoded: str) -> Path:
        """Create ~/.claude/projects/<encoded>/ and return it."""
        d = home / '.claude' / 'projects' / encoded
        d.mkdir(parents=True)
        return d

    def _make_fallback_dir(self, home: Path, encoded: str) -> Path:
        """Create ~/.config/claude/projects/<encoded>/ and return it."""
        d = home / '.config' / 'claude' / 'projects' / encoded
        d.mkdir(parents=True)
        return d

    def test_returns_path_when_primary_dir_exists(self, tmp_path, monkeypatch):
        """Returns Path to ~/.claude/projects/<encoded>/ when it exists."""
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))
        project_dir = '/home/forero/tasuki'
        encoded = spend.encode_project_path(project_dir)
        expected = self._make_primary_dir(tmp_path, encoded)

        result = spend.find_jsonl_dir(project_dir)

        assert result is not None
        assert isinstance(result, Path)
        assert result == expected

    def test_returns_none_when_no_dir_exists(self, tmp_path, monkeypatch):
        """Returns None when neither primary nor fallback directory exists."""
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))

        result = spend.find_jsonl_dir('/home/forero/tasuki')

        assert result is None

    def test_falls_back_to_config_dir_when_primary_missing(self, tmp_path, monkeypatch):
        """Uses ~/.config/claude/projects/ as fallback when primary is absent."""
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))
        project_dir = '/home/forero/tasuki'
        encoded = spend.encode_project_path(project_dir)
        expected = self._make_fallback_dir(tmp_path, encoded)

        result = spend.find_jsonl_dir(project_dir)

        assert result is not None
        assert result == expected

    def test_primary_preferred_over_fallback_when_both_exist(self, tmp_path, monkeypatch):
        """Primary (~/.claude) is preferred when both directories exist."""
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))
        project_dir = '/home/forero/tasuki'
        encoded = spend.encode_project_path(project_dir)
        primary = self._make_primary_dir(tmp_path, encoded)
        self._make_fallback_dir(tmp_path, encoded)

        result = spend.find_jsonl_dir(project_dir)

        assert result == primary


# ---------------------------------------------------------------------------
# 3. parse_session
# ---------------------------------------------------------------------------

class TestParseSession:
    """Unit tests for parse_session(jsonl_path)."""

    def test_returns_list_of_usage_records(self, tmp_path):
        """Each assistant entry produces one usage record dict."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [make_jsonl_line()])

        records = spend.parse_session(f)

        assert isinstance(records, list)
        assert len(records) == 1

    def test_record_has_required_keys(self, tmp_path):
        """Each record must contain timestamp, model, and the four token counts."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [make_jsonl_line()])

        record = spend.parse_session(f)[0]

        required_keys = {'timestamp', 'model', 'input_tokens', 'output_tokens', 'cache_read', 'cache_create'}
        assert required_keys == set(record.keys())

    def test_record_values_are_correct_types(self, tmp_path):
        """Token counts must be int; timestamp and model must be str."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [make_jsonl_line(
            model='claude-opus-4-6',
            timestamp='2026-03-21T10:00:00.000Z',
            input_tokens=100,
            output_tokens=200,
            cache_read=50,
            cache_create=10,
        )])

        record = spend.parse_session(f)[0]

        assert isinstance(record['timestamp'], str)
        assert isinstance(record['model'], str)
        assert isinstance(record['input_tokens'], int)
        assert isinstance(record['output_tokens'], int)
        assert isinstance(record['cache_read'], int)
        assert isinstance(record['cache_create'], int)

    def test_skips_non_assistant_entries(self, tmp_path):
        """Only entries with type='assistant' are returned."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [
            make_jsonl_line(msg_type='user'),
            make_jsonl_line(msg_type='assistant'),
            make_jsonl_line(msg_type='tool_result'),
        ])

        records = spend.parse_session(f)

        assert len(records) == 1

    def test_handles_malformed_json_lines_gracefully(self, tmp_path):
        """Malformed lines are skipped; no exception is raised."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [
            '{not valid json',
            make_jsonl_line(),
            'another broken line :::',
        ])

        records = spend.parse_session(f)

        # Only the valid assistant entry should be returned
        assert len(records) == 1

    def test_handles_missing_usage_fields_with_defaults(self, tmp_path):
        """Missing token fields default to 0 instead of raising KeyError."""
        line = json.dumps({
            'type': 'assistant',
            'timestamp': '2026-03-21T10:00:00.000Z',
            'message': {
                'model': 'claude-sonnet-4-6',
                'usage': {},  # All token fields absent
            },
        })
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [line])

        records = spend.parse_session(f)

        assert len(records) == 1
        record = records[0]
        assert record['input_tokens'] == 0
        assert record['output_tokens'] == 0
        assert record['cache_read'] == 0
        assert record['cache_create'] == 0

    def test_multiple_assistant_entries_all_returned(self, tmp_path):
        """All assistant entries in the file are parsed."""
        f = tmp_path / 'session.jsonl'
        lines = [make_jsonl_line(input_tokens=i * 10) for i in range(1, 6)]
        write_jsonl(f, lines)

        records = spend.parse_session(f)

        assert len(records) == 5

    def test_empty_file_returns_empty_list(self, tmp_path):
        """An empty JSONL file returns an empty list without error."""
        f = tmp_path / 'session.jsonl'
        f.write_text('', encoding='utf-8')

        records = spend.parse_session(f)

        assert records == []

    def test_entry_missing_usage_key_entirely_is_skipped_or_defaults(self, tmp_path):
        """An entry with no 'usage' key at all is skipped gracefully."""
        line = json.dumps({
            'type': 'assistant',
            'timestamp': '2026-03-21T10:00:00.000Z',
            'message': {
                'model': 'claude-sonnet-4-6',
                # No 'usage' key
            },
        })
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [line])

        # Must not raise; either skip the record or return it with zeros
        try:
            records = spend.parse_session(f)
            if records:
                assert records[0]['input_tokens'] == 0
        except Exception as exc:
            pytest.fail(f"parse_session raised unexpectedly: {exc}")

    def test_correct_token_values_extracted(self, tmp_path):
        """Token values in the record match what was in the JSONL."""
        f = tmp_path / 'session.jsonl'
        write_jsonl(f, [make_jsonl_line(
            input_tokens=1234,
            output_tokens=5678,
            cache_read=999,
            cache_create=42,
        )])

        record = spend.parse_session(f)[0]

        assert record['input_tokens'] == 1234
        assert record['output_tokens'] == 5678
        assert record['cache_read'] == 999
        assert record['cache_create'] == 42


# ---------------------------------------------------------------------------
# 4. PRICING and calculate_cost
# ---------------------------------------------------------------------------

class TestPricing:
    """Verify the PRICING dict has the required model families and rates."""

    def test_pricing_has_opus_family(self):
        """PRICING must contain 'claude-opus' key."""
        assert 'claude-opus' in spend.PRICING

    def test_pricing_has_sonnet_family(self):
        """PRICING must contain 'claude-sonnet' key."""
        assert 'claude-sonnet' in spend.PRICING

    def test_pricing_has_haiku_family(self):
        """PRICING must contain 'claude-haiku' key."""
        assert 'claude-haiku' in spend.PRICING

    def test_opus_rates(self):
        """claude-opus: input=$15/M, output=$75/M, cache_read=$1.50/M, cache_create=$18.75/M."""
        p = spend.PRICING['claude-opus']
        assert p['input'] == pytest.approx(15.0)
        assert p['output'] == pytest.approx(75.0)
        assert p['cache_read'] == pytest.approx(1.50)
        assert p['cache_create'] == pytest.approx(18.75)

    def test_sonnet_rates(self):
        """claude-sonnet: input=$3/M, output=$15/M, cache_read=$0.30/M, cache_create=$3.75/M."""
        p = spend.PRICING['claude-sonnet']
        assert p['input'] == pytest.approx(3.0)
        assert p['output'] == pytest.approx(15.0)
        assert p['cache_read'] == pytest.approx(0.30)
        assert p['cache_create'] == pytest.approx(3.75)

    def test_haiku_rates(self):
        """claude-haiku: input=$0.80/M, output=$4/M, cache_read=$0.08/M, cache_create=$1.00/M."""
        p = spend.PRICING['claude-haiku']
        assert p['input'] == pytest.approx(0.80)
        assert p['output'] == pytest.approx(4.0)
        assert p['cache_read'] == pytest.approx(0.08)
        assert p['cache_create'] == pytest.approx(1.00)


class TestCalculateCost:
    """Unit tests for calculate_cost(record)."""

    def _record(self, model, input_tokens=0, output_tokens=0, cache_read=0, cache_create=0):
        return {
            'timestamp': '2026-03-21T10:00:00.000Z',
            'model': model,
            'input_tokens': input_tokens,
            'output_tokens': output_tokens,
            'cache_read': cache_read,
            'cache_create': cache_create,
        }

    def test_opus_cost_calculation(self):
        """1M input + 1M output for opus = $15 + $75 = $90."""
        record = self._record('claude-opus-4-6', input_tokens=1_000_000, output_tokens=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(90.0)

    def test_sonnet_cost_calculation(self):
        """1M input + 1M output for sonnet = $3 + $15 = $18."""
        record = self._record('claude-sonnet-4-6', input_tokens=1_000_000, output_tokens=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(18.0)

    def test_haiku_cost_calculation(self):
        """1M input + 1M output for haiku = $0.80 + $4.00 = $4.80."""
        record = self._record('claude-haiku', input_tokens=1_000_000, output_tokens=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(4.80)

    def test_cache_read_tokens_are_priced(self):
        """1M cache_read tokens for sonnet = $0.30."""
        record = self._record('claude-sonnet-4-6', cache_read=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(0.30)

    def test_cache_create_tokens_are_priced(self):
        """1M cache_create tokens for opus = $18.75."""
        record = self._record('claude-opus-4-6', cache_create=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(18.75)

    def test_unknown_model_returns_zero_no_crash(self):
        """An unknown model family must return 0.0, not raise an exception."""
        record = self._record('some-unknown-model-xyz', input_tokens=1_000_000)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(0.0)

    def test_zero_tokens_returns_zero_cost(self):
        """All-zero token counts produce $0.00 cost."""
        record = self._record('claude-sonnet-4-6')
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(0.0)

    def test_partial_token_counts(self):
        """Small but non-zero token counts produce fractional costs."""
        # 100 input tokens for sonnet: 100 * 3.0 / 1_000_000 = 0.0003
        record = self._record('claude-sonnet-4-6', input_tokens=100)
        cost = spend.calculate_cost(record)
        assert cost == pytest.approx(100 * 3.0 / 1_000_000)

    def test_model_matching_is_substring_case_insensitive(self):
        """'claude-opus-4-6' must match the 'claude-opus' pricing family."""
        record = self._record('claude-opus-4-6', input_tokens=1_000_000)
        cost = spend.calculate_cost(record)
        # Should be priced at opus rates, not zero
        assert cost > 0.0

    def test_combined_all_token_types_correct_sum(self):
        """Total cost is the sum of all four token type costs."""
        input_tok = 500_000
        output_tok = 250_000
        cache_r = 100_000
        cache_c = 50_000
        record = self._record(
            'claude-sonnet-4-6',
            input_tokens=input_tok,
            output_tokens=output_tok,
            cache_read=cache_r,
            cache_create=cache_c,
        )
        expected = (
            input_tok * 3.0
            + output_tok * 15.0
            + cache_r * 0.30
            + cache_c * 3.75
        ) / 1_000_000

        cost = spend.calculate_cost(record)

        assert cost == pytest.approx(expected)


# ---------------------------------------------------------------------------
# 5. aggregate
# ---------------------------------------------------------------------------

class TestAggregate:
    """Unit tests for aggregate(records, since=None)."""

    TODAY = '2026-03-21'
    TODAY_TS = '2026-03-21T10:00:00.000Z'
    YESTERDAY_TS = '2026-03-20T10:00:00.000Z'
    EIGHT_DAYS_AGO_TS = '2026-03-13T10:00:00.000Z'

    def _record(self, timestamp, model='claude-sonnet-4-6',
                input_tokens=100, output_tokens=200, cache_read=0, cache_create=0):
        return {
            'timestamp': timestamp,
            'model': model,
            'input_tokens': input_tokens,
            'output_tokens': output_tokens,
            'cache_read': cache_read,
            'cache_create': cache_create,
        }

    # --- Return shape ---

    def test_empty_records_returns_zero_totals(self):
        """Empty input produces zeros and empty collections."""
        result = spend.aggregate([])

        assert result['total_usd'] == pytest.approx(0.0)
        assert result['by_model'] == {}
        assert result['messages'] == 0

    def test_result_has_required_keys(self):
        """Aggregate result must contain total_usd, by_model, sessions, messages, date_range."""
        result = spend.aggregate([])
        required = {'total_usd', 'by_model', 'sessions', 'messages', 'date_range'}
        assert required.issubset(set(result.keys()))

    def test_date_range_present_with_records(self):
        """date_range must have 'from' and 'to' keys when records exist."""
        records = [self._record(self.TODAY_TS)]
        result = spend.aggregate(records)

        assert 'from' in result['date_range']
        assert 'to' in result['date_range']

    # --- since=None (all records) ---

    def test_since_none_includes_all_records(self):
        """since=None includes records from any date."""
        records = [
            self._record(self.TODAY_TS),
            self._record(self.YESTERDAY_TS),
            self._record(self.EIGHT_DAYS_AGO_TS),
        ]
        result = spend.aggregate(records, since=None)

        assert result['messages'] == 3

    # --- since='today' ---

    def test_since_today_excludes_yesterday(self):
        """since='today' keeps only today's records."""
        records = [
            self._record(self.TODAY_TS),
            self._record(self.YESTERDAY_TS),
        ]
        with patch('spend.date') as mock_date:
            mock_date.today.return_value = date(2026, 3, 21)
            mock_date.fromisoformat = date.fromisoformat
            result = spend.aggregate(records, since='today')

        assert result['messages'] == 1

    def test_since_today_includes_multiple_today_records(self):
        """All of today's records are counted with since='today'."""
        records = [
            self._record('2026-03-21T08:00:00.000Z'),
            self._record('2026-03-21T12:00:00.000Z'),
            self._record('2026-03-21T23:59:00.000Z'),
            self._record(self.YESTERDAY_TS),
        ]
        with patch('spend.date') as mock_date:
            mock_date.today.return_value = date(2026, 3, 21)
            mock_date.fromisoformat = date.fromisoformat
            result = spend.aggregate(records, since='today')

        assert result['messages'] == 3

    # --- since='week' ---

    def test_since_week_excludes_eight_days_ago(self):
        """since='week' excludes records older than 7 days (today minus 6 days = window start)."""
        records = [
            self._record(self.TODAY_TS),
            self._record(self.YESTERDAY_TS),
            self._record(self.EIGHT_DAYS_AGO_TS),
        ]
        with patch('spend.date') as mock_date:
            mock_date.today.return_value = date(2026, 3, 21)
            mock_date.fromisoformat = date.fromisoformat
            result = spend.aggregate(records, since='week')

        # today + yesterday = 2; eight_days_ago excluded
        assert result['messages'] == 2

    def test_since_week_includes_boundary_day(self):
        """since='week' includes the record exactly at today-6 days."""
        six_days_ago = '2026-03-15T10:00:00.000Z'  # 2026-03-21 - 6 = 2026-03-15
        records = [
            self._record(self.TODAY_TS),
            self._record(six_days_ago),
        ]
        with patch('spend.date') as mock_date:
            mock_date.today.return_value = date(2026, 3, 21)
            mock_date.fromisoformat = date.fromisoformat
            result = spend.aggregate(records, since='week')

        assert result['messages'] == 2

    # --- by_model grouping ---

    def test_by_model_groups_by_family(self):
        """Records from the same model family are grouped together in by_model."""
        records = [
            self._record(self.TODAY_TS, model='claude-sonnet-4-6', input_tokens=100),
            self._record(self.TODAY_TS, model='claude-sonnet-4-6', input_tokens=200),
        ]
        result = spend.aggregate(records)

        assert 'claude-sonnet' in result['by_model']
        assert result['by_model']['claude-sonnet']['input'] == 300

    def test_by_model_separates_different_families(self):
        """Opus and sonnet records end up in separate by_model entries."""
        records = [
            self._record(self.TODAY_TS, model='claude-opus-4-6', input_tokens=500),
            self._record(self.TODAY_TS, model='claude-sonnet-4-6', input_tokens=100),
        ]
        result = spend.aggregate(records)

        assert 'claude-opus' in result['by_model']
        assert 'claude-sonnet' in result['by_model']
        assert result['by_model']['claude-opus']['input'] == 500
        assert result['by_model']['claude-sonnet']['input'] == 100

    def test_by_model_entry_has_usd_key(self):
        """Each model family entry in by_model must include a 'usd' cost field."""
        records = [self._record(self.TODAY_TS, model='claude-sonnet-4-6')]
        result = spend.aggregate(records)

        assert 'usd' in result['by_model']['claude-sonnet']

    def test_total_usd_equals_sum_of_by_model_usd(self):
        """total_usd must equal the sum of all by_model usd values."""
        records = [
            self._record(self.TODAY_TS, model='claude-opus-4-6', input_tokens=1_000_000),
            self._record(self.TODAY_TS, model='claude-sonnet-4-6', input_tokens=1_000_000),
        ]
        result = spend.aggregate(records)

        model_total = sum(v['usd'] for v in result['by_model'].values())
        assert result['total_usd'] == pytest.approx(model_total)

    def test_messages_count_equals_number_of_records(self):
        """messages field reflects the number of records after filtering."""
        records = [self._record(self.TODAY_TS) for _ in range(7)]
        result = spend.aggregate(records)

        assert result['messages'] == 7

    def test_unknown_model_excluded_from_by_model(self):
        """Records with an unknown model family produce no by_model entry (cost = 0)."""
        records = [self._record(self.TODAY_TS, model='claude-unknown-xyz')]
        result = spend.aggregate(records)

        # Should not crash; total_usd is 0
        assert result['total_usd'] == pytest.approx(0.0)

    def test_date_range_from_to_are_correct(self):
        """date_range 'from' and 'to' reflect the earliest and latest record timestamps."""
        records = [
            self._record('2026-03-19T10:00:00.000Z'),
            self._record('2026-03-21T10:00:00.000Z'),
            self._record('2026-03-20T10:00:00.000Z'),
        ]
        result = spend.aggregate(records)

        assert result['date_range']['from'] <= result['date_range']['to']
        assert '2026-03-19' in result['date_range']['from']
        assert '2026-03-21' in result['date_range']['to']

    def test_by_model_sums_all_token_types(self):
        """by_model entry sums input, output, cache_read, and cache_create across records."""
        records = [
            self._record(self.TODAY_TS, model='claude-sonnet-4-6',
                         input_tokens=100, output_tokens=200, cache_read=50, cache_create=10),
            self._record(self.TODAY_TS, model='claude-sonnet-4-6',
                         input_tokens=100, output_tokens=200, cache_read=50, cache_create=10),
        ]
        result = spend.aggregate(records)

        entry = result['by_model']['claude-sonnet']
        assert entry['input'] == 200
        assert entry['output'] == 400
        assert entry['cache_read'] == 100
        assert entry['cache_create'] == 20


# ---------------------------------------------------------------------------
# 6. Graceful failure — no JSONL directory
# ---------------------------------------------------------------------------

class TestGracefulFailure:
    """When no JSONL directory exists, the CLI must exit cleanly with a message."""

    def test_find_jsonl_dir_returns_none_when_missing(self, tmp_path, monkeypatch):
        """find_jsonl_dir returns None (not raises) when directory is absent."""
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))
        result = spend.find_jsonl_dir('/home/forero/tasuki')
        assert result is None

    def test_cli_exits_cleanly_when_no_jsonl_dir(self, tmp_path, monkeypatch, capsys):
        """When find_jsonl_dir returns None, spend module handles it gracefully.

        Either main() prints a friendly message and exits 0, or it raises SystemExit
        — both are acceptable as long as there is no unhandled exception/traceback.
        """
        monkeypatch.setattr(Path, 'home', staticmethod(lambda: tmp_path))
        # Patch sys.argv to simulate CLI invocation
        monkeypatch.setattr(sys, 'argv', ['spend.py', str(tmp_path)])

        try:
            spend.main()
            captured = capsys.readouterr()
            # A human-readable message should appear on stdout or stderr
            output = captured.out + captured.err
            assert len(output) > 0, "Expected some output when no JSONL dir found"
        except SystemExit as exc:
            # Clean exit is acceptable; only non-zero exit with no message would be a bug
            assert exc.code in (0, 1), f"Unexpected exit code: {exc.code}"
        except Exception as exc:
            pytest.fail(f"spend.main() raised unhandled exception when no JSONL dir: {exc}")
