#!/usr/bin/env bash
set -euo pipefail
# Runs a clean-profile, uncheated AUTOMATED playthrough (script agent driving VirtualJoystick
# via InputEventScreenTouch/InputEventScreenDrag) with real Vulkan Forward Mobile rendering
# and post-limiter Master bus WAV capture during the Ancient Forest Guardian boss fight.
#
# Usage:
#   ./scripts/run_automated_playthrough.sh [summary_json_out] [boss_wav_out] [result_png_out]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SUMMARY_OUT="${1:-/tmp/automated_playthrough_summary.json}"
BOSS_WAV_OUT="${2:-/tmp/boss_combat_post_limiter.wav}"
RESULT_PNG_OUT="${3:-/tmp/automated_playthrough_result.png}"
CLEAN_PROFILE_DIR="$(mktemp -d /tmp/smush_clean_profile.XXXXXX)"
trap 'rm -rf "$CLEAN_PROFILE_DIR"' EXIT

# Optional: reuse compiled Vulkan PSO cache only (never copy save files) to speed startup.
WARM_CACHE_SRC="${WARM_SHADER_CACHE_DIR:-/tmp/smoke_rendered/godot/app_userdata/Slime Rush- Evolution}"
if [[ -d "$WARM_CACHE_SRC/shader_cache" ]]; then
  DEST_APP="$CLEAN_PROFILE_DIR/godot/app_userdata/Slime Rush- Evolution"
  mkdir -p "$DEST_APP"
  cp -r "$WARM_CACHE_SRC/shader_cache" "$DEST_APP/"
  [[ -d "$WARM_CACHE_SRC/vulkan" ]] && cp -r "$WARM_CACHE_SRC/vulkan" "$DEST_APP/"
fi

export PLAYTHROUGH_SUMMARY_PATH="$SUMMARY_OUT"
export PLAYTHROUGH_BOSS_WAV_PATH="$BOSS_WAV_OUT"
export PLAYTHROUGH_RESULT_PNG_PATH="$RESULT_PNG_OUT"
export XDG_DATA_HOME="$CLEAN_PROFILE_DIR"
export COMPOSITOR_W="${COMPOSITOR_W:-360}"
export COMPOSITOR_H="${COMPOSITOR_H:-640}"

./scripts/run_rendered_check.sh --resolution "${COMPOSITOR_W}x${COMPOSITOR_H}" --quit-after 32000 res://tools/AutomatedPlaythrough.tscn
