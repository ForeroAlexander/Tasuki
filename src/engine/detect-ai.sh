#!/bin/bash
# Tasuki Engine — AI Tool Detection
# Detects which AI coding assistants are installed on the system.
# Used by onboard to auto-select target and by doctor to verify setup.
#
# Usage: source this file, then call detect_ai_tools
#   or:  bash detect-ai.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

# Global: detected AI tools
declare -A AI_TOOLS=()

detect_ai_tools() {
  AI_TOOLS=()

  # Claude Code
  if command -v claude &>/dev/null; then
    AI_TOOLS[claude]="installed"
  elif [ -d "$HOME/.claude" ]; then
    AI_TOOLS[claude]="configured"
  fi

  # Cursor
  if command -v cursor &>/dev/null; then
    AI_TOOLS[cursor]="installed"
  elif [ -d "$HOME/.cursor" ] || pgrep -x "Cursor" &>/dev/null; then
    AI_TOOLS[cursor]="running"
  fi

  # OpenAI Codex CLI
  if command -v codex &>/dev/null; then
    AI_TOOLS[codex]="installed"
  fi

  # GitHub Copilot (VS Code extension — check via code CLI)
  if command -v code &>/dev/null && code --list-extensions 2>/dev/null | grep -qi "github.copilot"; then
    AI_TOOLS[copilot]="installed"
  fi

  # Continue (VS Code extension)
  if command -v code &>/dev/null && code --list-extensions 2>/dev/null | grep -qi "continue"; then
    AI_TOOLS[continue]="installed"
  elif [ -d "$HOME/.continue" ]; then
    AI_TOOLS[continue]="configured"
  fi

  # Windsurf
  if command -v windsurf &>/dev/null || pgrep -x "Windsurf" &>/dev/null; then
    AI_TOOLS[windsurf]="installed"
  fi

  # Roo Code (VS Code extension)
  if command -v code &>/dev/null && code --list-extensions 2>/dev/null | grep -qi "roocode\|roo-cline"; then
    AI_TOOLS[roocode]="installed"
  elif [ -d "$HOME/.roo" ]; then
    AI_TOOLS[roocode]="configured"
  fi

  # Gemini CLI
  if command -v gemini &>/dev/null; then
    AI_TOOLS[gemini]="installed"
  fi
}

# Print detected tools
print_ai_tools() {
  echo ""
  echo -e "${BOLD}AI Tools Detected${NC}"
  echo -e "${DIM}══════════════════${NC}"
  echo ""

  detect_ai_tools

  local found=0

  for tool in claude cursor codex copilot continue windsurf roocode gemini; do
    local status="${AI_TOOLS[$tool]:-}"
    if [ -n "$status" ]; then
      echo -e "  ${GREEN}●${NC} ${BOLD}$tool${NC} ($status)"
      found=$((found + 1))
    else
      echo -e "  ${DIM}○ $tool${NC}"
    fi
  done

  echo ""

  if [ "$found" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}No AI coding assistant detected.${NC}"
    echo ""
    echo -e "  Tasuki generates config for AI coding assistants."
    echo -e "  Install at least one to use the generated pipeline:"
    echo ""
    echo -e "    ${CYAN}Claude Code${NC}   → https://claude.ai/code"
    echo -e "    ${CYAN}Cursor${NC}        → https://cursor.com"
    echo -e "    ${CYAN}Codex CLI${NC}     → npm install -g @openai/codex"
    echo -e "    ${CYAN}Windsurf${NC}      → https://windsurf.com"
    echo -e "    ${CYAN}Continue${NC}      → VS Code extension"
    echo -e "    ${CYAN}Gemini CLI${NC}    → https://github.com/google-gemini/gemini-cli"
    echo ""
    echo -e "  After installing, run: ${CYAN}tasuki onboard .${NC}"
    echo ""
  else
    echo -e "  ${GREEN}$found tool(s) found.${NC} Tasuki will generate config for"
    if [ "$found" -eq 1 ]; then
      local tool
      for t in "${!AI_TOOLS[@]}"; do tool="$t"; done
      echo -e "  ${BOLD}$tool${NC} automatically."
    else
      echo -e "  all detected tools. Use ${CYAN}--target${NC} to pick one."
    fi
    echo ""
  fi
}

# Get the best default target based on what's installed
get_default_target() {
  detect_ai_tools

  # Priority order
  for tool in claude cursor codex copilot windsurf continue roocode gemini; do
    if [ -n "${AI_TOOLS[$tool]:-}" ]; then
      echo "$tool"
      return
    fi
  done

  # Nothing found — default to claude (most common)
  echo "claude"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  print_ai_tools
fi
