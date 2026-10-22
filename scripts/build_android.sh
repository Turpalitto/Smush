#!/usr/bin/env bash
# Reproducible Android Debug APK & Release AAB build script for SLIME RUSH: EVOLUTION.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-godot4}"

echo "[1/4] Synchronizing GDScript global class cache..."
python3 tools/sync_godot_cache.py

echo "[2/4] Running automated QA & integration test suite..."
"$GODOT_BIN" --headless --quit-after 600 --path "$ROOT_DIR" res://tests/TestRunner.tscn

if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  echo "ERROR: ANDROID_HOME / ANDROID_SDK_ROOT is not set. Install Android SDK (API 35, build-tools 35.0.0, NDK) to build APK/AAB." >&2
  exit 2
fi

mkdir -p builds/android

echo "[3/4] Exporting Android Debug APK..."
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-debug "Android Debug APK" builds/android/slime-rush-debug.apk

if [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" && -f "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH}" ]]; then
  echo "[4/4] Exporting signed Android Release AAB..."
  "$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "Android Release AAB" builds/android/slime-rush-release.aab
  echo "Release AAB ready: builds/android/slime-rush-release.aab"
else
  echo "[4/4] Skipping Release AAB export: GODOT_ANDROID_KEYSTORE_RELEASE_PATH not provided."
fi

echo "Done. Artifacts written to builds/android/"
