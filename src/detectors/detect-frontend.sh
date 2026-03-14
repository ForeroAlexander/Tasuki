#!/bin/bash
# Tasuki Detector: Frontend Stack
# Usage: detect-frontend.sh /path/to/project

set -euo pipefail
PROJECT_DIR="${1:-.}"

framework=""
styling=""
state=""
components_lib=""
lang=""
package_manager=""
ssr=""

# Search root AND common subdirectories for frontend
FE_DIR=""
FE_SEARCH_DIRS=("$PROJECT_DIR" "$PROJECT_DIR/frontend" "$PROJECT_DIR/app/frontend" "$PROJECT_DIR/client" "$PROJECT_DIR/web" "$PROJECT_DIR/app/web" "$PROJECT_DIR/app/client" "$PROJECT_DIR/packages/web" "$PROJECT_DIR/apps/web" "$PROJECT_DIR/src/client" "$PROJECT_DIR/src/frontend")
for _fd in "${FE_SEARCH_DIRS[@]}"; do
  if [ -f "$_fd/svelte.config.js" ] || [ -f "$_fd/svelte.config.ts" ] || [ -f "$_fd/next.config.js" ] || [ -f "$_fd/next.config.mjs" ] || [ -f "$_fd/nuxt.config.ts" ] || [ -f "$_fd/vite.config.ts" ] || [ -f "$_fd/angular.json" ]; then
    FE_DIR="$_fd"
    break
  fi
  if [ -f "$_fd/package.json" ] && grep -qE '"svelte"|"react"|"vue"|"@angular/|"next"|"nuxt"' "$_fd/package.json" 2>/dev/null; then
    FE_DIR="$_fd"
    break
  fi
done

# Fallback: find recursively (max depth 3)
if [ -z "$FE_DIR" ]; then
  _found=$(find "$PROJECT_DIR" -maxdepth 3 \( -name "svelte.config.js" -o -name "svelte.config.ts" -o -name "next.config.js" -o -name "next.config.mjs" -o -name "nuxt.config.ts" -o -name "angular.json" \) -not -path "*/node_modules/*" 2>/dev/null | head -1)
  if [ -n "$_found" ]; then
    FE_DIR="$(dirname "$_found")"
  fi
fi

# Default to PROJECT_DIR if nothing found (detection will fail gracefully)
[ -z "$FE_DIR" ] && FE_DIR="$PROJECT_DIR"

# --- SvelteKit ---
if [ -f "$FE_DIR/svelte.config.js" ] || [ -f "$FE_DIR/svelte.config.ts" ]; then
  framework="sveltekit"
  lang="typescript"
  ssr="true"

  # Detect Svelte version
  if grep -rq '\$state\|\$derived\|\$effect' "$FE_DIR/src" --include="*.svelte" 2>/dev/null; then
    framework="sveltekit-5"
  fi
fi

# --- Next.js ---
if [ -z "$framework" ] && { [ -f "$FE_DIR/next.config.js" ] || [ -f "$FE_DIR/next.config.mjs" ] || [ -f "$FE_DIR/next.config.ts" ]; }; then
  framework="nextjs"
  lang="typescript"
  ssr="true"

  # App Router vs Pages Router
  if [ -d "$FE_DIR/app" ] || [ -d "$FE_DIR/src/app" ]; then
    framework="nextjs-app"
  else
    framework="nextjs-pages"
  fi
fi

# --- Nuxt ---
if [ -z "$framework" ] && { [ -f "$FE_DIR/nuxt.config.js" ] || [ -f "$FE_DIR/nuxt.config.ts" ]; }; then
  framework="nuxt"
  lang="typescript"
  ssr="true"
fi

# --- Angular ---
if [ -z "$framework" ] && [ -f "$FE_DIR/angular.json" ]; then
  framework="angular"
  lang="typescript"
  ssr="false"
fi

# --- React (Vite / CRA) ---
if [ -z "$framework" ] && [ -f "$FE_DIR/package.json" ]; then
  pkg=$(cat "$FE_DIR/package.json" 2>/dev/null || true)

  if echo "$pkg" | grep -q '"react"' && ! echo "$pkg" | grep -q '"next"'; then
    framework="react"
    lang="typescript"
    ssr="false"

    if [ -f "$FE_DIR/vite.config.ts" ] || [ -f "$FE_DIR/vite.config.js" ]; then
      framework="react-vite"
    fi
  fi

  # Vue (standalone, not Nuxt)
  if [ -z "$framework" ] && echo "$pkg" | grep -q '"vue"' && ! echo "$pkg" | grep -q '"nuxt"'; then
    framework="vue"
    lang="typescript"
    ssr="false"
    if [ -f "$FE_DIR/vite.config.ts" ] || [ -f "$FE_DIR/vite.config.js" ]; then
      framework="vue-vite"
    fi
  fi
fi

# --- Detect styling ---
if [ -n "$framework" ]; then
  all_configs=$(cat "$FE_DIR"/package.json "$FE_DIR"/tailwind.config.* "$FE_DIR"/postcss.config.* 2>/dev/null || true)

  if [ -f "$FE_DIR/tailwind.config.js" ] || [ -f "$FE_DIR/tailwind.config.ts" ] || echo "$all_configs" | grep -q "tailwindcss"; then
    styling="tailwind"
  elif echo "$all_configs" | grep -q "styled-components"; then
    styling="styled-components"
  elif echo "$all_configs" | grep -q "emotion"; then
    styling="emotion"
  elif find "$FE_DIR/src" -name "*.module.css" -o -name "*.module.scss" 2>/dev/null | head -1 | grep -q .; then
    styling="css-modules"
  elif find "$FE_DIR/src" -name "*.scss" -o -name "*.sass" 2>/dev/null | head -1 | grep -q .; then
    styling="sass"
  else
    styling="css"
  fi

  # State management
  if grep -rq "zustand" "$FE_DIR/package.json" 2>/dev/null; then
    state="zustand"
  elif grep -rq "redux\|@reduxjs" "$FE_DIR/package.json" 2>/dev/null; then
    state="redux"
  elif grep -rq "pinia" "$FE_DIR/package.json" 2>/dev/null; then
    state="pinia"
  elif grep -rq '\$state\|writable\|readable' "$FE_DIR/src" -r --include="*.ts" --include="*.svelte" 2>/dev/null; then
    state="svelte-stores"
  elif grep -rq "jotai" "$FE_DIR/package.json" 2>/dev/null; then
    state="jotai"
  fi

  # Component libraries
  pkg_content=$(cat "$FE_DIR/package.json" 2>/dev/null || true)
  if echo "$pkg_content" | grep -q "shadcn\|@radix-ui"; then
    components_lib="shadcn"
  elif echo "$pkg_content" | grep -q "bits-ui"; then
    components_lib="bits-ui"
  elif echo "$pkg_content" | grep -q "@mui/material"; then
    components_lib="material-ui"
  elif echo "$pkg_content" | grep -q "antd\|ant-design"; then
    components_lib="antd"
  elif echo "$pkg_content" | grep -q "chakra"; then
    components_lib="chakra"
  fi

  # Package manager
  [ -f "$FE_DIR/pnpm-lock.yaml" ] && package_manager="pnpm"
  [ -f "$FE_DIR/yarn.lock" ] && package_manager="yarn"
  [ -f "$FE_DIR/bun.lockb" ] && package_manager="bun"
  [ -f "$FE_DIR/package-lock.json" ] && package_manager="npm"
fi

# Count pages/components
page_count=0
component_count=0
if [ -n "$framework" ]; then
  page_count=$(find "$FE_DIR" -not -path "*/node_modules/*" -not -path "*/.git/*" \( -path "*/routes/*" -o -path "*/pages/*" \) -name "*.svelte" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" 2>/dev/null | grep -cE "\.(svelte|tsx|jsx|vue)$" || echo 0)
  component_count=$(find "$FE_DIR" -not -path "*/node_modules/*" -not -path "*/.git/*" -path "*/components/*" \( -name "*.svelte" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" \) 2>/dev/null | wc -l | tr -d ' ')
  # Also count lib/ files for Svelte
  if [ "$page_count" -eq 0 ] 2>/dev/null; then
    page_count=$(find "$FE_DIR/src" -name "+page.svelte" -o -name "+page.ts" -o -name "page.tsx" 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

# Detect frontend path relative to project
fe_path=""
if [ -n "$framework" ] && [ "$FE_DIR" != "$PROJECT_DIR" ]; then
  fe_path=$(python3 -c "import os; print(os.path.relpath('$FE_DIR', '$PROJECT_DIR'))" 2>/dev/null || echo "$FE_DIR")
fi

# Detect version from package.json
fe_version=""
if [ -n "$framework" ] && [ -f "$FE_DIR/package.json" ]; then
  case "$framework" in
    sveltekit*) fe_version=$(grep -oP '"@sveltejs/kit"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
    nextjs*) fe_version=$(grep -oP '"next"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
    nuxt*) fe_version=$(grep -oP '"nuxt"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
    react*) fe_version=$(grep -oP '"react"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
    vue*) fe_version=$(grep -oP '"vue"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
    angular*) fe_version=$(grep -oP '"@angular/core"\s*:\s*"\K[^"]+' "$FE_DIR/package.json" 2>/dev/null || true) ;;
  esac
fi

cat <<EOF
{
  "detected": $([ -n "$framework" ] && echo "true" || echo "false"),
  "framework": "${framework:-none}",
  "lang": "${lang:-}",
  "path": "${fe_path:-}",
  "version": "${fe_version:-}",
  "styling": "${styling:-}",
  "state": "${state:-}",
  "components_lib": "${components_lib:-}",
  "package_manager": "${package_manager:-}",
  "ssr": "${ssr:-false}",
  "counts": {
    "pages": $page_count,
    "components": $component_count
  }
}
EOF
