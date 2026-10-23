#!/usr/bin/env bash
set -euo pipefail
# Reproducible visible / software-rendered launcher for SLIME RUSH: EVOLUTION (Godot 4.5).
# - On a desktop workstation (Wayland or X11 available): launches Godot directly with Forward Mobile.
# - In a headless Linux container without Xvfb/apt: uses SwiftShader Vulkan + minimal Wayland socket
#   from ${GFX_RUNTIME_DIR:-/tmp/gfx_runtime} so shaders, CanvasItem draw layers, UI layout, and
#   AudioServer Master bus output execute through real rasterization rather than --headless Dummy mode.
#
# Usage:
#   ./scripts/run_rendered_check.sh [godot args...]
# Example (interactive desktop launch):
#   ./scripts/run_rendered_check.sh
# Example (headless software-rendered 180-frame smoke run):
#   ./scripts/run_rendered_check.sh --quit-after 180

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot || echo /usr/local/bin/godot4)}"
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Error: Godot 4.5 binary not found (checked GODOT_BIN=$GODOT_BIN)." >&2
  exit 1
fi

python3 tools/sync_godot_cache.py

if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  exec "$GODOT_BIN" --path "$ROOT_DIR" --rendering-method mobile "$@"
fi

GFX_RUNTIME_DIR="${GFX_RUNTIME_DIR:-/tmp/gfx_runtime}"
if [[ -x "$GFX_RUNTIME_DIR/run_godot_rendered.sh" ]]; then
  exec "$GFX_RUNTIME_DIR/run_godot_rendered.sh" "$@"
fi

cat >&2 << 'EOF'
Error: No active WAYLAND_DISPLAY / DISPLAY found, and headless SwiftShader runtime
was not found at /tmp/gfx_runtime.

To bootstrap headless Wayland + SwiftShader Vulkan without root/apt (requires python3 + npm):
  mkdir -p /tmp/gfx_runtime
  # 1) Install libvulkan loader + wayland libs (e.g. via pypi wheels sapien / PyQt6-Qt6)
  # 2) Extract SwiftShader WSI Vulkan ICD (@onirenaud/swiftshader-vulkan@0.1.0)
  # 3) Point VK_ICD_FILENAMES to ss_wsi_icd.json and launch Godot with:
  #    godot4 --display-driver wayland --rendering-driver vulkan --rendering-method mobile
EOF
exit 1
