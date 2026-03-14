---
name: test-endpoint
description: Test an API endpoint with curl — checks auth, response format, error handling, and edge cases.
argument-hint: "[METHOD] [endpoint-path]"
allowed-tools: Bash, Read
---

# Test Endpoint

Test the endpoint: $ARGUMENTS

## Steps

1. Read the router/controller code to understand expected behavior
2. Test success case (with auth token if required)
3. Test auth failure (no token) — expect 401
4. Test invalid data (if POST/PATCH) — expect 422 or 400
5. Test pagination (if GET list) — verify page size, total count
6. Report results:

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
