class_name GameModes
extends RefCounted
## The four ways to play, in one table.
##
## Mode rules used to be an inline `mode_id == "quick"` check repeated in the arena,
## the menu and the save file. Two more modes written that way would have meant four
## copies of every rule and at least one of them would have drifted, so the rules live
## here and everything reads from this table: the arena, the mode menu, the save
## sanitiser and the tests.
##
## `standard` and `quick` reproduce the previous behaviour exactly - their timings and
## multipliers are the old literals, not a re-derivation - because a mode split must
## not silently retune the two modes people already play.
##
## Two design decisions worth stating, because the brief leaves them open:
##
## 1. `zen` has no Guardian and no miniboss. The brief asks for a contemplative mode
##    "без давления" and for the run to end when the player says so; a three-phase
##    boss on a timer is the opposite of that, and its damage telegraphs would still
##    have to be read even at 20% damage. The run ends through the pause menu's
##    "finish the walk" button, which commits everything collected so far.
## 2. `endless` keeps the standard timings for the first Guardian. After each defeat
##    the next one is scheduled 270 s later, so the pacing inside a loop stays the
##    pacing the boss was tuned against.

const STANDARD := "standard"
const QUICK := "quick"
const ENDLESS := "endless"
const ZEN := "zen"

## Menu order. `standard` first because it is the intended first run.
const ORDER: Array[String] = [STANDARD, QUICK, ENDLESS, ZEN]

## Every key is present in every mode, so a test can assert the table is complete
## instead of discovering a missing key at runtime in one mode only.
##
## `time_scale` stretches run time for difficulty scaling only (enemy stat growth and
## spawn tiers); it does not touch the timers themselves.
const MODES: Dictionary = {
	STANDARD: {
		"name_key": "mode.standard.name",
		"desc_key": "mode.standard.desc",
		"miniboss_time": 165.0,
		"boss_time": 270.0,
		"time_scale": 1.0,
		"dash_mass_burn": 0.015,
		"damage_mult": 1.0,
		"hp_floor_frac": 0.0,
		"enemy_period_mult": 1.0,
		"orb_period_mult": 1.0,
		"has_miniboss": true,
		"has_boss": true,
		"endless": false,
		"zen": false,
		"music": "run",
	},
	QUICK: {
		"name_key": "mode.quick.name",
		"desc_key": "mode.quick.desc",
		"miniboss_time": 80.0,
		"boss_time": 145.0,
		"time_scale": 1.85,
		"dash_mass_burn": 0.015,
		"damage_mult": 1.0,
		"hp_floor_frac": 0.0,
		"enemy_period_mult": 1.0,
		"orb_period_mult": 1.0,
		"has_miniboss": true,
		"has_boss": true,
		"endless": false,
		"zen": false,
		"music": "run",
	},
	ENDLESS: {
		"name_key": "mode.endless.name",
		"desc_key": "mode.endless.desc",
		"miniboss_time": 165.0,
		"boss_time": 270.0,
		"time_scale": 1.0,
		"dash_mass_burn": 0.015,
		"damage_mult": 1.0,
		"hp_floor_frac": 0.0,
		"enemy_period_mult": 1.0,
		"orb_period_mult": 1.0,
		"has_miniboss": true,
		"has_boss": true,
		"endless": true,
		"zen": false,
		"music": "run",
	},
	ZEN: {
		"name_key": "mode.zen.name",
		"desc_key": "mode.zen.desc",
		"miniboss_time": 0.0,
		"boss_time": 0.0,
		# 0.8, not 1.0: time-scaled enemy growth still creeps up slowly, so a long
		# sit does not become a frozen diorama, but it never reaches boss-tier stats.
		"time_scale": 0.8,
		"dash_mass_burn": 0.0,
		# Periods, not rates: 3.0 means an aggressive enemy arrives three times less
		# often, 0.55 means orbs arrive about 1.8x more often.
		# The brief's "80% less damage" and "never below 15% HP" are one rule with two
		# halves: the multiplier makes hits gentle, the floor makes death impossible
		# even if something lands a large hit at low health.
		"damage_mult": 0.2,
		"hp_floor_frac": 0.15,
		"enemy_period_mult": 3.0,
		"orb_period_mult": 0.55,
		"has_miniboss": false,
		"has_boss": false,
		"endless": false,
		"zen": true,
		"music": "zen",
	},
}


static func is_valid(mode_id: String) -> bool:
	return MODES.has(mode_id)


static func normalize(mode_id: String) -> String:
	## Unknown ids fall back to `standard` rather than crashing: an old save or a
	## hand-edited config should not be able to brick the game.
	return mode_id if MODES.has(mode_id) else STANDARD


static func get_mode(mode_id: String) -> Dictionary:
	return (MODES[normalize(mode_id)] as Dictionary).duplicate(true)


static func value(mode_id: String, key: String, fallback: float = 0.0) -> float:
	var cfg: Dictionary = MODES[normalize(mode_id)]
	if not cfg.has(key):
		return fallback
	return float(cfg[key])


static func time_scale(mode_id: String) -> float:
	return value(mode_id, "time_scale", 1.0)


static func dash_mass_burn(mode_id: String) -> float:
	return value(mode_id, "dash_mass_burn", 0.015)


static func damage_mult(mode_id: String) -> float:
	return value(mode_id, "damage_mult", 1.0)


static func hp_floor_frac(mode_id: String) -> float:
	return value(mode_id, "hp_floor_frac", 0.0)


static func is_zen(mode_id: String) -> bool:
	return bool((MODES[normalize(mode_id)] as Dictionary).get("zen", false))


static func is_endless(mode_id: String) -> bool:
	return bool((MODES[normalize(mode_id)] as Dictionary).get("endless", false))


static func has_boss(mode_id: String) -> bool:
	return bool((MODES[normalize(mode_id)] as Dictionary).get("has_boss", true))


static func music_for(mode_id: String) -> String:
	return str((MODES[normalize(mode_id)] as Dictionary).get("music", "run"))


static func name_key(mode_id: String) -> String:
	return str((MODES[normalize(mode_id)] as Dictionary).get("name_key", ""))


static func desc_key(mode_id: String) -> String:
	return str((MODES[normalize(mode_id)] as Dictionary).get("desc_key", ""))
