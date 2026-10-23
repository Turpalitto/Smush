class_name EvolutionStages
extends RefCounted
## The fifteen growth stages of the slime, and what each one looks like.
##
## Growth is driven by MASS, not by the mutation level: the player literally gets
## bigger as they eat, and the character has to change with the body or the
## growth is just a number. Mass runs from 10 at spawn to ~125 at the boss, so the
## thresholds below are spaced so that a normal winning run sees most of the
## ladder and a greedy run sees all of it.
##
## Everything here is pure data plus two interpolation helpers, so the visuals,
## the HUD name and the world's reaction all read from one source. Colours are
## hex strings because a `const` array of Dictionaries holding Color(...) is not a
## constant expression in GDScript; they are parsed once into a cache.

const COUNT: int = 15

## Mass at which each stage begins. Stage 1 is the spawn mass.
const MASS_KEYS: Array[float] = [
	10.0, 15.0, 20.5, 26.0, 32.0, 38.5, 45.0, 52.0,
	59.0, 66.0, 73.0, 80.0, 87.0, 95.0, 104.0,
]

## Per-stage look. The hue walks a full arc from forest teal to pearl, so no two
## stages read as "the same slime, slightly different". The ornament weights are
## 0..1 and are what makes the silhouette change, not just the colour.
const STAGES: Array[Dictionary] = [
	{"name_key": "stage.1", "body": "#2ad48c", "core": "#fff080", "rim": "#a5ffe8", "trail": "#5ef5c8",
		"glow": 0.00, "sigil": 0.00, "crown": 0.0, "halo": 0.00, "wings": 0.0, "horns": 0.0,
		"motes": 0.0, "petals": 0.0, "env": 0.00},
	{"name_key": "stage.2", "body": "#22d0a8", "core": "#fff49a", "rim": "#b6ffe6", "trail": "#74f7d0",
		"glow": 0.04, "sigil": 0.00, "crown": 0.0, "halo": 0.00, "wings": 0.0, "horns": 0.0,
		"motes": 0.0, "petals": 0.0, "env": 0.06},
	{"name_key": "stage.3", "body": "#2ad6c0", "core": "#f6ffb0", "rim": "#c6fff0", "trail": "#7cf7e0",
		"glow": 0.08, "sigil": 0.00, "crown": 0.0, "halo": 0.00, "wings": 0.0, "horns": 0.0,
		"motes": 0.0, "petals": 0.15, "env": 0.12},
	{"name_key": "stage.4", "body": "#38d8d8", "core": "#e8fbff", "rim": "#d4f6ff", "trail": "#8aeeff",
		"glow": 0.12, "sigil": 0.00, "crown": 0.0, "halo": 0.00, "wings": 0.0, "horns": 0.0,
		"motes": 0.25, "petals": 0.25, "env": 0.18},
	{"name_key": "stage.5", "body": "#40d0ee", "core": "#dcf8ff", "rim": "#dcf4ff", "trail": "#8ce4ff",
		"glow": 0.16, "sigil": 0.00, "crown": 0.35, "halo": 0.00, "wings": 0.0, "horns": 0.0,
		"motes": 0.35, "petals": 0.45, "env": 0.24},
	{"name_key": "stage.6", "body": "#52bcf6", "core": "#d8fbff", "rim": "#e6f9ff", "trail": "#8ee0ff",
		"glow": 0.20, "sigil": 0.00, "crown": 0.45, "halo": 0.00, "wings": 0.0, "horns": 0.35,
		"motes": 0.45, "petals": 0.30, "env": 0.30},
	{"name_key": "stage.7", "body": "#6fa8ff", "core": "#e6f7ff", "rim": "#f0fbff", "trail": "#9cc6ff",
		"glow": 0.24, "sigil": 0.00, "crown": 0.55, "halo": 0.00, "wings": 0.45, "horns": 0.40,
		"motes": 0.55, "petals": 0.20, "env": 0.36},
	{"name_key": "stage.8", "body": "#8f8cff", "core": "#f2e8ff", "rim": "#ffffff", "trail": "#b6b4ff",
		"glow": 0.28, "sigil": 0.00, "crown": 0.60, "halo": 0.45, "wings": 0.55, "horns": 0.45,
		"motes": 0.65, "petals": 0.15, "env": 0.42},
	{"name_key": "stage.9", "body": "#b47cff", "core": "#f6e6ff", "rim": "#efe0ff", "trail": "#cf9cff",
		"glow": 0.32, "sigil": 0.30, "crown": 0.70, "halo": 0.55, "wings": 0.60, "horns": 0.40,
		"motes": 0.75, "petals": 0.25, "env": 0.48},
	{"name_key": "stage.10", "body": "#e07cd8", "core": "#ffe4f6", "rim": "#ffd9f4", "trail": "#ff9ce8",
		"glow": 0.36, "sigil": 0.50, "crown": 0.75, "halo": 0.70, "wings": 0.70, "horns": 0.35,
		"motes": 0.85, "petals": 0.20, "env": 0.54},
	{"name_key": "stage.11", "body": "#f07cc0", "core": "#fff2b0", "rim": "#ffd9ec", "trail": "#ff9cd4",
		"glow": 0.42, "sigil": 0.65, "crown": 0.80, "halo": 0.80, "wings": 0.80, "horns": 0.30,
		"motes": 0.95, "petals": 0.30, "env": 0.60},
	{"name_key": "stage.12", "body": "#ff8f8f", "core": "#fff2b0", "rim": "#ffdcd6", "trail": "#ffb0a8",
		"glow": 0.48, "sigil": 0.78, "crown": 0.85, "halo": 0.88, "wings": 0.88, "horns": 0.25,
		"motes": 1.00, "petals": 0.35, "env": 0.66},
	{"name_key": "stage.13", "body": "#ffb45c", "core": "#fff6c0", "rim": "#ffe4bc", "trail": "#ffcc8a",
		"glow": 0.54, "sigil": 0.88, "crown": 0.90, "halo": 0.92, "wings": 0.92, "horns": 0.80,
		"motes": 1.00, "petals": 0.20, "env": 0.74},
	{"name_key": "stage.14", "body": "#ffcb52", "core": "#fff8dc", "rim": "#ffe6ac", "trail": "#ffdc84",
		"glow": 0.62, "sigil": 0.95, "crown": 0.95, "halo": 1.00, "wings": 1.00, "horns": 0.85,
		"motes": 1.00, "petals": 0.15, "env": 0.84},
	{"name_key": "stage.15", "body": "#f6dfa2", "core": "#fff6d2", "rim": "#ffe7a6", "trail": "#ffefbe",
		"glow": 0.72, "sigil": 1.00, "crown": 1.00, "halo": 1.00, "wings": 1.00, "horns": 1.00,
		"motes": 1.00, "petals": 0.10, "env": 1.00},
]

static var _parsed: Array[Dictionary] = []


static func _table() -> Array[Dictionary]:
	if _parsed.size() == COUNT:
		return _parsed
	_parsed.clear()
	for row: Dictionary in STAGES:
		var out := row.duplicate(true)
		out["body_c"] = Color(str(row["body"]))
		out["core_c"] = Color(str(row["core"]))
		out["rim_c"] = Color(str(row["rim"]))
		out["trail_c"] = Color(str(row["trail"]))
		_parsed.append(out)
	return _parsed


static func stage_for_mass(m: float) -> int:
	## 1-based, clamped to the ladder. Mass below the spawn value reads as stage 1.
	var idx := 1
	for i in range(COUNT):
		if m >= MASS_KEYS[i]:
			idx = i + 1
	return idx


static func t_for_mass(m: float) -> float:
	## Continuous position on the ladder: 1.0 at stage 1, 15.0 at stage 15, with
	## fractional values in between. This is what the visuals interpolate on, so
	## growth reads as a continuous change instead of fifteen pops.
	var s := stage_for_mass(m)
	if s >= COUNT:
		return float(COUNT)
	var lo := MASS_KEYS[s - 1]
	var hi := MASS_KEYS[s]
	var w := clampf((m - lo) / maxf(0.001, hi - lo), 0.0, 1.0)
	return float(s) + w


static func progress_to_next(m: float) -> float:
	## 0..1 within the current stage, for the HUD bar.
	##
	## At the top of the ladder `t` clamps to COUNT, so `t - floor(t)` is 0 and the
	## bar sat empty while the label read "Рост 15/15" — seen in the boss-phase-3
	## capture at mass 110.3. There is no sixteenth stage, so full is the honest
	## reading once the last threshold is passed.
	var t := t_for_mass(m)
	if t >= float(COUNT):
		return 1.0
	return t - floorf(t)


static func look_at(t: float) -> Dictionary:
	## Blended stage look for a continuous ladder position. Returns the parsed
	## dictionary with `body_c`/`core_c`/`rim_c`/`trail_c` as Color and every
	## numeric weight already lerped.
	var table := _table()
	var tt := clampf(t, 1.0, float(COUNT))
	var i := int(floorf(tt)) - 1
	var j := mini(i + 1, COUNT - 1)
	var w := tt - floorf(tt)
	var a: Dictionary = table[i]
	var b: Dictionary = table[j]
	var out: Dictionary = a.duplicate(true)
	out["body_c"] = (a["body_c"] as Color).lerp(b["body_c"] as Color, w)
	out["core_c"] = (a["core_c"] as Color).lerp(b["core_c"] as Color, w)
	out["rim_c"] = (a["rim_c"] as Color).lerp(b["rim_c"] as Color, w)
	out["trail_c"] = (a["trail_c"] as Color).lerp(b["trail_c"] as Color, w)
	for k: String in ["glow", "sigil", "crown", "halo", "wings", "horns", "motes", "petals", "env"]:
		out[k] = lerpf(float(a[k]), float(b[k]), w)
	out["stage"] = i + 1
	out["name_key"] = str(a["name_key"])
	return out


static func env_for_mass(m: float) -> float:
	## 0..1 world-bloom value. The world reads this one number to decide how
	## magical it looks, so growth is visible in the environment too.
	return float(look_at(t_for_mass(m))["env"])


static func name_key_for_stage(stage: int) -> String:
	var s := clampi(stage, 1, COUNT)
	return str(_table()[s - 1]["name_key"])
