#!/bin/bash
# Tasuki Detector: Database & ORM
# Usage: detect-database.sh /path/to/project

set -euo pipefail
PROJECT_DIR="${1:-.}"

db_engine=""
orm=""
migration_tool=""
multi_tenant=""
connection_pattern=""

# --- PostgreSQL ---
if grep -rql "postgresql\|psycopg\|asyncpg\|pg\b\|postgres" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.yaml" --include="*.yml" --include="*.toml" --include="*.json" --include="*.env*" --include="*.go" --include="*.rb" --include="*.java" 2>/dev/null | head -1 > /dev/null 2>&1; then
  db_engine="postgresql"
fi

# --- MySQL ---
if [ -z "$db_engine" ] && grep -rql "mysql\|mariadb" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.yaml" --include="*.yml" --include="*.env*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  db_engine="mysql"
fi

# --- MongoDB ---
if [ -z "$db_engine" ] && grep -rql "mongodb\|mongoose\|pymongo" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.json" 2>/dev/null | head -1 > /dev/null 2>&1; then
  db_engine="mongodb"
fi

# --- SQLite ---
if [ -z "$db_engine" ] && grep -rql "sqlite" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.toml" 2>/dev/null | head -1 > /dev/null 2>&1; then
  db_engine="sqlite"
fi

# --- ORM Detection ---

# SQLAlchemy
if grep -rql "sqlalchemy\|SQLAlchemy" "$PROJECT_DIR" --include="*.py" --include="*.toml" --include="*.txt" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="sqlalchemy"
fi

# Prisma
if [ -f "$PROJECT_DIR/prisma/schema.prisma" ] || [ -f "$PROJECT_DIR/schema.prisma" ]; then
  orm="prisma"
fi

# TypeORM
if grep -rql "typeorm" "$PROJECT_DIR" --include="*.ts" --include="*.json" -not -path "*/node_modules/*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="typeorm"
fi

# Drizzle
if grep -rql "drizzle-orm" "$PROJECT_DIR" --include="*.ts" --include="*.json" -not -path "*/node_modules/*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="drizzle"
fi

# Django ORM
if grep -rql "django.db\|models.Model" "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="django-orm"
fi

# ActiveRecord (Rails)
if grep -rql "ActiveRecord\|ApplicationRecord" "$PROJECT_DIR" --include="*.rb" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="activerecord"
fi

# GORM (Go)
if grep -rql "gorm.io" "$PROJECT_DIR" --include="*.go" 2>/dev/null | head -1 > /dev/null 2>&1; then
  orm="gorm"
fi

# SQLC (Go)
if [ -f "$PROJECT_DIR/sqlc.yaml" ] || [ -f "$PROJECT_DIR/sqlc.yml" ]; then
  orm="sqlc"
fi

# --- Migration Tool ---
if [ -d "$PROJECT_DIR/alembic" ] || find "$PROJECT_DIR" -maxdepth 4 -type d -name "alembic" 2>/dev/null | head -1 | grep -q .; then
  migration_tool="alembic"
elif [ -d "$PROJECT_DIR/prisma/migrations" ]; then
  migration_tool="prisma-migrate"
elif [ -d "$PROJECT_DIR/db/migrate" ]; then
  migration_tool="rails-migrations"
elif grep -rql "knex" "$PROJECT_DIR/package.json" 2>/dev/null; then
  migration_tool="knex"
elif [ -d "$PROJECT_DIR/migrations" ] && find "$PROJECT_DIR/migrations" -name "*.sql" 2>/dev/null | head -1 | grep -q .; then
  migration_tool="raw-sql"
elif grep -rql "golang-migrate\|migrate" "$PROJECT_DIR/go.mod" 2>/dev/null; then
  migration_tool="golang-migrate"
elif find "$PROJECT_DIR" -maxdepth 3 -name "*.py" -path "*/migrations/*" 2>/dev/null | head -1 | grep -q .; then
  migration_tool="django-migrations"
fi

# --- Multi-tenancy detection ---
if grep -rql "client_id\|tenant_id\|organization_id\|org_id" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.go" --include="*.rb" 2>/dev/null | head -1 > /dev/null 2>&1; then
  # Check if it's RLS
  if grep -rql "row.level\|RLS\|current_setting\|set_config" "$PROJECT_DIR" --include="*.py" --include="*.sql" 2>/dev/null | head -1 > /dev/null 2>&1; then
    multi_tenant="rls"
  else
    multi_tenant="filter-based"
  fi
fi

# --- Redis ---
has_redis="false"
if grep -rql "redis\|Redis\|REDIS_URL" "$PROJECT_DIR" --include="*.py" --include="*.ts" --include="*.js" --include="*.yaml" --include="*.yml" --include="*.env*" 2>/dev/null | head -1 > /dev/null 2>&1; then
  has_redis="true"
fi

# Count migrations
migration_count=0
if [ -n "$migration_tool" ]; then
  case "$migration_tool" in
    alembic)
      migration_count=$(find "$PROJECT_DIR" -path "*/alembic/versions/*.py" 2>/dev/null | wc -l)
      ;;
    prisma-migrate)
      migration_count=$(find "$PROJECT_DIR/prisma/migrations" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
      ;;
    rails-migrations)
      migration_count=$(find "$PROJECT_DIR/db/migrate" -name "*.rb" 2>/dev/null | wc -l)
      ;;
    django-migrations)
      migration_count=$(find "$PROJECT_DIR" -path "*/migrations/*.py" -not -name "__init__.py" 2>/dev/null | wc -l)
      ;;
  esac
fi

cat <<EOF
{
  "detected": $([ -n "$db_engine" ] && echo "true" || echo "false"),
  "engine": "${db_engine:-none}",
  "orm": "${orm:-none}",
  "migration_tool": "${migration_tool:-none}",
  "multi_tenant": "${multi_tenant:-none}",
  "has_redis": $has_redis,
  "counts": {
    "migrations": $migration_count
  }
}
EOF
