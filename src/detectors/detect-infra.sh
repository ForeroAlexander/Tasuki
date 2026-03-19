#!/bin/bash
# Tasuki Detector: Infrastructure
# Usage: detect-infra.sh /path/to/project

set -euo pipefail
PROJECT_DIR="${1:-.}"

containerization=""
compose_file=""
ci_cd=""
reverse_proxy=""
deploy_target=""

# --- Docker ---
if [ -f "$PROJECT_DIR/Dockerfile" ] || find "$PROJECT_DIR" -maxdepth 3 -name "Dockerfile*" 2>/dev/null | head -1 | grep -q .; then
  containerization="docker"
fi

# --- Docker Compose ---
for f in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
  found=$(find "$PROJECT_DIR" -maxdepth 3 -name "$f" 2>/dev/null | head -1)
  if [ -n "$found" ]; then
    compose_file="$found"
    break
  fi
done

# --- CI/CD ---
if [ -d "$PROJECT_DIR/.github/workflows" ]; then
  ci_cd="github-actions"
elif [ -f "$PROJECT_DIR/.gitlab-ci.yml" ]; then
  ci_cd="gitlab-ci"
elif [ -f "$PROJECT_DIR/.circleci/config.yml" ]; then
  ci_cd="circleci"
elif [ -f "$PROJECT_DIR/Jenkinsfile" ]; then
  ci_cd="jenkins"
elif [ -f "$PROJECT_DIR/bitbucket-pipelines.yml" ]; then
  ci_cd="bitbucket"
elif [ -d "$PROJECT_DIR/.buildkite" ]; then
  ci_cd="buildkite"
fi

# --- Reverse Proxy ---
if find "$PROJECT_DIR" -maxdepth 3 -name "Caddyfile" 2>/dev/null | head -1 | grep -q .; then
  reverse_proxy="caddy"
elif find "$PROJECT_DIR" -maxdepth 3 -name "nginx.conf" -o -name "nginx" -type d 2>/dev/null | head -1 | grep -q .; then
  reverse_proxy="nginx"
elif find "$PROJECT_DIR" -maxdepth 3 -name "traefik*" 2>/dev/null | head -1 | grep -q .; then
  reverse_proxy="traefik"
fi

# --- Deploy Target ---
if [ -f "$PROJECT_DIR/vercel.json" ] || [ -f "$PROJECT_DIR/.vercel" ]; then
  deploy_target="vercel"
elif [ -f "$PROJECT_DIR/netlify.toml" ]; then
  deploy_target="netlify"
elif [ -f "$PROJECT_DIR/fly.toml" ]; then
  deploy_target="fly"
elif [ -f "$PROJECT_DIR/render.yaml" ]; then
  deploy_target="render"
elif [ -f "$PROJECT_DIR/railway.json" ] || [ -f "$PROJECT_DIR/railway.toml" ]; then
  deploy_target="railway"
elif find "$PROJECT_DIR" -maxdepth 2 -name "*.tf" 2>/dev/null | head -1 | grep -q .; then
  deploy_target="terraform"
elif [ -d "$PROJECT_DIR/k8s" ] || find "$PROJECT_DIR" -maxdepth 2 -name "*.yaml" -exec grep -l "kind: Deployment\|kind: Service" {} \; 2>/dev/null | head -1 | grep -q .; then
  deploy_target="kubernetes"
elif [ -n "$containerization" ]; then
  deploy_target="self-hosted"
fi

# --- Services count from compose ---
service_count=0
if [ -n "$compose_file" ]; then
  service_count=$(grep -c "^\s\+[a-zA-Z_-]\+:" "$compose_file" 2>/dev/null) || service_count=0
fi

# --- Dockerfile count ---
dockerfile_count=$(find "$PROJECT_DIR" -maxdepth 4 -name "Dockerfile*" 2>/dev/null | wc -l)

# --- Background Services / Dependencies ---
services_detected=""

# Search all requirements*.txt, package.json, go.mod, docker-compose for services
all_deps=$(find "$PROJECT_DIR" -maxdepth 4 \( -name "requirements*.txt" -o -name "pyproject.toml" -o -name "Pipfile" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -exec cat {} \; 2>/dev/null || true)
compose_content=""
[ -n "$compose_file" ] && compose_content=$(cat "$compose_file" 2>/dev/null || true)

# Redis
if echo "$all_deps" | grep -qi "redis\|aioredis" || echo "$compose_content" | grep -qi "redis"; then
  services_detected="${services_detected}redis,"
fi

# Celery
if echo "$all_deps" | grep -qi "celery"; then
  services_detected="${services_detected}celery,"
fi

# RabbitMQ
if echo "$all_deps" | grep -qi "rabbitmq\|pika\|amqp" || echo "$compose_content" | grep -qi "rabbitmq"; then
  services_detected="${services_detected}rabbitmq,"
fi

# Kafka
if echo "$all_deps" | grep -qi "kafka\|confluent" || echo "$compose_content" | grep -qi "kafka"; then
  services_detected="${services_detected}kafka,"
fi

# Elasticsearch
if echo "$all_deps" | grep -qi "elasticsearch" || echo "$compose_content" | grep -qi "elasticsearch"; then
  services_detected="${services_detected}elasticsearch,"
fi

# MinIO / S3
if echo "$all_deps" | grep -qi "minio\|boto3\|s3" || echo "$compose_content" | grep -qi "minio"; then
  services_detected="${services_detected}minio/s3,"
fi

# APScheduler
if echo "$all_deps" | grep -qi "apscheduler"; then
  services_detected="${services_detected}apscheduler,"
fi

# OpenAI / AI SDKs
if echo "$all_deps" | grep -qi "openai\|anthropic\|langchain"; then
  services_detected="${services_detected}ai-sdk,"
fi

# pgvector
if echo "$all_deps" | grep -qi "pgvector"; then
  services_detected="${services_detected}pgvector,"
fi

# WeasyPrint / PDF
if echo "$all_deps" | grep -qi "weasyprint\|reportlab\|fpdf\|puppeteer"; then
  services_detected="${services_detected}pdf-gen,"
fi

# Memcached
if echo "$all_deps" | grep -qi "memcached\|pymemcache\|pylibmc" || echo "$compose_content" | grep -qi "memcached"; then
  services_detected="${services_detected}memcached,"
fi

# MongoDB (as service, not primary DB)
if echo "$all_deps" | grep -qi "pymongo\|motor\|mongoengine\|mongoose" || echo "$compose_content" | grep -qi "mongo"; then
  services_detected="${services_detected}mongodb,"
fi

# GraphQL
if echo "$all_deps" | grep -qi "graphql\|graphene\|ariadne\|strawberry\|apollo\|@nestjs/graphql"; then
  services_detected="${services_detected}graphql,"
fi

# WebSocket
if echo "$all_deps" | grep -qi "websocket\|socket\.io\|channels\|starlette.*websocket\|ws\b\|socketio" || grep -rql "WebSocket\|websocket" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" -not -path "*/node_modules/*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  services_detected="${services_detected}websocket,"
fi

# SMTP / Email
if echo "$all_deps" | grep -qi "smtp\|sendgrid\|mailgun\|ses\|resend\|nodemailer\|django.core.mail\|fastapi-mail"; then
  services_detected="${services_detected}email,"
fi

# Webhooks (inbound/outbound)
if grep -rql "webhook\|Webhook\|WEBHOOK" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.yaml" --include="*.yml" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  services_detected="${services_detected}webhooks,"
fi

# Cron / Scheduled jobs (beyond APScheduler)
if echo "$all_deps" | grep -qi "cron\|schedule\|huey\|rq\|dramatiq" || echo "$compose_content" | grep -qi "cron"; then
  services_detected="${services_detected}cron-jobs,"
fi

# Sentry / Error tracking
if echo "$all_deps" | grep -qi "sentry-sdk\|sentry\|bugsnag\|rollbar"; then
  services_detected="${services_detected}error-tracking,"
fi

# Prometheus / Metrics
if echo "$all_deps" | grep -qi "prometheus\|statsd\|datadog" || echo "$compose_content" | grep -qi "prometheus\|grafana"; then
  services_detected="${services_detected}metrics,"
fi

# Remove trailing comma
services_detected="${services_detected%,}"

cat <<EOF
{
  "detected": $([ -n "$containerization" ] || [ -n "$ci_cd" ] && echo "true" || echo "false"),
  "containerization": "${containerization:-none}",
  "compose_file": "${compose_file:-}",
  "ci_cd": "${ci_cd:-none}",
  "reverse_proxy": "${reverse_proxy:-none}",
  "deploy_target": "${deploy_target:-none}",
  "services": "${services_detected:-none}",
  "counts": {
    "services": $service_count,
    "dockerfiles": $dockerfile_count
  }
}
EOF
