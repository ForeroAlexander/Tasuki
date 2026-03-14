---
name: db-migrate
description: Create a database migration using the project's migration tool.
argument-hint: "[migration description]"
allowed-tools: Bash, Read, Write, Edit, Glob
---

# Database Migration

Create a new migration for: $ARGUMENTS

## Steps

1. Detect migration tool from project config
2. Generate migration file using the project's tool:
   - **Alembic**: `alembic revision -m "$ARGUMENTS"`
   - **Prisma**: `npx prisma migrate dev --name "$ARGUMENTS"`
   - **Django**: `python manage.py makemigrations --name "$ARGUMENTS"`
   - **Rails**: `rails generate migration $ARGUMENTS`
   - **Knex**: `npx knex migrate:make $ARGUMENTS`
3. Edit the migration to follow project conventions (read from .tasuki/rules/migrations.md)
4. Verify by reading the file back
5. Show the migration content and ask to apply
