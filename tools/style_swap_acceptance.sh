#!/usr/bin/env bash
# ACCEPTANCE CAPTURE — the real Godot arena, original vs organic, same conditions.
#
# Every pair is produced by tools/style_swap_capture.gd with SWAP_AB=1: ONE run,
# ONE frozen simulation state, two visual classes. The world is shared, so the
# only variable between "<name>_organic.png" and "<name>_original.png" is the
# style under test. Event-armed moments (impact / swallow / reel / electro /
# dash) fail loudly instead of saving a frame taken after the effect ended.
#
# Usage: tools/style_swap_acceptance.sh [out_dir] [shot ...]
#   no shot names  -> everything below
#   out_dir        -> default deliverables/glm_visual_lab/acceptance/shots
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-/Users/turpal/godot45/Godot.app/Contents/MacOS/Godot}"
# The capture scene boots Main.tscn, so it runs the real SaveData autoload. Point
# HOME at a scratch directory so the stills cannot touch the owner's profile
# (Godot resolves user:// under $HOME/Library/Application Support/Godot).
if [ "${SWAP_KEEP_PROFILE:-0}" != "1" ]; then
  export HOME="${SWAP_HOME:-/tmp/smush_acceptance_home}"
  mkdir -p "$HOME"
fi
OUT="${1:-deliverables/glm_visual_lab/acceptance/shots}"
shift || true
mkdir -p "$OUT"

# name | env for the capture scene
capture() {
  local name="$1"; shift
  echo "--- $name"
  # QUICK_CAPTURE_OUT marks the process as unattended for GameManager: without it a
  # focus change pauses the run and the frame becomes the pause overlay (or the
  # boss freezes mid-telegraph and the armed wait times out).
  env SWAP_AB=1 SWAP_EYES=open SWAP_OUT="$OUT/$name" QUICK_CAPTURE_OUT="$OUT/$name" "$@" \
    "$GODOT_BIN" --path "$ROOT" res://tools/StyleSwapCapture.tscn 2>&1 \
    | grep -E "SWAP_AB|SWAP_ARMED_TIMEOUT|SWAP_PAUSED|SWAP: " || true
}

stage() {
  capture "arena_stage$(printf '%02d' "$1")" \
    SWAP_STAGE="$1" SWAP_WAIT=1.0 SWAP_TIMEOUT=12
}

run_all() {
  for s in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do stage "$s"; done

  # Absorption: small prey reeled in (pseudopod + sucker), then a big one.
  capture arena_absorb_small SWAP_STAGE=8 SWAP_MUT=ranged_absorb \
    SWAP_ABSORB=small SWAP_AT=reel SWAP_AFTER=0.30 SWAP_TIMEOUT=8
  # A big prey at 205 px: the reel is ~0.45 s, so 0.14 s after the first target
  # tick the limb is mid-flight instead of the prey already swallowed.
  capture arena_absorb_large SWAP_STAGE=8 SWAP_MUT=ranged_absorb \
    SWAP_ABSORB=large SWAP_PREY_DIST=205 SWAP_AT=reel SWAP_AFTER=0.14 SWAP_TIMEOUT=8
  # The swallow itself: ghost inside the membrane, ripple still alive. Small prey
  # keeps the frame clean; the large one always crosses a stage and the real
  # evolution flash washes the body out for 0.6 s.
  capture arena_swallow_small SWAP_STAGE=8 SWAP_MUT=ranged_absorb \
    SWAP_ABSORB=small SWAP_AT=swallow SWAP_AFTER=0.10 SWAP_TIMEOUT=8
  capture arena_swallow_large SWAP_STAGE=8 SWAP_MUT=ranged_absorb \
    SWAP_ABSORB=large SWAP_AT=swallow SWAP_AFTER=0.10 SWAP_TIMEOUT=8

  # Shield: raised (idle) and the instant a real hit is blocked. The hitter has to
  # be heavier than the player at this mass or the arena absorbs it on contact and
  # no damage (therefore no block) is ever dealt — stone_slug works at stage 1-3,
  # umbral_alpha is the one that still lands a hit at stage 8.
  capture arena_shield_idle SWAP_STAGE=8 SWAP_MUT=shield SWAP_WAIT=1.6
  capture arena_shield_impact SWAP_STAGE=8 SWAP_MUT=shield \
    SWAP_HITTER=umbral_alpha SWAP_AT=impact SWAP_AFTER=0.10 SWAP_TIMEOUT=10

  # Electro: the frame right after the real pulse timer resets.
  capture arena_electro SWAP_STAGE=8 SWAP_MUT=electro_discharge \
    SWAP_ENEMIES=6 SWAP_RING=200 SWAP_AT=electro SWAP_AFTER=0.08 SWAP_TIMEOUT=8

  # Motion: dashing and swimming.
  capture arena_dash SWAP_STAGE=8 SWAP_MUT=dash SWAP_MOVE=1 SWAP_DASH=1 \
    SWAP_AT=dash SWAP_AFTER=0.12 SWAP_TIMEOUT=8
  capture arena_move SWAP_STAGE=8 SWAP_MOVE=1 SWAP_WAIT=1.4

  # Stress frame: many enemies + boss + effects at once, for artefacts and fill.
  capture arena_stress SWAP_STAGE=12 SWAP_HP=5000 SWAP_ENEMIES=24 SWAP_RING=300 \
    SWAP_BOSS=1 SWAP_WAIT=1.4

  # Boss combat: armed on a real TELEGRAPH_* state, so the danger lane is on
  # screen and nothing has landed yet.
  capture arena_boss SWAP_STAGE=10 SWAP_HP=5000 SWAP_BOSS=1 \
    SWAP_AT=boss_telegraph SWAP_AFTER=0.45 SWAP_TIMEOUT=14
}

if [ "$#" -eq 0 ]; then
  run_all
else
  for s in "$@"; do
    case "$s" in
      stage*) stage "${s#stage}" ;;
      *) echo "unknown shot: $s" >&2; exit 2 ;;
    esac
  done
fi
echo "done -> $OUT"
