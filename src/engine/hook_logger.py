#!/usr/bin/env python3
"""
Tasuki — Hook Activity Logger

Shared logging for all hooks. Appends events to activity-log.json.

Usage:
    python3 hook_logger.py <activity_file> <timestamp> <hook_name> <detail>
"""

import json
import sys


def log_event(activity_file, timestamp, hook_name, detail):
    """Append a hook_blocked event to activity-log.json."""
    try:
        with open(activity_file) as f:
            data = json.load(f)
        data['events'].append({
            'time': timestamp,
            'type': 'hook_blocked',
            'agent': hook_name,
            'detail': detail
        })
        data['events'] = data['events'][-100:]
        with open(activity_file, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


def main():
    if len(sys.argv) < 5:
        print("Usage: hook_logger.py <activity_file> <timestamp> <hook_name> <detail>",
              file=sys.stderr)
        sys.exit(1)

    log_event(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])


if __name__ == '__main__':
    main()
