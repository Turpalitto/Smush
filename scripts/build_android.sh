#!/usr/bin/env bash
# Build a real Android package after QA. No SDK license acceptance or release keys in Git.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
GODOT_BIN="${GODOT_BIN:-godot4}"
MODE="${1:-debug}"
case "$MODE" in
  debug) PRESET="Android Debug APK"; PREFLIGHT_ARGS=() ;;
  offline) PRESET="Android Offline Debug APK"; PREFLIGHT_ARGS=(--offline) ;;
  release) PRESET="Android Release AAB"; PREFLIGHT_ARGS=() ;;
  *) echo "Usage: $0 [debug|offline|release]" >&2; exit 2 ;;
esac
python3 tools/android_preflight.py "${PREFLIGHT_ARGS[@]}"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ "$MODE" == release ]]; then
  : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?Release keystore path required}"
  : "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?Release key alias required}"
  : "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?Release key password required}"
  [[ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]] || { echo "Release keystore missing" >&2; exit 2; }
fi
./scripts/run_qa.sh
"$GODOT_BIN" --headless --editor --path "$TASK_ROOT" --import
GODOT_BIN="$GODOT_BIN" python3 tools/configure_android.py
# Gradle export requires the matching official android_source.zip unpacked at android/build/.
if [[ "$MODE" != offline && ! -f android/build/build.gradle ]]; then
  python3 tools/install_android_template.py
fi
mkdir -p builds/android
if [[ "$MODE" == release ]]; then
  "$GODOT_BIN" --headless --path "$TASK_ROOT" --export-release "$PRESET" builds/android/slime-rush-release.aab
else
  "$GODOT_BIN" --headless --path "$TASK_ROOT" --export-debug "$PRESET" "builds/android/slime-rush-${MODE}.apk"
fi
