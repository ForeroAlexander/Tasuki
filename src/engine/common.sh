#!/bin/bash
# Tasuki Engine — Common utilities
# Sourced by all engine scripts.

# Guard against multiple sourcing
[[ -n "${_TASUKI_COMMON_LOADED:-}" ]] && return 0
_TASUKI_COMMON_LOADED=1

set -euo pipefail

# --- Paths ---
TASUKI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASUKI_SRC="$TASUKI_ROOT/src"
TASUKI_DETECTORS="$TASUKI_SRC/detectors"
TASUKI_PROFILES="$TASUKI_SRC/profiles"
TASUKI_TEMPLATES="$TASUKI_SRC/templates"
TASUKI_REGISTRY="$TASUKI_SRC/registry.yaml"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Logging ---
log_info()    { echo -e "${BLUE}[tasuki]${NC} $*"; }
log_success() { echo -e "${GREEN}[tasuki]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[tasuki]${NC} $*"; }
log_error()   { echo -e "${RED}[tasuki]${NC} $*" >&2; }
log_step()    { echo -e "${CYAN}[tasuki]${NC} ${BOLD}$*${NC}"; }
log_dim()     { echo -e "${DIM}         $*${NC}"; }

# --- Dependency check ---
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    log_error "Install it and try again."
    exit 1
  fi
}

# --- JSON helpers (uses jq if available, fallback to grep/sed) ---
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

# Extract a value from a JSON object (supports nested via dot notation and numbers)
# json_get '{"key":"val"}' key → val
# json_get '{"counts":{"routers":70}}' routers → 70 (searches anywhere in JSON)
json_get() {
  local json="$1" key="$2"
  if $HAS_JQ; then
    # Try direct key first, then search nested
    local result
    result=$(echo "$json" | jq -r ".$key // empty" 2>/dev/null)
    if [ -z "$result" ]; then
      # Search recursively for the key
      result=$(echo "$json" | jq -r ".. | .$key? // empty" 2>/dev/null | head -1)
    fi
    echo "$result"
  else
    # Try string value first: "key": "value"
    local val
    val=$(echo "$json" | grep -oP "\"$key\"\s*:\s*\"\K[^\"]*" 2>/dev/null | head -1 || true)
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
    # Try number value: "key": 70
    val=$(echo "$json" | grep -oP "\"$key\"\s*:\s*\K[0-9.]+" 2>/dev/null | head -1 || true)
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
}

# Extract a boolean value from JSON: json_bool '{"detected":true}' detected
json_bool() {
  local json="$1" key="$2"
  if $HAS_JQ; then
    echo "$json" | jq -r ".$key // false"
  else
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[a-z]*" 2>/dev/null | head -1 | sed 's/.*:\s*//' || echo "false"
  fi
}

# Extract a numeric value from JSON: json_num '{"count":5}' count
json_num() {
  local json="$1" key="$2"
  if $HAS_JQ; then
    echo "$json" | jq -r ".$key // 0"
  else
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" 2>/dev/null | head -1 | sed 's/.*:\s*//' || echo "0"
  fi
}

# --- YAML helpers (lightweight, no external deps) ---
# Extract a simple value from a YAML file: yaml_get file.yaml "stack.backend.lang"
yaml_get() {
  local file="$1" keypath="$2"
  if $HAS_JQ && command -v yq &>/dev/null; then
    yq -r ".$keypath // empty" "$file" 2>/dev/null
  else
    # Simple fallback: only works for flat key: value lines
    local key="${keypath##*.}"
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
  fi
}

# Extract a YAML list as newline-separated values
yaml_list() {
  local file="$1" keypath="$2"
  if $HAS_JQ && command -v yq &>/dev/null; then
    yq -r ".$keypath[]? // empty" "$file" 2>/dev/null
  else
    local key="${keypath##*.}"
    local in_section=false
    while IFS= read -r line; do
      if echo "$line" | grep -qE "^\s*${key}:"; then
        in_section=true
        continue
      fi
      if $in_section; then
        if echo "$line" | grep -qE '^\s*-\s'; then
          echo "$line" | sed 's/^\s*-\s*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
        elif echo "$line" | grep -qE '^\s*[a-zA-Z_]'; then
          break
        fi
      fi
    done < "$file"
  fi
}

# --- File helpers ---
# Replace all {{PLACEHOLDER}} in a file with values from an associative array
# Usage: render_placeholders input_file output_file
# Reads from global TASUKI_VARS associative array
render_placeholders() {
  local input="$1" output="$2"

  # Write vars to temp files for awk to read (handles multi-line values)
  local vars_dir
  vars_dir=$(mktemp -d)

  for key in "${!TASUKI_VARS[@]}"; do
    printf '%s' "${TASUKI_VARS[$key]}" > "$vars_dir/$key"
  done

  # Use awk to replace {{PLACEHOLDER}} patterns
  awk -v vars_dir="$vars_dir" '
  {
    line = $0
    while (match(line, /\{\{[A-Z_]+\}\}/)) {
      placeholder = substr(line, RSTART, RLENGTH)
      key = substr(placeholder, 3, length(placeholder) - 4)
      varfile = vars_dir "/" key
      value = ""
      # Read entire file content
      first = 1
      while ((getline fileline < varfile) > 0) {
        if (first) {
          value = fileline
          first = 0
        } else {
          value = value "\n" fileline
        }
      }
      close(varfile)
      # Replace the placeholder in the line
      before = substr(line, 1, RSTART - 1)
      after = substr(line, RSTART + RLENGTH)
      line = before value after
    }
    print line
  }' "$input" > "$output.tmp"

  mkdir -p "$(dirname "$output")"
  mv "$output.tmp" "$output"
  rm -rf "$vars_dir"
}

# Check if a placeholder still exists in content
has_unresolved_placeholders() {
  local file="$1"
  grep -qE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null
}

# List unresolved placeholders in a file
list_unresolved_placeholders() {
  local file="$1"
  grep -oE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null | sort -u
}
