#!/usr/bin/env python3
"""
Tasuki — Vault Heuristic Seeder

Seeds universal heuristics (best practices) into a fresh memory vault.

Usage:
    python3 vault_seed.py <vault_dir> <seed_date>

Arguments:
    vault_dir   Path to memory-vault/
    seed_date   Date string (YYYY-MM-DD)
"""

import os
import sys


def seed_heuristics(vault, seed_date):
    hdir = os.path.join(vault, 'heuristics')
    os.makedirs(hdir, exist_ok=True)

    files = {
        "always-index-lookup-columns.md": f"""# Always Index Lookup Columns

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[db-architect]]
- [[backend-dev]]
- [[reviewer]]

## Rule
Every column used in WHERE, JOIN, or ORDER BY clauses must have a database index.

## Reason
Queries without indexes cause full table scans. On tables with >10K rows, this means seconds instead of milliseconds.

## Anti-Pattern
```
-- No index on email → full table scan
SELECT * FROM users WHERE email = 'user@example.com';
```

## Correct Pattern
```
CREATE INDEX idx_users_email ON users(email);
```

## Related
- [[postgres]]
""",

        "never-trust-client-input.md": f"""# Never Trust Client Input

Type: Heuristic
Severity: CRITICAL
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[backend-dev]]
- [[security]]
- [[reviewer]]

## Rule
Validate and sanitize ALL user input at the API boundary. Never pass raw input to queries, file operations, or shell commands.

## Enforcement
The Security agent runs OWASP checks. The security-check hook scans for common injection patterns.

## Related
- [[always-use-parameterized-queries]]
- [[security]]
""",

        "always-use-parameterized-queries.md": f"""# Always Use Parameterized Queries

Type: Heuristic
Severity: CRITICAL
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[db-architect]]
- [[backend-dev]]
- [[security]]

## Rule
Never use string interpolation or concatenation in SQL queries. Always use parameterized bindings.

## Anti-Pattern
```
# VULNERABLE — SQL injection
db.execute(f"SELECT * FROM users WHERE id = {{user_id}}")
```

## Correct Pattern
```
# SAFE — parameterized
db.execute("SELECT * FROM users WHERE id = :id", {{"id": user_id}})
```

## Related
- [[never-trust-client-input]]
- [[postgres]]
""",

        "tests-before-code.md": f"""# Tests Before Code (TDD)

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[qa]]
- [[backend-dev]]
- [[frontend-dev]]
- [[reviewer]]

## Rule
Write failing tests FIRST, then implement code to make them pass. Never the other way around.

## Reason
- Forces you to think about behavior before implementation
- Catches regressions automatically
- Serves as living documentation
- Prevents untestable code

## Enforcement
The TDD Guard hook (tdd-guard.sh) blocks edits to implementation files if no test file exists.

## Related
- [[qa]]
""",

        "handle-all-ui-states.md": f"""# Handle All UI States

Type: Heuristic
Severity: HIGH
Confidence: high
Last-Validated: {seed_date}
Applied-Count: 0

## Applies To
- [[frontend-dev]]
- [[reviewer]]

## Rule
Every UI component must handle ALL states: loading, error, empty, success, disabled.

## Anti-Pattern
```
// Only shows data — crashes or shows blank on error/loading
<UserList users={{data}} />
```

## Correct Pattern
```
if loading: <Skeleton />
else if error: <ErrorMessage />
else if data.length === 0: <EmptyState />
else: <UserList users={{data}} />
```

## Related
- [[ui-design]]
- [[ui-ux-pro-max]]
"""
    }

    for name, content in files.items():
        with open(os.path.join(hdir, name), 'w') as f:
            f.write(content.strip() + '\n')


def main():
    if len(sys.argv) < 3:
        print("Usage: vault_seed.py <vault_dir> <seed_date>", file=sys.stderr)
        sys.exit(1)

    seed_heuristics(sys.argv[1], sys.argv[2])


if __name__ == '__main__':
    main()
