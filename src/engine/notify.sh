#!/bin/bash
# Tasuki Engine — Notifications
# Sends webhook notifications when pipeline completes or fails.
# Supports: Slack, Discord, generic webhook.
#
# Config: .tasuki/config/notifications.json
# Usage:
#   tasuki notify setup                    Configure webhook
#   tasuki notify test                     Send test notification
#   tasuki notify send "Pipeline complete" Send notification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

NOTIFY_CONFIG=""

init_notify() {
  local project_dir="${1:-.}"
  NOTIFY_CONFIG="$project_dir/.tasuki/config/notifications.json"
}

# Setup notification webhook
notify_setup() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  init_notify "$project_dir"

  echo ""
  echo -e "${BOLD}Tasuki Notifications Setup${NC}"
  echo ""
  echo -e "  ${BOLD}Options:${NC}"
  echo -e "    ${CYAN}1${NC}) Slack (webhook URL)"
  echo -e "    ${CYAN}2${NC}) Discord (webhook URL)"
  echo -e "    ${CYAN}3${NC}) Generic webhook (any URL)"
  echo -e "    ${CYAN}4${NC}) Disable notifications"
  echo -en "  ${BOLD}Choice:${NC} "
  read -r choice

  local platform="" url=""

  case "$choice" in
    1)
      platform="slack"
      echo -en "  Slack webhook URL: "
      read -r url
      ;;
    2)
      platform="discord"
      echo -en "  Discord webhook URL: "
      read -r url
      ;;
    3)
      platform="webhook"
      echo -en "  Webhook URL: "
      read -r url
      ;;
    4)
      rm -f "$NOTIFY_CONFIG"
      log_success "Notifications disabled"
      return
      ;;
    *)
      log_error "Invalid choice"
      return
      ;;
  esac

  if [ -z "$url" ]; then
    log_error "No URL provided"
    return
  fi

  mkdir -p "$(dirname "$NOTIFY_CONFIG")"
  cat > "$NOTIFY_CONFIG" << EOF
{
  "platform": "$platform",
  "url": "$url",
  "enabled": true
}
EOF

  log_success "Notifications configured: $platform"
  echo ""
  echo -e "  Test it: ${CYAN}tasuki notify test${NC}"
  echo ""
}

# Send notification
notify_send() {
  local project_dir="${1:-.}"
  local message="${2:-Pipeline notification}"
  local status="${3:-info}"  # info, success, failure

  init_notify "$project_dir"

  if [ ! -f "$NOTIFY_CONFIG" ]; then
    return 0  # No notifications configured — silent
  fi

  local platform url enabled
  if command -v python3 &>/dev/null; then
    platform=$(python3 -c "import json; print(json.load(open('$NOTIFY_CONFIG')).get('platform',''))" 2>/dev/null)
    url=$(python3 -c "import json; print(json.load(open('$NOTIFY_CONFIG')).get('url',''))" 2>/dev/null)
    enabled=$(python3 -c "import json; print(json.load(open('$NOTIFY_CONFIG')).get('enabled',False))" 2>/dev/null)
  else
    return 0
  fi

  if [ "$enabled" != "True" ] || [ -z "$url" ]; then
    return 0
  fi

  local project_name
  project_name=$(basename "$(cd "$project_dir" && pwd)")
  local icon=""
  case "$status" in
    success) icon="✅" ;;
    failure) icon="❌" ;;
    *)       icon="ℹ️" ;;
  esac

  case "$platform" in
    slack)
      curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$icon *Tasuki — $project_name*\n$message\"}" \
        >/dev/null 2>&1
      ;;
    discord)
      curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$icon **Tasuki — $project_name**\n$message\"}" \
        >/dev/null 2>&1
      ;;
    webhook)
      curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"project\": \"$project_name\", \"message\": \"$message\", \"status\": \"$status\", \"timestamp\": \"$(date -Iseconds)\"}" \
        >/dev/null 2>&1
      ;;
  esac
}

# Test notification
notify_test() {
  local project_dir="${1:-.}"

  init_notify "$project_dir"

  if [ ! -f "$NOTIFY_CONFIG" ]; then
    log_error "No notifications configured. Run: tasuki notify setup"
    return
  fi

  notify_send "$project_dir" "Test notification from Tasuki 🚀" "info"
  log_success "Test notification sent!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    setup) shift; notify_setup "$@" ;;
    test)  shift; notify_test "$@" ;;
    send)  shift; notify_send "$@" ;;
    *)
      echo "Usage:"
      echo "  tasuki notify setup       Configure webhook (Slack/Discord/generic)"
      echo "  tasuki notify test        Send test notification"
      echo "  tasuki notify send \"msg\" Send custom notification"
      ;;
  esac
fi
