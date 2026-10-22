class_name AbsorptionRules
extends RefCounted
## Multi-factor absorption decision engine.
## Evaluates mass, target category, armor/shell state, player mutations/synergies,
## target status effects (frozen, stunned, poisoned, vulnerable), and temporary buffs.

const CATEGORY_BASE_RATIO: Dictionary = {
	"orb": 0.0,
	"flora": 0.82,
	"insect": 0.94,
	"toxic": 1.05,
	"ambusher": 1.16,
	"electric": 1.14,
	"predator": 1.12,
	"armored": 1.08,
	"miniboss": 1.35,
	"boss": 999.0
}


static func evaluate(player_ctx: Dictionary, target_ctx: Dictionary) -> Dictionary:
	var category: String = str(target_ctx.get("category", "insect"))
	if category == "orb":
		return {
			"can_absorb": true,
			"required_ratio": 0.0,
			"effective_ratio": 99.0,
			"reason": "ok",
			"cracks_shell": false
		}

	if category == "boss":
		# Bosses must be defeated down to <= 6% HP execution threshold before final core absorption
		var boss_hp_ratio: float = float(target_ctx.get("hp_ratio", 1.0))
		var can_exec := boss_hp_ratio <= 0.06
		return {
			"can_absorb": can_exec,
			"required_ratio": 1.0,
			"effective_ratio": 1.0 if can_exec else 0.0,
			"reason": "ok" if can_exec else "boss_active",
			"cracks_shell": false
		}

	var player_mass: float = maxf(1.0, float(player_ctx.get("mass", 10.0)))
	var target_mass: float = maxf(0.5, float(target_ctx.get("mass", 8.0)))
	var raw_ratio: float = player_mass / target_mass

	var req_ratio: float = float(CATEGORY_BASE_RATIO.get(category, 1.0))
	var armor: float = clampf(float(target_ctx.get("armor", 0.0)), 0.0, 0.90)
	var shell_active: bool = bool(target_ctx.get("shell_active", false))

	# Player offensive/tactical modifiers
	var spikes_lv: int = int(player_ctx.get("spikes_level", 0))
	var ranged_lv: int = int(player_ctx.get("ranged_absorb_level", 0))
	var has_piercing: bool = bool(player_ctx.get("has_piercing_strike", false))
	var has_vampirism: bool = bool(player_ctx.get("has_bio_vampirism", false))
	var is_dashing: bool = bool(player_ctx.get("is_dashing", false))
	var ambush_ready: bool = bool(player_ctx.get("mimicry_ambush_ready", false))
	var frenzy_mult: float = float(player_ctx.get("temp_absorb_bonus", 0.0))

	# Target state modifiers
	var is_frozen: bool = bool(target_ctx.get("is_frozen", false))
	var is_stunned: bool = bool(target_ctx.get("is_stunned", false))
	var is_poisoned: bool = bool(target_ctx.get("is_poisoned", false))
	var is_vulnerable: bool = bool(target_ctx.get("is_vulnerable", false))
	var hp_ratio: float = clampf(float(target_ctx.get("hp_ratio", 1.0)), 0.0, 1.0)

	# Armored shell gate: active Stone Slug shell resists normal gulping unless cracked or overwhelmed
	var cracks_shell := false
	if shell_active:
		if (is_dashing and has_piercing) or spikes_lv >= 2 or is_frozen or is_stunned:
			cracks_shell = true
			shell_active = false
		else:
			req_ratio += 1.15

	# Remaining armor adds modest absorption resistance mitigated by spikes
	var effective_armor := maxf(0.0, armor - float(spikes_lv) * 0.16)
	req_ratio += effective_armor * 0.45

	# Target statuses significantly lower absorption threshold (rewarding tactical mutations!)
	if is_frozen:
		req_ratio -= 0.24
	if is_stunned:
		req_ratio -= 0.22
	if is_poisoned:
		req_ratio -= 0.16
	if is_vulnerable:
		req_ratio -= 0.26

	# Damaged creatures (<60% HP) become progressively easier to absorb; <=15% HP is always finishable
	if hp_ratio <= 0.15:
		req_ratio = minf(req_ratio, 0.35)
	elif hp_ratio < 0.65:
		req_ratio -= (0.65 - hp_ratio) * 0.55

	# Player capability bonuses
	var bonus_ratio: float = frenzy_mult
	if ranged_lv > 0:
		bonus_ratio += 0.10 + float(ranged_lv) * 0.03
	if has_vampirism:
		bonus_ratio += 0.18
	if ambush_ready:
		bonus_ratio += 0.25
	if is_dashing:
		bonus_ratio += 0.12

	req_ratio = maxf(0.30, req_ratio - bonus_ratio)
	var can_absorb := raw_ratio >= req_ratio

	var reason := "ok"
	if not can_absorb:
		if shell_active:
			reason = "armored_shell"
		else:
			reason = "insufficient_mass"

	return {
		"can_absorb": can_absorb,
		"required_ratio": req_ratio,
		"effective_ratio": raw_ratio,
		"reason": reason,
		"cracks_shell": cracks_shell
	}
