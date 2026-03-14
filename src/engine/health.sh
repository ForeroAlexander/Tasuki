#!/bin/bash
# Tasuki Engine — Project Health Score
# Aggregate metric: security, testing, docs, code quality, config.
# Returns a score 0-100 with breakdown.
# Usage: bash health.sh [/path/to/project]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

health_score() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"

  echo ""
  echo -e "${BOLD}Project Health Score${NC}"
  echo -e "${DIM}════════════════════${NC}"
  echo ""

  local total=0
  local max=0

  # 1. Testing (25 points)
  max=$((max + 25))
  local test_score=0
  local test_files
  test_files=$(find "$project_dir" -name "test_*" -o -name "*_test.*" -o -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | grep -v node_modules | wc -l || echo 0)
  local source_files
  source_files=$(find "$project_dir" \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" \) -not -path "*/node_modules/*" -not -path "*/__pycache__/*" -not -path "*/.git/*" 2>/dev/null | wc -l || echo 0)

  if [ "$test_files" -gt 0 ] && [ "$source_files" -gt 0 ]; then
    local ratio=$((test_files * 100 / source_files))
    if [ "$ratio" -ge 80 ]; then test_score=25
    elif [ "$ratio" -ge 50 ]; then test_score=20
    elif [ "$ratio" -ge 30 ]; then test_score=15
    elif [ "$ratio" -ge 10 ]; then test_score=10
    else test_score=5; fi
  fi
  total=$((total + test_score))
  print_category "Testing" "$test_score" 25 "$test_files test files / $source_files source files"

  # 2. Security (20 points)
  max=$((max + 20))
  local sec_score=20
  # Deduct for common issues
  if grep -rqE 'password\s*=\s*["\x27][^\s"]{3,}' "$project_dir" --include="*.py" --include="*.ts" --include="*.js" 2>/dev/null | grep -v "test\|mock\|example" | head -1 | grep -q .; then
    sec_score=$((sec_score - 5))
  fi
  if grep -rqE 'eval\s*\(' "$project_dir" --include="*.py" --include="*.ts" --include="*.js" 2>/dev/null | grep -v "node_modules\|test" | head -1 | grep -q .; then
    sec_score=$((sec_score - 5))
  fi
  if [ -d "$project_dir/.git" ]; then
    if cd "$project_dir" && git ls-files '.env' 2>/dev/null | grep -q '.env'; then
      sec_score=$((sec_score - 10))
    fi
  fi
  [ "$sec_score" -lt 0 ] && sec_score=0
  total=$((total + sec_score))
  print_category "Security" "$sec_score" 20 ""

  # 3. Documentation (15 points)
  max=$((max + 15))
  local doc_score=0
  [ -f "$project_dir/README.md" ] && doc_score=$((doc_score + 5))
  [ -f "$project_dir/.env.example" ] && doc_score=$((doc_score + 3))
  [ -f "$project_dir/TASUKI.md" ] && doc_score=$((doc_score + 4))
  [ -d "$project_dir/tasuki-plans" ] && doc_score=$((doc_score + 3))
  [ "$doc_score" -gt 15 ] && doc_score=15
  total=$((total + doc_score))
  print_category "Documentation" "$doc_score" 15 ""

  # 4. Configuration (15 points)
  max=$((max + 15))
  local config_score=0
  [ -d "$project_dir/.tasuki" ] && config_score=$((config_score + 3))
  [ -f "$project_dir/.tasuki/settings.json" ] && config_score=$((config_score + 2))
  [ -f "$project_dir/.mcp.json" ] && config_score=$((config_score + 2))
  [ -f "$project_dir/.gitignore" ] && config_score=$((config_score + 2))
  [ -d "$project_dir/memory-vault" ] && config_score=$((config_score + 3))
  [ -f "$project_dir/.tasuki/config/capability-map.yaml" ] && config_score=$((config_score + 3))
  [ "$config_score" -gt 15 ] && config_score=15
  total=$((total + config_score))
  print_category "Configuration" "$config_score" 15 ""

  # 5. Code Quality (15 points)
  max=$((max + 15))
  local quality_score=15
  local todo_count
  todo_count=$(grep -rnE 'TODO|FIXME|HACK' "$project_dir" --include="*.py" --include="*.ts" --include="*.js" 2>/dev/null | grep -v "node_modules\|__pycache__" | wc -l || echo 0)
  [ "$todo_count" -gt 10 ] && quality_score=$((quality_score - 5))
  [ "$todo_count" -gt 30 ] && quality_score=$((quality_score - 5))

  local debug_count
  debug_count=$(grep -rnE 'console\.log|^\s*print\(' "$project_dir" --include="*.py" --include="*.ts" --include="*.js" 2>/dev/null | grep -v "node_modules\|__pycache__\|test" | wc -l || echo 0)
  [ "$debug_count" -gt 5 ] && quality_score=$((quality_score - 3))
  [ "$debug_count" -gt 15 ] && quality_score=$((quality_score - 4))

  [ "$quality_score" -lt 0 ] && quality_score=0
  total=$((total + quality_score))
  print_category "Code Quality" "$quality_score" 15 "$todo_count TODOs, $debug_count debug stmts"

  # 6. Infrastructure (10 points)
  max=$((max + 10))
  local infra_score=0
  [ -f "$project_dir/Dockerfile" ] && infra_score=$((infra_score + 3))
  [ -f "$project_dir/docker-compose.yml" ] || [ -f "$project_dir/compose.yml" ] && infra_score=$((infra_score + 3))
  [ -d "$project_dir/.github/workflows" ] && infra_score=$((infra_score + 4))
  [ "$infra_score" -gt 10 ] && infra_score=10
  total=$((total + infra_score))
  print_category "Infrastructure" "$infra_score" 10 ""

  # Overall
  echo ""
  echo -e "${DIM}─────────────────${NC}"

  # Score bar
  local bar=""
  local i
  for i in $(seq 1 20); do
    local threshold=$((i * 5))
    if [ "$total" -ge "$threshold" ]; then
      if [ "$total" -ge 80 ]; then bar+="${GREEN}█${NC}"
      elif [ "$total" -ge 50 ]; then bar+="${YELLOW}█${NC}"
      else bar+="${RED}█${NC}"; fi
    else
      bar+="${DIM}░${NC}"
    fi
  done

  echo -e "  ${BOLD}Overall:${NC} $bar ${BOLD}$total${NC}/100"
  echo ""

  if [ "$total" -ge 80 ]; then
    echo -e "  ${GREEN}${BOLD}EXCELLENT${NC} — Production-ready"
  elif [ "$total" -ge 60 ]; then
    echo -e "  ${GREEN}${BOLD}GOOD${NC} — Minor improvements recommended"
  elif [ "$total" -ge 40 ]; then
    echo -e "  ${YELLOW}${BOLD}FAIR${NC} — Several areas need attention"
  else
    echo -e "  ${RED}${BOLD}NEEDS WORK${NC} — Significant improvements needed"
  fi
  echo ""
}

print_category() {
  local name="$1" score="$2" max="$3" detail="$4"
  local pct=$((score * 100 / max))
  local color="$GREEN"
  [ "$pct" -lt 70 ] && color="$YELLOW"
  [ "$pct" -lt 40 ] && color="$RED"

  printf "  %-16s ${color}%2d${NC}/%d" "$name" "$score" "$max"
  [ -n "$detail" ] && printf "  ${DIM}%s${NC}" "$detail"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  health_score "$@"
fi
