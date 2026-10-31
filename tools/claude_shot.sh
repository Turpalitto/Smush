#!/usr/bin/env bash
# Usage: tools/claude_shot.sh <out.png> [ENV=VALUE ...]
# One deterministic frame of the Claude visual lab (see ClaudeVisualLab.gd header).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Users/turpal/godot45/Godot.app/Contents/MacOS/Godot}"
OUT="$1"; shift
env CL_SHOT="$OUT" "$@" "$GODOT_BIN" --path "$ROOT" --fixed-fps 60 res://scenes/labs/ClaudeVisualLab.tscn 2>&1 | grep -E "CL_SHOT|ERROR|SCRIPT|WARNING|Parse" | sort | uniq -c | head -20 || true
