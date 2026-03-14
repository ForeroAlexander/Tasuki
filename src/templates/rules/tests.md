---
paths:
  - "{{TEST_PATH}}/**/*.py"
  - "{{TEST_PATH}}/**/*.ts"
  - "{{TEST_PATH}}/**/*.js"
  - "**/*.test.{ts,js,tsx,jsx}"
  - "**/*.spec.{ts,js,tsx,jsx}"
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/*_test.go"
  - "**/spec/**/*.rb"
---

# Testing Rules

## TDD Workflow (MANDATORY)
- **Tests FIRST**: Write failing tests before implementing
- **Build order**: Backend tests + code FIRST, then frontend (never in parallel)
- **No skipping**: Every new endpoint/service/component MUST have tests
- **Run tests before commit**: All tests must pass

## General
- Mock external services — never hit real APIs in tests
- Test authentication: 401 without token, 403 wrong role
- Test edge cases: empty data, invalid input, boundary values
- Test pagination when applicable: page size, total count, empty results
- Keep tests focused — one assertion concept per test
