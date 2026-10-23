class_name Haptics
extends RefCounted
## Short device vibrations for impact feedback.
##
## The game is designed for one hand on a phone, where the screen is often at the edge
## of peripheral vision: a hit that only shakes the camera is easy to miss, and the
## vibration channel carries that information without any pixels.
##
## Design constraints:
## * **Never on desktop.** `Input.vibrate_handheld()` is a no-op off-device but the
##   display server still prints a warning per call, which would flood the QA log, so
##   the platform check comes first.
## * **Coalesced.** Contact damage arrives in bursts (a boss charge plus an add), and
##   one 40 ms buzz per event turns into a continuous rattle. Each kind has a minimum
##   gap, and the gap is measured in wall-clock time, not frames, so a hitch cannot
##   swallow the feedback.
## * **Opt-out.** Follows `haptics_enabled` in the save file, toggled in Settings.

## Vibrations shorter than ~15 ms are not felt on most phones; longer than ~120 ms on
## a hit reads as an error state rather than an impact.
const DURATION_MS: Dictionary = {
	"damage": 45,
	"boss_phase": 70,
	"boss_down": 110,
	"miniboss": 55,
	"evolve": 28,
	"ui": 12,
}

## Minimum wall-clock gap between two vibrations of the same kind.
const MIN_GAP_MS: Dictionary = {
	"damage": 140,
	"boss_phase": 260,
	"boss_down": 400,
	"miniboss": 300,
	"evolve": 220,
	"ui": 60,
}

static var _last_ms: Dictionary = {}


static func is_supported() -> bool:
	return OS.has_feature("mobile")


static func is_enabled() -> bool:
	if not is_supported():
		return false
	return bool(SaveData.get_setting("haptics_enabled", true))


static func play(kind: String = "damage") -> void:
	if not is_enabled():
		return
	var now := Time.get_ticks_msec()
	var gap := int(MIN_GAP_MS.get(kind, 120))
	if now - int(_last_ms.get(kind, -100000)) < gap:
		return
	_last_ms[kind] = now
	Input.vibrate_handheld(int(DURATION_MS.get(kind, 40)), 1.0)


## Test hook: forget the coalescing state so a suite can assert the gap logic.
static func reset_for_tests() -> void:
	_last_ms.clear()
