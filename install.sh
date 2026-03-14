#!/bin/bash
# Tasuki — Installation Script
# Run: curl -fsSL https://raw.githubusercontent.com/USER/tasuki/main/install.sh | bash
#   or: git clone ... && cd tasuki && bash install.sh
#
# What it does:
# 1. Makes all scripts executable
# 2. Creates symlink in /usr/local/bin (or adds to PATH)
# 3. Verifies dependencies

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Tasuki — Installation           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# Determine tasuki root
TASUKI_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$TASUKI_ROOT/bin/tasuki" ]; then
  echo -e "${RED}Error: bin/tasuki not found.${NC}"
  echo "Run this script from the tasuki directory:"
  echo "  cd tasuki && bash install.sh"
  exit 1
fi

# Step 1: Make everything executable
echo -e "${CYAN}[1/3]${NC} Making scripts executable..."
chmod +x "$TASUKI_ROOT/bin/tasuki"
find "$TASUKI_ROOT/src/engine" -name "*.sh" -exec chmod +x {} \;
find "$TASUKI_ROOT/src/detectors" -name "*.sh" -exec chmod +x {} \;
find "$TASUKI_ROOT/src/templates/hooks" -name "*.sh" -exec chmod +x {} \;
echo -e "  ${GREEN}Done${NC}"

# Step 2: Add to PATH
echo -e "${CYAN}[2/3]${NC} Adding to PATH..."

INSTALL_METHOD=""

# Try symlink first (needs sudo)
if [ -w "/usr/local/bin" ]; then
  ln -sf "$TASUKI_ROOT/bin/tasuki" /usr/local/bin/tasuki
  INSTALL_METHOD="symlink"
  echo -e "  ${GREEN}Symlinked to /usr/local/bin/tasuki${NC}"
elif command -v sudo &>/dev/null; then
  echo -e "  ${DIM}Creating symlink in /usr/local/bin (may ask for password)${NC}"
  if sudo ln -sf "$TASUKI_ROOT/bin/tasuki" /usr/local/bin/tasuki 2>/dev/null; then
    INSTALL_METHOD="symlink"
    echo -e "  ${GREEN}Symlinked to /usr/local/bin/tasuki${NC}"
  fi
fi

# Fallback: add to shell profile
if [ -z "$INSTALL_METHOD" ]; then
  EXPORT_LINE="export PATH=\"$TASUKI_ROOT/bin:\$PATH\""

  # Detect shell
  SHELL_NAME=$(basename "$SHELL" 2>/dev/null || echo "bash")
  case "$SHELL_NAME" in
    zsh)  PROFILE="$HOME/.zshrc" ;;
    fish) PROFILE="$HOME/.config/fish/config.fish" ;;
    *)    PROFILE="$HOME/.bashrc" ;;
  esac

  # Check if already added
  if grep -qF "tasuki/bin" "$PROFILE" 2>/dev/null; then
    echo -e "  ${DIM}Already in $PROFILE${NC}"
  else
    echo "$EXPORT_LINE" >> "$PROFILE"
    echo -e "  ${GREEN}Added to $PROFILE${NC}"
  fi
  INSTALL_METHOD="profile"

  # Also export for current session
  export PATH="$TASUKI_ROOT/bin:$PATH"
fi

# Step 3: Verify
echo -e "${CYAN}[3/3]${NC} Verifying installation..."

if command -v tasuki &>/dev/null; then
  VERSION=$(tasuki version 2>/dev/null)
  echo -e "  ${GREEN}$VERSION installed successfully!${NC}"
else
  # Try direct
  if "$TASUKI_ROOT/bin/tasuki" version &>/dev/null; then
    VERSION=$("$TASUKI_ROOT/bin/tasuki" version)
    echo -e "  ${GREEN}$VERSION installed!${NC}"
    if [ "$INSTALL_METHOD" = "profile" ]; then
      echo -e "  ${YELLOW}Restart your terminal or run:${NC} source $PROFILE"
    fi
  else
    echo -e "  ${RED}Installation failed${NC}"
    exit 1
  fi
fi

# Check optional dependencies
echo ""
echo -e "${BOLD}Dependencies:${NC}"
for cmd in git curl awk python3 node npx jq; do
  if command -v "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $cmd"
  else
    echo -e "  ${YELLOW}○${NC} $cmd ${DIM}(optional)${NC}"
  fi
done

echo ""
echo -e "${BOLD}Quick Start:${NC}"
echo ""
echo -e "  ${CYAN}New project:${NC}"
echo -e "    tasuki init nextjs my-app"
echo -e "    tasuki init fastapi my-api"
echo ""
echo -e "  ${CYAN}Existing project:${NC}"
echo -e "    cd your-project"
echo -e "    tasuki"
echo ""
echo -e "  ${CYAN}Full command list:${NC}"
echo -e "    tasuki help"
echo ""
echo -e "${GREEN}${BOLD}Ready to go!${NC}"
echo ""
