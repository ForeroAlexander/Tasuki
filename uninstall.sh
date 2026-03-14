#!/bin/bash
# Tasuki — Uninstall
set -euo pipefail

echo "Removing tasuki..."

# Remove symlink
if [ -L "/usr/local/bin/tasuki" ]; then
  sudo rm -f /usr/local/bin/tasuki 2>/dev/null || rm -f /usr/local/bin/tasuki
  echo "  Removed /usr/local/bin/tasuki"
fi

# Remove from shell profile
for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
  if [ -f "$profile" ] && grep -q "tasuki/bin" "$profile" 2>/dev/null; then
    sed -i '/tasuki\/bin/d' "$profile"
    echo "  Removed from $profile"
  fi
done

echo ""
echo "Tasuki uninstalled. The source directory was NOT deleted."
echo "To fully remove: rm -rf $(cd "$(dirname "$0")" && pwd)"
