class_name PlayerSlime
extends CharacterBody2D
## Playable Slime character controller combining inertial movement, non-linear mass growth,
## multi-factor absorption, and all 12 mutations + 5 synergies.

var mass: float = MassSystem.DEFAULT_START_MASS
var peak_mass: float = MassSystem.DEFAULT_START_MASS
var max_hp: float = 100.0
var hp: float = 100.0
var evolution_xp: float = 0.0
var evolution_level: int = 0
var absorbed_count: int = 0

var move_input: Vector2 = Vector2.ZERO
var base_move_speed: float = 232.0
var base_accel: float = 1080.0
var base_friction: float = 790.0

var mutations: MutationManager = MutationManager.new()
var visual: SlimeVisual
var collision_shape: CollisionShape2D
var circle_shape: CircleShape2D
var arena_ref: Node = null

# Active ability & status timers
var is_dashing: bool = false
var _dash_timer: float = 0.0
var dash_cooldown: float = 0.0
var dash_cooldown_max: float = 4.2
var _dash_dir: Vector2 = Vector2.DOWN
var invulnerable_timer: float = 0.0

var shield_ready: bool = false
var _shield_recharge_timer: float = 0.0

var split_cooldown: float = 0.0
var split_cooldown_max: float = 10.0

var _poison_drop_timer: float = 0.0
var _electro_timer: float = 1.5
var _freeze_timer: float = 2.0
var _tendril_tick: float = 0.0
var _combat_quiet_timer: float = 5.0
var _slipstream_charge: float = 0.0
var _slipstream_wave_cd: float = 0.0
var slipstream_active: bool = false
var mimicry_ambush_ready: bool = false
var is_dead: bool = false
var revive_used: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 4 # Static world obstacles
	circle_shape = CircleShape2D.new()
	circle_shape.radius = MassSystem.radius_from_mass(mass)
	collision_shape = CollisionShape2D.new()
	collision_shape.shape = circle_shape
	add_child(collision_shape)

	visual = SlimeVisual.new()
	add_child(visual)
	_sync_mass_metrics()


func initialize_for_run(p_arena: Node) -> void:
	arena_ref = p_arena
	mutations.reset()
	is_dead = false
	revive_used = false
	absorbed_count = 0
	evolution_xp = 0.0
	evolution_level = 0
	velocity = Vector2.ZERO
	move_input = Vector2.ZERO
	_dash_timer = 0.0
	_dash_dir = Vector2.DOWN
	_poison_drop_timer = 0.0
	_electro_timer = 1.5
	_freeze_timer = 2.0
	_tendril_tick = 0.0
	_combat_quiet_timer = 5.0
	_slipstream_charge = 0.0
	_slipstream_wave_cd = 0.0
	slipstream_active = false
	mimicry_ambush_ready = false

	var start_mass_bonus := SaveData.get_upgrade_bonus("start_mass")
	mass = MassSystem.clamp_mass(MassSystem.DEFAULT_START_MASS + start_mass_bonus)
	peak_mass = mass

	max_hp = 100.0 + SaveData.get_upgrade_bonus("max_vitality")
	hp = max_hp
	invulnerable_timer = 0.8
	is_dashing = false
	dash_cooldown = 0.0
	split_cooldown = 0.0
	shield_ready = false
	_shield_recharge_timer = 0.0

	if visual != null:
		visual.is_dying = false
		visual.death_progress = 0.0
		visual.apply_cosmetics()

	_sync_mass_metrics()
	Events.player_hp_changed.emit(hp, max_hp)
	Events.evolution_progress_changed.emit(evolution_xp, MassSystem.evolution_threshold_for_level(evolution_level), evolution_level)


func _sync_mass_metrics() -> void:
	mass = MassSystem.clamp_mass(mass)
	if mass > peak_mass:
		peak_mass = mass
		SaveData.increment_stat("peak_mass", peak_mass)
	var r := MassSystem.radius_from_mass(mass)
	if circle_shape != null:
		circle_shape.radius = r * 0.86
	if visual != null:
		visual.radius = r
		visual.set_growth(mass)
		visual.mutation_levels = mutations.levels
		visual.active_synergies = mutations.active_synergies
	Events.player_mass_changed.emit(mass, r)


func get_radius() -> float:
	return MassSystem.radius_from_mass(mass)


func build_absorption_context() -> Dictionary:
	return mutations.build_player_absorption_context(mass, is_dashing, mimicry_ambush_ready)


func get_effective_visibility_multiplier() -> float:
	var vis := MassSystem.visibility_multiplier(mass)
	if mutations.has_mutation("magnet"):
		vis += 0.06
	if mutations.has_mutation("electro_discharge"):
		vis += 0.10
	if mutations.has_mutation("mimicry"):
		var red := mutations.get_scaled_param("mimicry", "detect_reduction_base", "detect_reduction_per_level", 0.28)
		if velocity.length() < 65.0:
			red += 0.14
		vis *= clampf(1.0 - red, 0.28, 1.0)
	return vis


func trigger_dash() -> bool:
	if is_dead or not mutations.has_mutation("dash") or dash_cooldown > 0.0 or is_dashing:
		return false
	var cfg := ConfigDB.get_mutation("dash")
	var params: Dictionary = cfg.get("params", {})
	var cd := mutations.get_scaled_param("dash", "cooldown_base", "cooldown_per_level", 4.2)
	dash_cooldown_max = maxf(1.4, cd)
	dash_cooldown = dash_cooldown_max
	is_dashing = true
	var dur: float = float(params.get("dash_duration", 0.26))
	if mutations.has_synergy("piercing_strike"):
		dur *= 1.22
	_dash_timer = dur
	invulnerable_timer = maxf(invulnerable_timer, float(params.get("iframes_sec", 0.24)))

	_dash_dir = move_input.normalized() if move_input.length() > 0.1 else (velocity.normalized() if velocity.length() > 5.0 else visual.look_dir.normalized())
	if _dash_dir.length_squared() < 0.01:
		_dash_dir = Vector2.UP

	# Subtle tactical mass burn above MIN_MASS lets players trim excess bulk if desired
	if mass > MassSystem.MIN_MASS + 1.5:
		mass = MassSystem.clamp_mass(mass * 0.985)
		_sync_mass_metrics()

	Audio.play_sfx("attack", 1.15)
	Events.active_skill_cooldown_updated.emit("dash", dash_cooldown, dash_cooldown_max)
	return true


func trigger_split_clone() -> bool:
	if is_dead or not mutations.has_mutation("split") or split_cooldown > 0.0:
		return false
	if arena_ref == null or not arena_ref.has_method("spawn_slime_clones"):
		return false
	var cd := mutations.get_scaled_param("split", "cooldown_base", "cooldown_per_level", 10.5)
	split_cooldown_max = maxf(4.5, cd)
	split_cooldown = split_cooldown_max

	var loan := 0.0
	if mass >= 16.0:
		loan = minf(mass - 14.5, mass * 0.08)
		mass = MassSystem.clamp_mass(mass - loan)
		_sync_mass_metrics()

	var clone_count: int = 2 if mutations.has_synergy("toxic_clones") else 1
	var dps := mutations.get_scaled_param("split", "clone_damage_base", "clone_damage_per_level", 18.0)
	arena_ref.call("spawn_slime_clones", self, clone_count, 7.0, dps, mutations.has_synergy("toxic_clones"), loan / float(clone_count))
	Audio.play_sfx("absorb", 1.35)
	Events.active_skill_cooldown_updated.emit("split", split_cooldown, split_cooldown_max)
	return true


func consume_ambush_strike() -> float:
	if not mimicry_ambush_ready or not mutations.has_mutation("mimicry"):
		return 0.0
	mimicry_ambush_ready = false
	_combat_quiet_timer = 0.0
	if visual != null:
		visual.stealth_alpha = 0.94
	var lv := mutations.get_level("mimicry")
	return 26.0 + float(lv - 1) * 11.0


func refund_clone_mass(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	mass = MassSystem.clamp_mass(mass + amount)
	_sync_mass_metrics()


func _physics_process(delta: float) -> void:
	if is_dead:
		if visual != null:
			visual.death_progress = move_toward(visual.death_progress, 1.0, delta * 2.2)
		return

	_update_timers_and_passives(delta)
	_process_movement(delta)


func _process_movement(delta: float) -> void:
	var input_vec := move_input
	if input_vec.length_squared() < 0.001:
		# Desktop/keyboard convenience fallback (Arrow keys + WASD)
		var kx := Input.get_axis("ui_left", "ui_right")
		var ky := Input.get_axis("ui_up", "ui_down")
		if absf(kx) < 0.01 and absf(ky) < 0.01:
			kx = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
			ky = (1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0)
		input_vec = Vector2(kx, ky).limit_length(1.0)

	var upg_spd_mult := 1.0 + SaveData.get_upgrade_bonus("move_speed")
	var spd_lv := mutations.get_level("speed_boost")
	var mut_spd_mult := 1.0 + float(spd_lv) * 0.09 + (0.12 if slipstream_active else 0.0)
	if mutations.has_mutation("spikes"):
		mut_spd_mult -= 0.03
	var mass_maneuver := MassSystem.maneuverability_multiplier(mass)
	var max_spd := base_move_speed * upg_spd_mult * mut_spd_mult * mass_maneuver

	if is_dashing:
		velocity = _dash_dir * (max_spd * 2.65)
	elif input_vec.length() > 0.04:
		var accel := base_accel * (1.0 + float(spd_lv) * 0.14) * mass_maneuver
		var pre_move_spd := velocity.length()
		var sharp_turn := false
		# Counter-traction turn assist: responsive direction reversals without losing organic glide
		if pre_move_spd > 25.0:
			var align := velocity.normalized().dot(input_vec.normalized())
			if align < 0.35:
				sharp_turn = true
				if slipstream_active and align < -0.25 and _slipstream_wave_cd <= 0.0 and arena_ref != null and arena_ref.has_method("trigger_slipstream_wave"):
					_slipstream_wave_cd = 1.9
					_slipstream_charge = 0.25
					arena_ref.call("trigger_slipstream_wave", global_position, 120.0, 16.0 + float(spd_lv) * 8.0)
				accel *= lerpf(1.95, 1.0, clampf((align + 0.5) / 0.85, 0.0, 1.0))
		var target_vel := input_vec * max_spd
		velocity = velocity.move_toward(target_vel, accel * delta)
		if visual != null:
			visual.look_dir = input_vec.normalized()
		if (pre_move_spd < 38.0 or sharp_turn) and Audio._move_cooldown > 0.38:
			Audio._move_cooldown = 0.38
		Audio.play_sfx("move", lerpf(1.15, 0.82, clampf((mass - 10.0) / 90.0, 0.0, 1.0)))
	else:
		velocity = velocity.move_toward(Vector2.ZERO, base_friction * delta)

	# Build or decay Speed Boost slipstream state
	if spd_lv > 0 and velocity.length() >= max_spd * 0.68:
		_slipstream_charge = minf(1.0, _slipstream_charge + delta * 1.05)
	else:
		_slipstream_charge = maxf(0.0, _slipstream_charge - delta * 1.6)
	slipstream_active = (spd_lv > 0 and _slipstream_charge >= 0.95)

	var pre_vel := velocity
	move_and_slide()

	if get_slide_collision_count() > 0:
		var col := get_slide_collision(0)
		if col != null and visual != null:
			visual.trigger_wall_bump(col.get_normal())
			velocity = pre_vel.bounce(col.get_normal()) * 0.35

	# Clamp inside Enchanted Forest arena bounds & check narrow root corridors
	if arena_ref != null:
		if arena_ref.has_method("constrain_player_position"):
			global_position = arena_ref.call("constrain_player_position", global_position, get_radius(), is_dashing)

	if visual != null:
		visual.velocity_vec = velocity
		visual.is_dashing = is_dashing
		visual.shield_active = shield_ready
		visual.slipstream_active = slipstream_active


func _update_timers_and_passives(delta: float) -> void:
	if invulnerable_timer > 0.0:
		invulnerable_timer = maxf(0.0, invulnerable_timer - delta)

	if is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			is_dashing = false

	if dash_cooldown > 0.0:
		dash_cooldown = maxf(0.0, dash_cooldown - delta)
		Events.active_skill_cooldown_updated.emit("dash", dash_cooldown, dash_cooldown_max)

	if _slipstream_wave_cd > 0.0:
		_slipstream_wave_cd = maxf(0.0, _slipstream_wave_cd - delta)

	if split_cooldown > 0.0:
		split_cooldown = maxf(0.0, split_cooldown - delta)
		Events.active_skill_cooldown_updated.emit("split", split_cooldown, split_cooldown_max)
	elif mutations.has_mutation("split") and velocity.length() > 35.0 and mass >= 18.0:
		# One-finger combat assist: auto-bud clone only when active combat/cluster is nearby
		if arena_ref != null and arena_ref.has_method("has_nearby_split_opportunity") and bool(arena_ref.call("has_nearby_split_opportunity", global_position)):
			trigger_split_clone()

	_combat_quiet_timer += delta * (1.35 if velocity.length() < 90.0 else 1.0)

	# Shield recharge
	if mutations.has_mutation("shield") and not shield_ready:
		if _shield_recharge_timer <= 0.0:
			shield_ready = true
			Events.player_shield_recharged.emit()
		else:
			_shield_recharge_timer -= delta
			if _shield_recharge_timer <= 0.0:
				shield_ready = true
				Events.player_shield_recharged.emit()

	# Cellular Regeneration
	if mutations.has_mutation("regeneration") and hp < max_hp:
		var regen := mutations.get_scaled_param("regeneration", "hp_per_sec_base", "hp_per_sec_per_level", 2.6)
		if _combat_quiet_timer < 1.5:
			regen *= 0.45
		heal(regen * delta)

	# Mimicry camouflage & ambush charge
	if mutations.has_mutation("mimicry"):
		mimicry_ambush_ready = (_combat_quiet_timer >= 1.2)
		if visual != null:
			visual.stealth_alpha = 0.62 if mimicry_ambush_ready else 0.92
	elif visual != null:
		mimicry_ambush_ready = false
		visual.stealth_alpha = 1.0

	if arena_ref == null:
		return

	# Poison trail pools
	if mutations.has_mutation("poison_trail") and velocity.length() > 32.0:
		_poison_drop_timer -= delta
		if _poison_drop_timer <= 0.0:
			_poison_drop_timer = 0.38
			var dps := mutations.get_scaled_param("poison_trail", "dps_base", "dps_per_level", 14.0)
			arena_ref.call("spawn_player_poison_pool", global_position, get_radius() * 1.05, 3.4, dps)

	# Magnet & Electromagnetic Storm pull
	if mutations.has_mutation("magnet"):
		var pull_r := mutations.get_scaled_param("magnet", "pull_radius_base", "pull_radius_per_level", 145.0)
		var pull_f := mutations.get_scaled_param("magnet", "pull_force_base", "pull_force_per_level", 260.0)
		if mutations.has_synergy("em_storm"):
			pull_r += 75.0
		arena_ref.call("apply_magnet_field", global_position, pull_r, pull_f, delta, mutations.has_synergy("em_storm"))

	# Electro Discharge
	if mutations.has_mutation("electro_discharge"):
		_electro_timer -= delta
		if _electro_timer <= 0.0:
			var interval := maxf(1.1, mutations.get_scaled_param("electro_discharge", "interval_base", "interval_per_level", 3.4))
			_electro_timer = interval
			var rad := mutations.get_scaled_param("electro_discharge", "radius_base", "radius_per_level", 150.0)
			var dmg := mutations.get_scaled_param("electro_discharge", "damage_base", "damage_per_level", 22.0)
			var targets: int = 2 + (2 if mutations.has_synergy("em_storm") else 0)
			if mutations.has_synergy("em_storm"):
				rad += 60.0
				dmg *= 1.35
			arena_ref.call("trigger_electro_pulse", global_position, rad, dmg, targets, 0.75)

	# Freeze Cryo-Aura
	if mutations.has_mutation("freeze"):
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_freeze_timer = 3.6
			var frad := mutations.get_scaled_param("freeze", "radius_base", "radius_per_level", 140.0)
			var slow := clampf(mutations.get_scaled_param("freeze", "slow_factor_base", "slow_per_level", 0.42), 0.25, 0.78)
			arena_ref.call("trigger_freeze_pulse", global_position, frad, slow, 2.6)

	# Ranged Absorb & Bio-Vampirism Tendrils
	if mutations.has_mutation("ranged_absorb"):
		_tendril_tick -= delta
		if _tendril_tick <= 0.0:
			_tendril_tick = 0.10
			var rng := mutations.get_scaled_param("ranged_absorb", "range_base", "range_per_level", 155.0)
			var reel := mutations.get_scaled_param("ranged_absorb", "reel_speed_base", "reel_speed_per_level", 310.0)
			var pts: Array[Vector2] = arena_ref.call("process_ranged_tendrils", self, global_position, rng, reel, 0.10, mutations.has_synergy("bio_vampirism"))
			if visual != null:
				visual.active_tendril_targets = pts
	elif visual != null and not visual.active_tendril_targets.is_empty():
		visual.active_tendril_targets.clear()


func complete_absorption(entity_id: String, mass_gain: float, xp_gain: float, essence_drop: int, world_pos: Vector2) -> void:
	if is_dead:
		return
	absorbed_count += 1
	SaveData.increment_stat("total_absorbed", 1.0)
	SaveData.record_creature_seen(entity_id, 1)

	# 1 & 2. Slime deformation bulge
	if visual != null:
		visual.trigger_gulp()

	# 3. Non-linear mass increase
	var eff_mass := MassSystem.effective_gain(mass, mass_gain)
	mass = MassSystem.clamp_mass(mass + eff_mass)
	_sync_mass_metrics()

	# Bio-vampirism heal on absorb (balanced so combat still rewards dodging)
	if mutations.has_synergy("bio_vampirism"):
		heal(4.5)

	# Mimicry ambush resets briefly on strike
	if mimicry_ambush_ready:
		_combat_quiet_timer = 0.0
		mimicry_ambush_ready = false

	# 4 & 5. Sound & Evolution XP
	Audio.play_sfx("absorb", randf_range(0.92, 1.18))
	var evo_mult := 1.0 + SaveData.get_upgrade_bonus("evolution_rate")
	add_evolution_xp(xp_gain * evo_mult)

	Events.entity_absorbed.emit(entity_id, eff_mass, xp_gain, world_pos)

	# 7. Essence reward if dropped
	if essence_drop > 0 and arena_ref != null and arena_ref.has_method("add_run_essence"):
		arena_ref.call("add_run_essence", essence_drop)


func add_evolution_xp(amount: float) -> void:
	if amount < 0.0 or is_dead:
		return
	evolution_xp += amount
	var threshold := MassSystem.evolution_threshold_for_level(evolution_level)
	Events.evolution_progress_changed.emit(evolution_xp, threshold, evolution_level)
	# Keep the current cards stable if several pickups complete in one frame.
	if App.state == App.State.MUTATION_DRAFT:
		return
	while evolution_xp >= threshold:
		evolution_xp -= threshold
		evolution_level += 1
		if visual != null:
			visual.trigger_evolution()
		Audio.play_sfx("evolution", 1.0)
		threshold = MassSystem.evolution_threshold_for_level(evolution_level)
		Events.evolution_progress_changed.emit(evolution_xp, threshold, evolution_level)
		if arena_ref != null and arena_ref.has_method("request_mutation_draft"):
			arena_ref.call("request_mutation_draft")
			if App.state == App.State.MUTATION_DRAFT:
				return


func heal(amount: float) -> void:
	if amount <= 0.0 or is_dead:
		return
	hp = minf(max_hp, hp + amount)
	Events.player_hp_changed.emit(hp, max_hp)


func take_damage(raw_amount: float, source_id: String, is_aoe_hazard: bool = false, knockback_from: Vector2 = Vector2.INF) -> bool:
	if is_dead or raw_amount <= 0.0 or invulnerable_timer > 0.0:
		return false

	_combat_quiet_timer = 0.0

	# Shield mutation blocks one hit completely!
	if mutations.has_mutation("shield") and shield_ready:
		shield_ready = false
		var rech := mutations.get_scaled_param("shield", "recharge_base", "recharge_per_level", 11.0)
		if mutations.has_synergy("ice_armor"):
			rech -= 2.0
		_shield_recharge_timer = maxf(3.2, rech)
		invulnerable_timer = 0.45
		Audio.play_sfx("shield_break", 1.0)
		Events.player_shield_triggered.emit()
		if arena_ref != null:
			arena_ref.call("on_player_shield_burst", global_position, mutations.has_synergy("ice_armor"))
		return false

	var final_dmg := raw_amount
	if is_aoe_hazard:
		final_dmg *= MassSystem.aoe_vulnerability_multiplier(mass)
		if source_id == "poison_pool" and slipstream_active:
			final_dmg *= 0.50

	hp = maxf(0.0, hp - final_dmg)
	invulnerable_timer = 0.32
	if visual != null:
		visual.trigger_hurt()
	Audio.play_sfx("hurt", 1.0)

	if knockback_from != Vector2.INF:
		var kb_dir := (global_position - knockback_from).normalized()
		var kb_mult := 1.10 if mutations.has_mutation("speed_boost") else 1.0
		velocity += kb_dir * 210.0 * kb_mult

	Events.player_damaged.emit(final_dmg, source_id)
	Events.player_hp_changed.emit(hp, max_hp)

	if hp <= 0.0:
		is_dead = true
		if visual != null:
			visual.is_dying = true
		if arena_ref != null and arena_ref.has_method("on_player_died"):
			arena_ref.call("on_player_died")
	return true


func revive_player() -> bool:
	if revive_used:
		return false
	revive_used = true
	is_dead = false
	hp = max_hp
	invulnerable_timer = 2.6
	if visual != null:
		visual.is_dying = false
		visual.death_progress = 0.0
		visual.trigger_evolution()
	Events.player_hp_changed.emit(hp, max_hp)
	return true
