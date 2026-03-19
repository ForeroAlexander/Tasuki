#!/usr/bin/env python3
"""
Tasuki — Vault Graph Expansion (BFS)

Builds an in-memory graph of all vault nodes and performs BFS traversal
to find related memories N levels deep. O(V+E) complexity.

Usage:
    python3 vault_graph.py <vault_dir> <start_node> <max_depth> <confidence_filter> <project_dir>

Arguments:
    vault_dir          Path to memory-vault/
    start_node         Node name to expand from (e.g., "backend-dev")
    max_depth          BFS depth (0=direct, 1=one hop, 2=two hops)
    confidence_filter  Comma-separated allowed levels (e.g., "high,experimental")
    project_dir        Project root (for applied-count file updates)
"""

import os
import re
import sys
from collections import defaultdict, deque


def build_graph(vault):
    """Build forward and reverse index from vault .md files. Single os.walk pass."""
    nodes = {}
    reverse = defaultdict(set)

    for root, dirs, files in os.walk(vault):
        for f in files:
            if not f.endswith('.md') or f == 'index.md':
                continue
            fpath = os.path.join(root, f)
            fname = f.replace('.md', '')
            rel = os.path.relpath(fpath, vault)
            ntype = rel.split('/')[0]

            try:
                with open(fpath) as fh:
                    content = fh.read()
            except Exception:
                continue

            # Extract confidence level
            confidence = 'high'
            conf_match = re.search(r'Confidence:\s*(\w+)', content)
            if conf_match:
                confidence = conf_match.group(1).lower()

            # Extract applied count
            applied = 0
            applied_match = re.search(r'Applied-Count:\s*(\d+)', content)
            if applied_match:
                applied = int(applied_match.group(1))

            # Extract summary (first non-header, non-metadata line)
            lines = [
                l.strip() for l in content.split('\n')
                if l.strip() and not l.startswith('#') and l.strip() != '---'
                and not l.startswith('Type:') and not l.startswith('Confidence:')
                and not l.startswith('Last-Validated:') and not l.startswith('Applied-Count:')
                and not l.startswith('Severity:') and not l.startswith('Created:')
            ]
            summary = lines[0][:120] if lines else fname

            # Extract outgoing wikilinks
            links = set(re.findall(r'\[\[([a-z0-9_-]+)\]\]', content))

            nodes[fname] = {
                'type': ntype, 'summary': summary, 'links': links,
                'confidence': confidence, 'applied': applied,
                'path': fpath
            }

            # Build reverse index
            for link in links:
                reverse[link].add(fname)

    return nodes, reverse


def bfs_expand(nodes, reverse, start, max_depth, allowed_confidence):
    """BFS traversal from start node. Returns related nodes with metadata."""
    visited = set()
    queue = deque([(start, 0)])
    results = []

    while queue:
        current, depth = queue.popleft()
        if current in visited or depth > max_depth:
            continue
        visited.add(current)

        # Get neighbors: outgoing links + nodes that reference this one
        neighbors = set()
        if current in nodes:
            neighbors |= nodes[current]['links']
        neighbors |= reverse.get(current, set())

        for neighbor in neighbors:
            if neighbor in visited:
                continue
            if neighbor in nodes:
                n = nodes[neighbor]
                # Filter by confidence
                if n['confidence'] not in allowed_confidence:
                    continue
                conf_badge = ''
                if n['confidence'] == 'experimental':
                    conf_badge = ' [experimental]'
                elif n['confidence'] == 'deprecated':
                    conf_badge = ' [deprecated]'
                applied_badge = f" (applied {n['applied']}x)" if n['applied'] > 0 else ''
                results.append({
                    'type': n['type'],
                    'name': neighbor,
                    'summary': n['summary'],
                    'confidence': n['confidence'],
                    'badge': conf_badge + applied_badge,
                    'depth': depth + 1
                })
            if depth + 1 < max_depth:
                queue.append((neighbor, depth + 1))

    return results


def increment_applied_counts(nodes, results, vault):
    """Increment Applied-Count for heuristic nodes that were loaded."""
    for r in results:
        if r['type'] == 'heuristics' and r['name'] in nodes:
            hfile = nodes[r['name']].get('path', '')
            if not hfile or not os.path.exists(hfile):
                continue
            try:
                with open(hfile) as fh:
                    content = fh.read()
                m = re.search(r'Applied-Count:\s*(\d+)', content)
                if m:
                    count = int(m.group(1)) + 1
                    content = re.sub(r'Applied-Count:\s*\d+', f'Applied-Count: {count}', content)
                    with open(hfile, 'w') as fh:
                        fh.write(content)
            except Exception:
                pass


def format_output(results, start, max_depth, allowed_confidence):
    """Print formatted results to stdout."""
    # Deduplicate and exclude start node
    seen = set()
    unique = []
    for r in results:
        if r['name'] not in seen and r['name'] != start:
            seen.add(r['name'])
            unique.append(r)

    if not unique:
        print(f"  No related memories found for [[{start}]] (depth={max_depth})")
        return

    conf_str = ','.join(sorted(allowed_confidence))
    print(f"  Graph expansion for [[{start}]] (depth={max_depth}, mode={{{conf_str}}}):")

    # Sort by depth, then type
    type_order = {
        'heuristics': 0, 'bugs': 1, 'errors': 2, 'lessons': 3,
        'decisions': 4, 'architecture': 5, 'stack': 6, 'tools': 7, 'agents': 8
    }
    unique.sort(key=lambda x: (x['depth'], type_order.get(x['type'], 99)))

    for r in unique:
        print(f"      [{r['type']}] {r['name']}: {r['summary']}{r['badge']}")


def main():
    if len(sys.argv) < 5:
        print("Usage: vault_graph.py <vault_dir> <start_node> <max_depth> <confidence_filter> [project_dir]",
              file=sys.stderr)
        sys.exit(1)

    vault = sys.argv[1]
    start = sys.argv[2]
    max_depth = int(sys.argv[3])
    allowed_confidence = set(sys.argv[4].split(","))
    project_dir = sys.argv[5] if len(sys.argv) > 5 else os.path.dirname(vault)

    if not os.path.isdir(vault):
        sys.exit(0)

    nodes, reverse = build_graph(vault)
    results = bfs_expand(nodes, reverse, start, max_depth, allowed_confidence)
    increment_applied_counts(nodes, results, vault)
    format_output(results, start, max_depth, allowed_confidence)


if __name__ == '__main__':
    main()
