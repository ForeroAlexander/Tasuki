#!/bin/bash
# Tasuki Detector: Backend Stack
# Scans a project directory and outputs JSON with backend framework details.
# Usage: detect-backend.sh /path/to/project

set -euo pipefail
PROJECT_DIR="${1:-.}"

lang=""
framework=""
entry=""
package_manager=""
auth_pattern=""
api_style=""

# --- Python ---
# Find ALL directories with Python deps, pick the one with most .py files (main app, not microservice)
PY_FOUND=""
if command -v python3 &>/dev/null; then
  PY_FOUND=$(python3 -c "
import os, glob

project = '$PROJECT_DIR'
candidates = []

# Search known paths + find any requirements.txt recursively
search = [project, project+'/app', project+'/backend', project+'/app/backend', project+'/src', project+'/server',
          project+'/api', project+'/services/api', project+'/packages/server', project+'/apps/api',
          project+'/src/server', project+'/src/backend', project+'/apps/backend']

# Also find any requirements.txt up to depth 3
for root, dirs, files in os.walk(project):
    depth = root.replace(project, '').count(os.sep)
    if depth > 3: continue
    dirs[:] = [d for d in dirs if d not in ('node_modules', '.git', '__pycache__', '.venv', 'venv', '.tasuki')]
    if any(f in files for f in ('requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile')):
        search.append(root)

for d in search:
    if not os.path.isdir(d): continue
    has_deps = any(os.path.exists(os.path.join(d, f)) for f in ('requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile'))
    if has_deps:
        # Count .py files as a proxy for 'main app'
        py_count = sum(1 for _ in glob.iglob(os.path.join(d, '**/*.py'), recursive=True))
        candidates.append((py_count, d))

if candidates:
    # Pick the one with most .py files
    candidates.sort(key=lambda x: -x[0])
    print(candidates[0][1])
" 2>/dev/null)
fi

# Fallback: simple search if python3 not available
if [ -z "$PY_FOUND" ]; then
  PY_SEARCH_DIRS=("$PROJECT_DIR/app/backend" "$PROJECT_DIR/backend" "$PROJECT_DIR/app" "$PROJECT_DIR/src" "$PROJECT_DIR/server" "$PROJECT_DIR/api" "$PROJECT_DIR/services/api" "$PROJECT_DIR/packages/server" "$PROJECT_DIR/apps/api" "$PROJECT_DIR/src/server" "$PROJECT_DIR")
  for _pd in "${PY_SEARCH_DIRS[@]}"; do
    if [ -f "$_pd/requirements.txt" ] || [ -f "$_pd/pyproject.toml" ] || [ -f "$_pd/setup.py" ] || [ -f "$_pd/Pipfile" ]; then
      PY_FOUND="$_pd"
      break
    fi
  done
fi

if [ -n "$PY_FOUND" ]; then
  lang="python"
  [ -f "$PY_FOUND/Pipfile" ] && package_manager="pipenv"
  [ -f "$PY_FOUND/pyproject.toml" ] && package_manager="poetry"
  if [ -f "$PY_FOUND/requirements.txt" ]; then
    if command -v pip3 &>/dev/null; then
      package_manager="pip3"
    else
      package_manager="pip"
    fi
  fi

  # Detect framework
  all_deps=$(cat "$PY_FOUND"/requirements*.txt "$PY_FOUND"/pyproject.toml "$PY_FOUND"/Pipfile "$PY_FOUND"/setup.py 2>/dev/null || true)

  if echo "$all_deps" | grep -qi "fastapi"; then
    framework="fastapi"
    entry=$(find "$PY_FOUND" -maxdepth 4 -name "main.py" 2>/dev/null | head -1)
  elif echo "$all_deps" | grep -qi "django"; then
    framework="django"
    entry=$(find "$PY_FOUND" -maxdepth 4 -name "settings.py" 2>/dev/null | head -1)
  elif echo "$all_deps" | grep -qi "flask"; then
    framework="flask"
    entry=$(find "$PY_FOUND" -maxdepth 4 -name "app.py" -o -name "__init__.py" 2>/dev/null | head -1)
  fi

  # Detect auth pattern
  if grep -rql "Depends.*get_current_user\|jwt\|PyJWT" "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null; then
    auth_pattern="jwt"
  elif grep -rql "django.contrib.auth\|rest_framework.permissions" "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null; then
    auth_pattern="django-auth"
  fi

  # Detect API style
  if grep -rql "APIRouter\|@router\." "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null; then
    api_style="router-based"
  elif grep -rql "class.*ViewSet\|class.*APIView" "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null; then
    api_style="class-based-views"
  elif grep -rql "@app.route\|@app.get\|@app.post" "$PROJECT_DIR" --include="*.py" 2>/dev/null | head -1 > /dev/null; then
    api_style="decorator-based"
  fi
fi

# --- JavaScript / TypeScript (server-side) ---
# Search root AND common subdirectories
JS_FOUND=""
JS_SEARCH_DIRS=("$PROJECT_DIR" "$PROJECT_DIR/app" "$PROJECT_DIR/backend" "$PROJECT_DIR/app/backend" "$PROJECT_DIR/server" "$PROJECT_DIR/api")
for _jd in "${JS_SEARCH_DIRS[@]}"; do
  if [ -f "$_jd/package.json" ] && grep -qE '"express"|"@nestjs|"hono"|"fastify"' "$_jd/package.json" 2>/dev/null; then
    JS_FOUND="$_jd"
    break
  fi
done
[ -z "$JS_FOUND" ] && [ -f "$PROJECT_DIR/package.json" ] && JS_FOUND="$PROJECT_DIR"

if [ -z "$lang" ] && [ -n "$JS_FOUND" ]; then
  pkg_content=$(cat "$JS_FOUND/package.json" 2>/dev/null || true)

  if echo "$pkg_content" | grep -q '"express"'; then
    lang="javascript"
    framework="express"
    entry=$(find "$PROJECT_DIR" -maxdepth 3 \( -name "server.js" -o -name "app.js" -o -name "index.js" \) -not -path "*/node_modules/*" 2>/dev/null | head -1)
    package_manager="npm"
  elif echo "$pkg_content" | grep -q '"@nestjs/core"'; then
    lang="typescript"
    framework="nestjs"
    entry=$(find "$PROJECT_DIR" -maxdepth 4 -name "main.ts" -not -path "*/node_modules/*" 2>/dev/null | head -1)
    package_manager="npm"
  elif echo "$pkg_content" | grep -q '"hono"'; then
    lang="typescript"
    framework="hono"
    package_manager="npm"
  fi

  [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && package_manager="pnpm"
  [ -f "$PROJECT_DIR/yarn.lock" ] && package_manager="yarn"
  [ -f "$PROJECT_DIR/bun.lockb" ] && package_manager="bun"
fi

# --- Go ---
if [ -z "$lang" ] && [ -f "$PROJECT_DIR/go.mod" ]; then
  lang="go"
  package_manager="go-modules"
  go_deps=$(cat "$PROJECT_DIR/go.mod" 2>/dev/null || true)

  if echo "$go_deps" | grep -q "github.com/gin-gonic/gin"; then
    framework="gin"
  elif echo "$go_deps" | grep -q "github.com/gofiber/fiber"; then
    framework="fiber"
  elif echo "$go_deps" | grep -q "github.com/labstack/echo"; then
    framework="echo"
  elif echo "$go_deps" | grep -q "net/http"; then
    framework="stdlib"
  fi
  entry=$(find "$PROJECT_DIR" -maxdepth 3 -name "main.go" 2>/dev/null | head -1)
fi

# --- Ruby ---
if [ -z "$lang" ] && [ -f "$PROJECT_DIR/Gemfile" ]; then
  lang="ruby"
  package_manager="bundler"
  if grep -q "rails" "$PROJECT_DIR/Gemfile" 2>/dev/null; then
    framework="rails"
    entry="$PROJECT_DIR/config/application.rb"
  elif grep -q "sinatra" "$PROJECT_DIR/Gemfile" 2>/dev/null; then
    framework="sinatra"
  fi
fi

# --- Java ---
if [ -z "$lang" ]; then
  if [ -f "$PROJECT_DIR/pom.xml" ]; then
    lang="java"
    package_manager="maven"
    if grep -q "spring-boot" "$PROJECT_DIR/pom.xml" 2>/dev/null; then
      framework="spring-boot"
    fi
  elif [ -f "$PROJECT_DIR/build.gradle" ] || [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    lang="java"
    package_manager="gradle"
    if grep -q "spring-boot" "$PROJECT_DIR"/build.gradle* 2>/dev/null; then
      framework="spring-boot"
    fi
  fi
fi

# --- PHP ---
if [ -z "$lang" ] && [ -f "$PROJECT_DIR/composer.json" ]; then
  lang="php"
  package_manager="composer"
  php_deps=$(cat "$PROJECT_DIR/composer.json" 2>/dev/null || true)
  if echo "$php_deps" | grep -q "laravel/framework"; then
    framework="laravel"
    entry="$PROJECT_DIR/artisan"
  elif echo "$php_deps" | grep -q "symfony/framework-bundle"; then
    framework="symfony"
  fi

  if grep -rql "Route::" "$PROJECT_DIR/routes" --include="*.php" 2>/dev/null | head -1 > /dev/null; then
    api_style="route-based"
  fi
fi

# --- Rust ---
if [ -z "$lang" ] && [ -f "$PROJECT_DIR/Cargo.toml" ]; then
  lang="rust"
  package_manager="cargo"
  cargo_deps=$(cat "$PROJECT_DIR/Cargo.toml" 2>/dev/null || true)
  if echo "$cargo_deps" | grep -q "actix-web"; then
    framework="actix"
  elif echo "$cargo_deps" | grep -q "axum"; then
    framework="axum"
  elif echo "$cargo_deps" | grep -q "rocket"; then
    framework="rocket"
  fi
fi

# Count routers/controllers/handlers
router_count=0
model_count=0
service_count=0
if [ -n "$lang" ]; then
  case "$lang" in
    python)
      router_count=$(find "$PROJECT_DIR" -name "*.py" -path "*router*" -o -name "*.py" -path "*views*" 2>/dev/null | wc -l)
      model_count=$(find "$PROJECT_DIR" -name "*.py" -path "*model*" 2>/dev/null | wc -l)
      service_count=$(find "$PROJECT_DIR" -name "*.py" -path "*service*" 2>/dev/null | wc -l)
      ;;
    javascript|typescript)
      router_count=$(find "$PROJECT_DIR" -name "*.ts" -o -name "*.js" 2>/dev/null | xargs grep -l "Router\|controller\|handler" 2>/dev/null | wc -l)
      model_count=$(find "$PROJECT_DIR" \( -name "*.ts" -o -name "*.js" \) -path "*model*" -not -path "*/node_modules/*" 2>/dev/null | wc -l)
      ;;
    go)
      router_count=$(find "$PROJECT_DIR" -name "*.go" -path "*handler*" -o -name "*.go" -path "*controller*" 2>/dev/null | wc -l)
      model_count=$(find "$PROJECT_DIR" -name "*.go" -path "*model*" 2>/dev/null | wc -l)
      ;;
  esac
fi

# Detect backend path relative to project
be_path=""
if [ -n "$lang" ] && [ -n "$PY_FOUND" ] && [ "$PY_FOUND" != "$PROJECT_DIR" ]; then
  be_path=$(python3 -c "import os; print(os.path.relpath('$PY_FOUND', '$PROJECT_DIR'))" 2>/dev/null || echo "$PY_FOUND")
elif [ -n "$lang" ] && [ -n "$JS_FOUND" ] && [ "$JS_FOUND" != "$PROJECT_DIR" ]; then
  be_path=$(python3 -c "import os; print(os.path.relpath('$JS_FOUND', '$PROJECT_DIR'))" 2>/dev/null || echo "$JS_FOUND")
fi

# Detect Python version
py_version=""
if [ "$lang" = "python" ]; then
  py_version=$(python3 --version 2>/dev/null | grep -oP '[\d.]+' || true)
fi

# Detect framework version from deps
fw_version=""
if [ -n "$framework" ] && [ -n "$PY_FOUND" ]; then
  fw_version=$(grep -ohiP "${framework}[>=<~!]*\K[\d.]+" "$PY_FOUND"/requirements*.txt 2>/dev/null | head -1 || true)
fi

# Output JSON
cat <<EOF
{
  "detected": $([ -n "$lang" ] && echo "true" || echo "false"),
  "lang": "${lang:-none}",
  "lang_version": "${py_version:-}",
  "framework": "${framework:-unknown}",
  "framework_version": "${fw_version:-}",
  "path": "${be_path:-}",
  "entry": "${entry:-}",
  "package_manager": "${package_manager:-}",
  "auth_pattern": "${auth_pattern:-unknown}",
  "api_style": "${api_style:-unknown}",
  "counts": {
    "routers": $router_count,
    "models": $model_count,
    "services": $service_count
  }
}
EOF
