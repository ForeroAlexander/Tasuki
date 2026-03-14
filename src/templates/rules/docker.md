---
paths:
  - "**/Dockerfile*"
  - "**/docker-compose*.yml"
  - "**/compose*.yml"
---

# Docker & Infrastructure Rules

- Use slim/alpine base images to minimize attack surface
- Never run containers as root — add a USER directive
- Always use `--no-cache-dir` for pip, `npm ci` for node
- Always include `restart: unless-stopped`
- Always include `depends_on` for database and cache services
- Health checks: `test: ["CMD", "curl", "-f", "http://localhost:{{PORT}}/health"]`
- Use `.dockerignore` to exclude .git, node_modules, __pycache__, .env
- Pin base image versions (don't use `latest`)
- Use multi-stage builds to reduce final image size
