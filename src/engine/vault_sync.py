#!/usr/bin/env python3
"""
Tasuki — Vault RAG Sync

Indexes project data into rag-sync-batch.jsonl for deep memory queries.
Indexes: memory vault, database schema, API routes, plans, git history, config files.

Usage:
    python3 vault_sync.py <action> <project_dir> <json_file> [extra_args...]

Actions:
    memory   <project_dir> <json_file> <node_file> <node_type> <node_name> <tags>
    schema   <project_dir> <json_file>
    api      <project_dir> <json_file>
    plan     <project_dir> <json_file> <plan_file> <feature_dir> <plan_name>
    git      <project_dir> <json_file>
    config   <project_dir> <json_file> <cfg_file> <cfg_name>
    query    <batch_file> <query>
    setup    <mcp_file> <project_dir>
"""

import json
import os
import re
import subprocess
import sys


EXCLUDE_DIRS = {'node_modules', '.git', '__pycache__', '.venv', 'venv', '.tasuki', 'memory-vault'}


def sync_memory(node_file, node_type, node_name, tags, json_file):
    """Index a single memory vault node."""
    content = open(node_file).read()
    entry = {
        'id': f'vault/{node_type}/{node_name}',
        'type': node_type,
        'name': node_name,
        'tags': tags,
        'content': content
    }
    print(json.dumps(entry))


def sync_schema(project_dir, json_file):
    """Index database model files and migrations."""
    count = 0

    for root, dirs, files in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if not f.endswith('.py'):
                continue
            fpath = os.path.join(root, f)
            rel = os.path.relpath(fpath, project_dir)

            if '/models/' not in rel and '/models.py' not in rel and '/entities/' not in rel:
                continue

            try:
                content = open(fpath).read()
            except Exception:
                continue

            if not re.search(r'class \w+.*(?:Base|Model|db\.Model|DeclarativeBase)', content):
                continue

            models = re.findall(r'class (\w+)\(', content)
            app_name = os.path.basename(os.path.dirname(fpath))

            entry = {
                'id': f'schema/{app_name}/{f.replace(".py", "")}',
                'type': 'schema',
                'name': f'{app_name}/{f}' if f != 'models.py' else f'{app_name} models',
                'tags': ','.join(models[:10]),
                'content': content[:3000]
            }
            with open(json_file, 'a') as jf:
                jf.write(json.dumps(entry) + '\n')
            count += 1

    # Also index recent migrations (last 10)
    mig_files = []
    for root, dirs, files in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        if 'migrations' in root or 'alembic' in root or 'versions' in root:
            for f in sorted(files):
                if f.endswith('.py') and f != '__init__.py':
                    mig_files.append(os.path.join(root, f))

    for fpath in mig_files[-10:]:
        try:
            content = open(fpath).read()[:2000]
        except Exception:
            continue
        mig_name = os.path.basename(fpath).replace('.py', '')
        entry = {
            'id': f'schema/migrations/{mig_name}',
            'type': 'migration',
            'name': mig_name,
            'tags': 'schema,migration,database',
            'content': content
        }
        with open(json_file, 'a') as jf:
            jf.write(json.dumps(entry) + '\n')
        count += 1


def sync_api(project_dir, json_file):
    """Index API route/view/serializer files."""
    count = 0

    for root, dirs, files in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if not f.endswith('.py') and not f.endswith('.ts'):
                continue
            fpath = os.path.join(root, f)
            rel = os.path.relpath(fpath, project_dir)

            api_paths = ['/routers/', '/views/', '/routes/', '/controllers/',
                         '/endpoints/', '/serializers/', '/schemas/']
            if not any(p in rel for p in api_paths):
                continue

            try:
                content = open(fpath).read()
            except Exception:
                continue

            if not re.search(
                r'@router\.|@app\.|APIRouter|@Get|@Post|@Put|@Delete|class.*View|class.*Serializer',
                content
            ):
                continue

            endpoints = re.findall(r'(?:@router|@app)\.\w+\(["\']([^"\']+)', content)
            app_name = os.path.basename(os.path.dirname(fpath))
            api_type = f.replace('.py', '').replace('.ts', '')

            entry = {
                'id': f'api/{app_name}/{api_type}',
                'type': 'api',
                'name': f'{app_name}/{api_type}',
                'tags': 'api,' + ','.join(endpoints[:5]),
                'content': content[:3000]
            }
            with open(json_file, 'a') as jf:
                jf.write(json.dumps(entry) + '\n')
            count += 1


def sync_plan(plan_file, feature_dir, plan_name, json_file):
    """Index a single plan file."""
    content = open(plan_file).read()[:3000]
    entry = {
        'id': f'plan/{feature_dir}/{plan_name}',
        'type': 'plan',
        'name': f'{feature_dir} — {plan_name}',
        'tags': f'plan,{feature_dir},planner',
        'content': content
    }
    print(json.dumps(entry))


def sync_git(project_dir, json_file):
    """Index recent git commits and diff stats."""
    try:
        log = subprocess.run(
            ['git', 'log', '--oneline', '-20'],
            capture_output=True, text=True, cwd=project_dir
        )
        for line in log.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = line.split(' ', 1)
            sha = parts[0]
            msg = parts[1] if len(parts) > 1 else ''
            try:
                diff = subprocess.run(
                    ['git', 'diff', f'{sha}~1', sha, '--stat'],
                    capture_output=True, text=True, cwd=project_dir
                )
                stat = diff.stdout[:1000]
            except Exception:
                stat = ''
            if not stat:
                continue
            entry = {
                'id': f'git/{sha}',
                'type': 'commit',
                'name': f'{sha} — {msg[:80]}',
                'tags': 'git,commit,history',
                'content': f'{msg}\n\n{stat}'
            }
            with open(json_file, 'a') as f:
                f.write(json.dumps(entry) + '\n')
    except Exception:
        pass


def sync_config(cfg_file, cfg_name, json_file):
    """Index a single config file."""
    content = open(cfg_file).read()[:2000]
    entry = {
        'id': f'config/{cfg_name}',
        'type': 'config',
        'name': cfg_name,
        'tags': 'config,infrastructure',
        'content': content
    }
    print(json.dumps(entry))


def rag_query(batch_file, query):
    """Search RAG entries by keyword."""
    query_lower = query.lower()
    results = []
    with open(batch_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                searchable = ' '.join([
                    entry.get('name', ''),
                    entry.get('tags', ''),
                    entry.get('content', '')[:500],
                    entry.get('type', '')
                ]).lower()
                if query_lower in searchable:
                    results.append(entry)
            except json.JSONDecodeError:
                continue

    if not results:
        print('  No results found. Try different keywords.')
    else:
        for r in results[:8]:
            typ = r.get('type', '?')
            name = r.get('name', 'unknown')
            rid = r.get('id', '')
            tags = r.get('tags', '')
            colors = {'schema': '36', 'api': '33', 'plan': '35', 'config': '2', 'commit': '2'}
            c = colors.get(typ, '32')
            print(f'  \033[0;{c}m[{typ}]\033[0m \033[1m{name}\033[0m \033[2m({rid})\033[0m')
            if tags:
                print(f'    \033[2mlinks: {tags}\033[0m')
            content = r.get('content', '')
            snippet = ' '.join(content.split()[:20])
            if snippet:
                print(f'    \033[2m{snippet}...\033[0m')


def rag_setup(mcp_file, project_dir):
    """Add rag-memory-mcp to .mcp.json."""
    with open(mcp_file) as f:
        data = json.load(f)
    servers = data.get('mcpServers', {})
    if 'rag-memory' not in servers:
        servers['rag-memory'] = {
            'command': 'npx',
            'args': ['-y', 'rag-memory-mcp'],
            'env': {
                'MEMORY_DB_PATH': f'{project_dir}/.tasuki/config/rag-memory.db'
            }
        }
        data['mcpServers'] = servers
        with open(mcp_file, 'w') as f:
            json.dump(data, f, indent=2)
        print('  rag-memory-mcp added to .mcp.json')
    else:
        print('  rag-memory-mcp already configured')


def main():
    if len(sys.argv) < 2:
        print("Usage: vault_sync.py <action> [args...]", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]

    if action == 'memory':
        # memory <node_file> <node_type> <node_name> <tags> <json_file>
        sync_memory(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
    elif action == 'schema':
        sync_schema(sys.argv[2], sys.argv[3])
    elif action == 'api':
        sync_api(sys.argv[2], sys.argv[3])
    elif action == 'plan':
        # plan <plan_file> <feature_dir> <plan_name> <json_file>
        sync_plan(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == 'git':
        sync_git(sys.argv[2], sys.argv[3])
    elif action == 'config':
        # config <cfg_file> <cfg_name> <json_file>
        sync_config(sys.argv[2], sys.argv[3], sys.argv[4])
    elif action == 'query':
        rag_query(sys.argv[2], sys.argv[3])
    elif action == 'setup':
        rag_setup(sys.argv[2], sys.argv[3])
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
