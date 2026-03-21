"""
tasuki spend — Real cost from Claude Code JSONL session files.

Usage:
    python3 spend.py <project_dir> [--today|--week|--all] [--json]
    python3 spend.py <project_dir> --session <uuid>
"""
import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import List, Optional

# ---------------------------------------------------------------------------
# Pricing (per 1M tokens, in USD)
# ---------------------------------------------------------------------------

PRICING = {
    'claude-opus':   {'input': 15.0,  'output': 75.0,  'cache_read': 1.50,  'cache_create': 18.75},
    'claude-sonnet': {'input': 3.0,   'output': 15.0,  'cache_read': 0.30,  'cache_create': 3.75},
    'claude-haiku':  {'input': 0.80,  'output': 4.0,   'cache_read': 0.08,  'cache_create': 1.00},
}


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

def encode_project_path(project_dir: str) -> str:
    """Convert an absolute project path to the Claude Code session directory name.

    Example: '/home/forero/tasuki' → '-home-forero-tasuki'
    """
    # Strip trailing slash, then leading slash, then replace remaining slashes
    path = project_dir.rstrip('/')
    path = path.lstrip('/')
    encoded = path.replace('/', '-')
    return '-' + encoded


def find_jsonl_dir(project_dir: str) -> Optional[Path]:
    """Return the Path to the Claude Code JSONL session directory, or None.

    Checks the primary location (~/.claude/projects/<encoded>) first,
    then falls back to ~/.config/claude/projects/<encoded>.
    Uses Path.home() so tests can monkeypatch it.
    """
    encoded = encode_project_path(project_dir)
    home = Path.home()

    primary = home / '.claude' / 'projects' / encoded
    if primary.is_dir():
        return primary

    fallback = home / '.config' / 'claude' / 'projects' / encoded
    if fallback.is_dir():
        return fallback

    return None


# ---------------------------------------------------------------------------
# JSONL parsing
# ---------------------------------------------------------------------------

def parse_session(jsonl_path: Path) -> List[dict]:
    """Parse one Claude Code .jsonl file and return usage records.

    Each record is a dict with keys:
        timestamp, model, input_tokens, output_tokens, cache_read, cache_create

    Non-assistant entries and malformed lines are silently skipped.
    """
    records: List[dict] = []

    try:
        text = jsonl_path.read_text(encoding='utf-8')
    except OSError:
        return records

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue

        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        if entry.get('type') != 'assistant':
            continue

        message = entry.get('message', {})
        usage = message.get('usage', {})

        records.append({
            'timestamp':    entry.get('timestamp', ''),
            'model':        message.get('model', 'unknown'),
            'input_tokens': usage.get('input_tokens', 0),
            'output_tokens': usage.get('output_tokens', 0),
            'cache_read':   usage.get('cache_read_input_tokens', 0),
            'cache_create': usage.get('cache_creation_input_tokens', 0),
        })

    return records


# ---------------------------------------------------------------------------
# Cost calculation
# ---------------------------------------------------------------------------

def _find_family(model_name: str) -> Optional[str]:
    """Return the PRICING family key that matches model_name, or None."""
    lower = model_name.lower()
    for family in PRICING:
        if family in lower:
            return family
    return None


def calculate_cost(record: dict) -> float:
    """Return the USD cost for a single usage record."""
    family = _find_family(record['model'])
    if family is None:
        return 0.0

    p = PRICING[family]
    cost = (
        record['input_tokens']  * p['input']
        + record['output_tokens'] * p['output']
        + record['cache_read']    * p['cache_read']
        + record['cache_create']  * p['cache_create']
    ) / 1_000_000

    return cost


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

def aggregate(records: List[dict], since: Optional[str] = None) -> dict:
    """Aggregate usage records, optionally filtered by date window.

    since:
        None     → include all records
        'today'  → only records from today
        'week'   → records from the last 7 days (today - 6 days inclusive)
    """
    # Filter by date window
    if since is None:
        filtered = records
    else:
        today = date.today()
        if since == 'today':
            filtered = [
                r for r in records
                if r['timestamp'] and date.fromisoformat(r['timestamp'][:10]) == today
            ]
        elif since == 'week':
            cutoff = today - timedelta(days=6)
            filtered = [
                r for r in records
                if r['timestamp'] and date.fromisoformat(r['timestamp'][:10]) >= cutoff
            ]
        else:
            filtered = records

    if not filtered:
        return {
            'total_usd':  0.0,
            'by_model':   {},
            'sessions':   0,
            'messages':   0,
            'date_range': {'from': '', 'to': ''},
        }

    # Group by model family
    by_model: dict = {}
    for r in filtered:
        family = _find_family(r['model'])
        if family is None:
            continue
        if family not in by_model:
            by_model[family] = {
                'input': 0, 'output': 0, 'cache_read': 0, 'cache_create': 0, 'usd': 0.0,
            }
        entry = by_model[family]
        entry['input']        += r['input_tokens']
        entry['output']       += r['output_tokens']
        entry['cache_read']   += r['cache_read']
        entry['cache_create'] += r['cache_create']
        entry['usd']          += calculate_cost(r)

    total_usd = sum(v['usd'] for v in by_model.values())

    timestamps = [r['timestamp'][:10] for r in filtered if r['timestamp']]
    date_from = min(timestamps) if timestamps else ''
    date_to   = max(timestamps) if timestamps else ''

    return {
        'total_usd':  total_usd,
        'by_model':   by_model,
        'sessions':   len(set(r.get('session_id', '') for r in filtered if r.get('session_id'))),
        'messages':   len(filtered),
        'date_range': {'from': date_from, 'to': date_to},
    }


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

def format_report(agg: dict, fmt: str = 'human') -> str:
    """Format the aggregation result for display.

    fmt='json'  → compact JSON
    fmt='human' → human-readable terminal output
    """
    if fmt == 'json':
        return json.dumps(agg, indent=2)

    lines = []
    date_from = agg['date_range'].get('from', '')
    date_to   = agg['date_range'].get('to', '')

    lines.append(f"Real Spend Report")
    lines.append(f"{'═' * 40}")
    lines.append(f"Messages:  {agg['messages']}")
    lines.append(f"Sessions:  {agg['sessions']}")
    if date_from:
        lines.append(f"Period:    {date_from} → {date_to}")
    lines.append("")

    by_model = agg.get('by_model', {})
    if by_model:
        for family, entry in sorted(by_model.items()):
            lines.append(f"  {family}")
            lines.append(
                f"    Input:  {entry['input']:>12,}  "
                f"Output: {entry['output']:>12,}  "
                f"Cache read: {entry['cache_read']:>14,}"
            )
            lines.append(f"    Cost: ${entry['usd']:.4f}")
        lines.append("")
        lines.append(f"  {'─' * 36}")

    lines.append(f"  Total: ${agg['total_usd']:.4f}")
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    """Parse CLI arguments and print the spend report."""
    argv = sys.argv[1:]

    if not argv:
        print("Usage: spend.py <project_dir> [--today|--week|--all] [--json] [--session UUID]",
              file=sys.stderr)
        sys.exit(1)

    project_dir = argv[0]
    remaining = argv[1:]

    since: Optional[str] = 'today'  # default
    fmt = 'human'
    session_uuid: Optional[str] = None

    i = 0
    while i < len(remaining):
        arg = remaining[i]
        if arg == '--today':
            since = 'today'
        elif arg == '--week':
            since = 'week'
        elif arg == '--all':
            since = None
        elif arg == '--json':
            fmt = 'json'
        elif arg == '--session':
            i += 1
            if i < len(remaining):
                session_uuid = remaining[i]
        i += 1

    jsonl_dir = find_jsonl_dir(project_dir)
    if jsonl_dir is None:
        print(f"No session data found for project: {project_dir}")
        print("(Checked ~/.claude/projects/ and ~/.config/claude/projects/)")
        sys.exit(0)

    records: List[dict] = []
    if session_uuid:
        # Validate UUID format to prevent path traversal
        if not re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', session_uuid, re.IGNORECASE):
            print("Invalid session ID format.", file=sys.stderr)
            sys.exit(1)
        session_file = jsonl_dir / f"{session_uuid}.jsonl"
        # Containment check: resolved path must stay within jsonl_dir
        if not session_file.resolve().is_relative_to(jsonl_dir.resolve()):
            print("Invalid session ID.", file=sys.stderr)
            sys.exit(1)
        if session_file.exists():
            records = parse_session(session_file)
        else:
            print("Session file not found.", file=sys.stderr)
            sys.exit(1)
    else:
        for jsonl_file in sorted(jsonl_dir.glob('*.jsonl')):
            records.extend(parse_session(jsonl_file))

    agg = aggregate(records, since=since)
    print(format_report(agg, fmt=fmt))


if __name__ == '__main__':
    main()
