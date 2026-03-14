---
name: deploy-check
description: Check health and status of all project services — containers, API, frontend, database, migrations.
allowed-tools: Bash, Read, Grep
---

# Deploy Check — Health Status

Run a complete health check of all services.

## Steps

1. **Containers**: `docker ps` — check all services are running
2. **Backend API**: `curl -s {{HEALTH_ENDPOINT}}` — verify API responds
3. **Frontend**: `curl -s -o /dev/null -w "%{http_code}" {{FRONTEND_URL}}` — verify frontend loads
4. **Database**: Verify connection and migration status
5. **Logs**: Check last 20 lines for errors across services

## Report

| Service | Status | Details |
|---------|--------|---------|

Flag issues as CRITICAL, WARNING, or OK.
