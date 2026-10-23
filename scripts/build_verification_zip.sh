#!/usr/bin/env bash
set -euo pipefail
# Packs the evidence for one iteration: the real GPU screenshots, the summary
# JSONs, the growth sheets, the audio excerpt and a MANIFEST that says exactly
# which commit produced them.
#
# Usage:
#   ./scripts/build_verification_zip.sh [output_dir]
#
# Why this exists: the first verification archive was assembled by hand, so it
# could not be rebuilt when the art changed and its file list had to be taken on
# trust. Everything that goes in here is now named by the script and hashed into
# MANIFEST.md, including the git commit.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-$ROOT_DIR/deliverables}"
DATE="$(date +%Y-%m-%d)"
COMMIT_SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
GODOT_BIN="${GODOT_BIN:-$HOME/godot45/Godot.app/Contents/MacOS/Godot}"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null | head -n 1 || echo "unknown")"

STAGE="$(mktemp -d /tmp/smush_verify.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/SlimeRushEvolution_Verification_$DATE"
mkdir -p "$PKG/screenshots" "$PKG/reports" "$PKG/audio"

shopt -s nullglob
shots=("$ROOT_DIR/deliverables/macos_screenshots"/*.png)
reports=("$ROOT_DIR/reports"/*.json "$ROOT_DIR/reports"/growth-*.png)
audio=("$ROOT_DIR/deliverables"/*.wav "$ROOT_DIR/reports"/*.wav)

for f in "${shots[@]}"; do cp "$f" "$PKG/screenshots/"; done
for f in "${reports[@]}"; do [[ -f "$f" ]] && cp "$f" "$PKG/reports/"; done
for f in "${audio[@]}"; do [[ -f "$f" ]] && cp "$f" "$PKG/audio/"; done

{
  echo "# SLIME RUSH: EVOLUTION — verification archive ($DATE)"
  echo
  echo "- Git commit: \`$COMMIT_SHA\` (branch \`$BRANCH\`)"
  echo "- Godot: $GODOT_VER"
  echo "- Host: macOS, Apple M5, Metal 3.2 Forward Mobile"
  echo
  echo "## What is in here"
  echo
  echo "- \`screenshots/\` — ${#shots[@]} frames rendered by the game itself at 720x1280"
  echo "  (viewport capture, not a desktop screenshot: the agent process has no"
  echo "  Screen Recording permission on this machine)."
  echo "- \`reports/\` — automated QA and playthrough summaries as JSON, plus the"
  echo "  growth ladder contact sheet and the mass 10 vs mass 104 comparison."
  echo "- \`audio/\` — a Master-bus excerpt recorded after the hard limiter."
  echo
  echo "## Files"
  echo
  echo "| File | Bytes | SHA-256 (first 16) |"
  echo "|---|---|---|"
  while IFS= read -r f; do
    rel="${f#"$PKG"/}"
    size="$(wc -c < "$f" | tr -d ' ')"
    hash="$(shasum -a 256 "$f" | cut -c1-16)"
    echo "| $rel | $size | $hash |"
  done < <(find "$PKG" -type f ! -name MANIFEST.md | sort)
  echo
  echo "## What this does not prove"
  echo
  echo "- Frame rate, heat and battery on a physical Android phone."
  echo "- How the game feels under a real thumb on glass, and whether it is"
  echo "  actually charming. No script measures that."
  echo "- Audio by ear: the levels are measured, the mix is not heard by a human."
} > "$PKG/MANIFEST.md"

ARCHIVE="$OUT_DIR/SlimeRushEvolution_macOS_Verification_$DATE.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$PKG" "$ARCHIVE"
echo "Archive: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "Files:   $(find "$PKG" -type f | wc -l | tr -d ' ')"
