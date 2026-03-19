#!/usr/bin/env python3
"""
Tasuki — Vault Memory Decay

Auto-demotes/promotes memories based on age and usage:
  high + 90 days no validation  → experimental
  experimental + 60 days        → deprecated
  deprecated + 30 days          → archived (moved to memory-vault/archive/)
  experimental + applied 3x     → promoted to high

Usage:
    python3 vault_decay.py <vault_dir> <today_date>

Arguments:
    vault_dir    Path to memory-vault/
    today_date   Current date as YYYY-MM-DD
"""

import os
import re
import sys
from datetime import datetime


# Thresholds
HIGH_TO_EXPERIMENTAL_DAYS = 90
EXPERIMENTAL_TO_DEPRECATED_DAYS = 60
DEPRECATED_TO_ARCHIVE_DAYS = 30
PROMOTE_THRESHOLD = 3  # applied count to promote experimental → high


def run_decay(vault, today_str):
    today = datetime.strptime(today_str, "%Y-%m-%d")
    changes = 0
    promoted = 0
    archived = 0

    archive_dir = os.path.join(vault, "archive")

    for root, dirs, files in os.walk(vault):
        # Skip archive directory
        if "archive" in root:
            continue
        for f in files:
            if not f.endswith('.md') or f == 'index.md':
                continue
            fpath = os.path.join(root, f)
            fname = f.replace('.md', '')
            rel = os.path.relpath(fpath, vault)
            ntype = rel.split('/')[0]

            # Only decay heuristics, bugs, lessons, decisions
            if ntype not in ('heuristics', 'bugs', 'lessons', 'decisions'):
                continue

            try:
                with open(fpath) as fh:
                    content = fh.read()
            except Exception:
                continue

            # Parse metadata
            conf_match = re.search(r'Confidence:\s*(\w+)', content)
            confidence = conf_match.group(1).lower() if conf_match else 'high'

            date_match = re.search(r'Last-Validated:\s*(\d{4}-\d{2}-\d{2})', content)
            if date_match:
                last_validated = datetime.strptime(date_match.group(1), "%Y-%m-%d")
            else:
                # Use file mtime as fallback
                last_validated = datetime.fromtimestamp(os.path.getmtime(fpath))

            applied_match = re.search(r'Applied-Count:\s*(\d+)', content)
            applied = int(applied_match.group(1)) if applied_match else 0

            days_since = (today - last_validated).days
            new_confidence = confidence

            # --- Promotion: experimental with 3+ applies → high ---
            if confidence == 'experimental' and applied >= PROMOTE_THRESHOLD:
                new_confidence = 'high'
                promoted += 1

            # --- Demotion based on age ---
            elif confidence == 'high' and days_since > HIGH_TO_EXPERIMENTAL_DAYS:
                new_confidence = 'experimental'
                changes += 1

            elif confidence == 'experimental' and days_since > EXPERIMENTAL_TO_DEPRECATED_DAYS:
                new_confidence = 'deprecated'
                changes += 1

            elif confidence == 'deprecated' and days_since > DEPRECATED_TO_ARCHIVE_DAYS:
                # Archive: move to memory-vault/archive/
                os.makedirs(archive_dir, exist_ok=True)
                dest = os.path.join(archive_dir, f)
                os.rename(fpath, dest)
                archived += 1
                print(f"  archived: {ntype}/{fname} (deprecated for {days_since} days)")
                continue

            # Update file if confidence changed
            if new_confidence != confidence:
                if 'Confidence:' in content:
                    content = re.sub(r'Confidence:\s*\w+', f'Confidence: {new_confidence}', content)
                else:
                    content = content.replace('Type:', f'Confidence: {new_confidence}\nType:', 1)

                # Update Last-Validated on promotion
                if new_confidence == 'high' and confidence == 'experimental':
                    content = re.sub(
                        r'Last-Validated:\s*\d{4}-\d{2}-\d{2}',
                        f'Last-Validated: {today.strftime("%Y-%m-%d")}', content
                    )

                with open(fpath, 'w') as fh:
                    fh.write(content)

                direction = "promoted" if new_confidence == 'high' else "demoted"
                print(f"  {direction}: {ntype}/{fname} ({confidence} → {new_confidence}, "
                      f"{days_since}d since validation, {applied}x applied)")

    total = changes + promoted + archived
    if total == 0:
        print("  All memories up to date. No decay needed.")
    else:
        print(f"  Summary: {changes} demoted, {promoted} promoted, {archived} archived")


def main():
    if len(sys.argv) < 3:
        print("Usage: vault_decay.py <vault_dir> <today_date>", file=sys.stderr)
        sys.exit(1)

    vault = sys.argv[1]
    today_str = sys.argv[2]

    if not os.path.isdir(vault):
        sys.exit(0)

    run_decay(vault, today_str)


if __name__ == '__main__':
    main()
