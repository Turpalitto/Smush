#!/usr/bin/env bash
set -euo pipefail
# Frame-time probe for the endless world (macOS, Metal, vsync off).
#
# Same isolation as run_macos_playthrough.sh: HOME is overridden so Godot reads a
# clean profile and the run does not inherit a save file.
#
# Usage: ./scripts/run_macos_perf.sh [perf_json_out]
#
# Note: this measures the machine it runs on (Apple M5 / Metal). It is a CPU and
# draw-call measurement, not a phone GPU measurement — see tools/perf_probe.gd.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-$HOME/godot45/Godot.app/Contents/MacOS/Godot}"
PERF_OUT="${1:-/tmp/perf_endless_world.json}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot binary not found or not executable: $GODOT_BIN" >&2
  exit 2
fi

CLEAN_HOME="$(mktemp -d /tmp/smush_perf_home.XXXXXX)"
trap 'rm -rf "$CLEAN_HOME"' EXIT

export PERF_OUT="$PERF_OUT"

# PERF_HEADLESS=1 drops rendering entirely, which removes the vsync cap and turns
# the wall clock into pure CPU frame time. The two runs answer different questions:
#   windowed -> what the GPU/CPU pair costs, draw calls, art-layer attribution
#   headless -> how much CPU headroom there is, with nothing to hide behind
#
# --fixed-fps 60 is not a cap, it is the opposite: it pins the simulated delta at
# 1/60 and removes the frame pacing, so one iteration of the main loop is one
# 60 Hz frame's worth of work and the wall clock measures that work. Without it
# the loop has a 6.9 ms floor on this machine (an EMPTY scene reads the same
# 6.9 ms), which hides everything the game actually costs.
if [[ "${PERF_HEADLESS:-0}" == "1" ]]; then
  HOME="$CLEAN_HOME" "$GODOT_BIN" --headless --fixed-fps 60 --path "$ROOT_DIR" res://tools/PerfProbe.tscn
else
  HOME="$CLEAN_HOME" "$GODOT_BIN" --path "$ROOT_DIR" res://tools/PerfProbe.tscn
fi
