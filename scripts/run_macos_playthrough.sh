#!/usr/bin/env bash
set -euo pipefail
# macOS runner for the reproducible AUTOMATED playthrough (script agent, no cheats).
# Differences from the Linux/Wayland runner:
#   * uses the native macOS binary (Metal), no Vulkan/Wayland compositor needed;
#   * isolates the profile by overriding HOME, because Godot on macOS resolves
#     ~/Library/Application Support from HOME and ignores XDG_DATA_HOME.
#
# Usage:
#   ./scripts/run_macos_playthrough.sh [summary_json_out] [boss_wav_out] [result_png_out] [screenshot_dir]
#
# GODOT_BIN must point to a Godot 4.5 binary (defaults to the app bundle in ~/godot45).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-$HOME/godot45/Godot.app/Contents/MacOS/Godot}"
SUMMARY_OUT="${1:-/tmp/automated_playthrough_summary.json}"
BOSS_WAV_OUT="${2:-/tmp/boss_combat_post_limiter.wav}"
RESULT_PNG_OUT="${3:-/tmp/automated_playthrough_result.png}"
SCREENSHOT_DIR="${4:-}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot binary not found or not executable: $GODOT_BIN" >&2
  exit 2
fi

CLEAN_HOME="$(mktemp -d /tmp/smush_clean_home.XXXXXX)"
trap 'rm -rf "$CLEAN_HOME"' EXIT

export PLAYTHROUGH_SUMMARY_PATH="$SUMMARY_OUT"
export PLAYTHROUGH_BOSS_WAV_PATH="$BOSS_WAV_OUT"
export PLAYTHROUGH_RESULT_PNG_PATH="$RESULT_PNG_OUT"
if [[ -n "$SCREENSHOT_DIR" ]]; then
  mkdir -p "$SCREENSHOT_DIR"
  export PLAYTHROUGH_SCREENSHOT_DIR="$SCREENSHOT_DIR"
fi

# Clean profile: no save file exists on start.
HOME="$CLEAN_HOME" "$GODOT_BIN" --path "$ROOT_DIR" res://tools/AutomatedPlaythrough.tscn
