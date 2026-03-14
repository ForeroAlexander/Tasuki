#!/bin/bash
# Tasuki — Model Mapper
# Translates model references from Claude (opus/sonnet/haiku)
# to the equivalent model in each AI platform.
#
# Usage: source this file, then call translate_model <platform> <claude_model>

ADAPTERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Translate a Claude model name to the target platform's equivalent
translate_model() {
  local platform="$1"
  local claude_model="$2"

  # Determine tier from Claude model
  local tier="execution"
  case "$claude_model" in
    opus|claude-opus*) tier="thinking" ;;
    sonnet|claude-sonnet*) tier="execution" ;;
    haiku|claude-haiku*) tier="reflection" ;;
  esac

  # Map tier to platform model
  case "$platform" in
    claude)
      case "$tier" in
        thinking)   echo "opus" ;;
        execution)  echo "sonnet" ;;
        reflection) echo "haiku" ;;
      esac
      ;;
    codex)
      case "$tier" in
        thinking)   echo "o3" ;;
        execution)  echo "o4-mini" ;;
        reflection) echo "o4-mini" ;;
      esac
      ;;
    gemini)
      case "$tier" in
        thinking)   echo "gemini-2.5-pro" ;;
        execution)  echo "gemini-2.5-flash" ;;
        reflection) echo "gemini-2.5-flash" ;;
      esac
      ;;
    cursor)
      case "$tier" in
        thinking)   echo "claude-sonnet-4" ;;
        execution)  echo "claude-sonnet-4" ;;
        reflection) echo "cursor-small" ;;
      esac
      ;;
    copilot)
      case "$tier" in
        thinking)   echo "gpt-4.1" ;;
        execution)  echo "gpt-4.1-mini" ;;
        reflection) echo "gpt-4.1-mini" ;;
      esac
      ;;
    windsurf|continue|roocode)
      case "$tier" in
        thinking)   echo "claude-sonnet-4" ;;
        execution)  echo "claude-sonnet-4" ;;
        reflection) echo "claude-haiku-4" ;;
      esac
      ;;
    *)
      echo "$claude_model"  # fallback: return as-is
      ;;
  esac
}

# Translate all model references in a file for a target platform
translate_file_models() {
  local platform="$1"
  local file="$2"

  if [ ! -f "$file" ]; then return; fi

  # Get the model mappings
  local opus_model sonnet_model haiku_model
  opus_model=$(translate_model "$platform" "opus")
  sonnet_model=$(translate_model "$platform" "sonnet")
  haiku_model=$(translate_model "$platform" "haiku")

  # Replace in file
  sed -i \
    -e "s/model: opus/model: $opus_model/g" \
    -e "s/model: sonnet/model: $sonnet_model/g" \
    -e "s/model: haiku/model: $haiku_model/g" \
    -e "s/Opus/$opus_model/g" \
    -e "s/Sonnet/$sonnet_model/g" \
    "$file"
}
