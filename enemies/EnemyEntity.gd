class_name EnemyEntity
extends CharacterBody2D
## Pooled creature entity configured from resources/data/enemies.json and controlled by EnemyFSM.

var enemy_id: String = "tiny_mushroom"
var category: String = "flora"
var behavior: String = "passive_hop"
var mass: float = 6.0
var max_hp: float = 20.0
var hp: float = 20.0
var move_speed: float = 60.0
var armor: float = 0.0
var contact_damage: float = 0.0
var detect_radius: float = 150.0
var xp_reward: float = 10.0
var mass_gain: float = 1.6
var essence_chance: float = 0.2
var essence_amount: int = 1
var is_miniboss: bool = false

var color_primary: Color = Color(0.94, 0.53, 0.65)
var color_secondary: Color = Color(1.0, 0.92, 0.82)

var fsm: EnemyFSM = EnemyFSM.new()
var shell_active: bool = false
var shell_broken_permanently: bool = false
var is_vulnerable: bool = false

# Status effects
var freeze_timer: float = 0.0
var slow_factor: float = 0.0
var stun_timer: float = 0.0
var poison_timer: float = 0.0
var hurt_flash: float = 0.0

var wander_dir: Vector2 = Vector2.RIGHT
var attack_dir: Vector2 = Vector2.RIGHT
var _action_cooldown: float = 1.5
var _contact_hit_cd: float = 0.0
var block_callout_cd: float = 0.0
var _anim_phase: float = 0.0
var _absorb_target: Node2D = null
var _absorb_elapsed: float = 0.0
var _readability_mode: int = -1 # -1 hidden, 0 edible, 1 armored_shell, 2 nearly_edible, 3 dangerous
var _pull_lean: Vector2 = Vector2.ZERO
var arena_ref: Node = null


func setup_from_config(cfg: Dictionary, spawn_pos: Vector2, p_arena: Node, difficulty_scale: float = 1.0, mass_scale: float = 1.0) -> void:
	arena_ref = p_arena
	global_position = spawn_pos
	scale = Vector2.ONE
	enemy_id = str(cfg.get("id", "tiny_mushroom"))
	category = str(cfg.get("category", "flora"))
	behavior = str(cfg.get("behavior", "passive_hop"))
	is_miniboss = (category == "miniboss")
	if is_miniboss:
		behavior = "hunter_stalker"

	var m_mult := mass_scale if not (category in ["flora", "insect"]) else lerpf(1.0, mass_scale, 0.20)
	mass = float(cfg.get("base_mass", 8.0)) * m_mult
	max_hp = float(cfg.get("hp", 20.0)) * difficulty_scale
	hp = max_hp
	move_speed = float(cfg.get("move_speed", 70.0))
	armor = float(cfg.get("armor", 0.0))
	contact_damage = float(cfg.get("contact_damage", 5.0)) * lerpf(1.0, difficulty_scale, 0.5)
	detect_radius = float(cfg.get("detect_radius", 180.0))
	xp_reward = float(cfg.get("xp_reward", 12.0)) * lerpf(1.0, m_mult, 0.45)
	mass_gain = float(cfg.get("mass_gain", 2.0))
	essence_chance = float(cfg.get("essence_chance", 0.25))
	essence_amount = int(cfg.get("essence_amount", 1))

	color_primary = Color(str(cfg.get("color_primary", "#9b5cff")))
	color_secondary = Color(str(cfg.get("color_secondary", "#ffebd2")))

	shell_active = false
	shell_broken_permanently = false
	is_vulnerable = false
	freeze_timer = 0.0
	slow_factor = 0.0
	stun_timer = 0.0
	poison_timer = 0.0
	hurt_flash = 0.0
	_action_cooldown = randf_range(0.8, 2.2)
	_contact_hit_cd = 0.0
	block_callout_cd = 0.0
	_absorb_target = null
	_absorb_elapsed = 0.0
	_readability_mode = -1
	_pull_lean = Vector2.ZERO
	_anim_phase = randf() * TAU
	wander_dir = Vector2.from_angle(randf() * TAU)

	if behavior == "ambush_lunge":
		fsm.transition_to(EnemyFSM.State.AMBUSH_HIDE, 999.0)
	else:
		fsm.transition_to(EnemyFSM.State.WANDER, randf_range(1.2, 2.8))
	queue_redraw()


func get_body_radius() -> float:
	if is_miniboss:
		return 34.0
	return clampf(12.0 + sqrt(mass) * 3.1, 13.0, 30.0)


func build_absorption_context() -> Dictionary:
	return {
		"category": category,
		"mass": mass,
		"armor": 0.0 if shell_broken_permanently else armor,
		"shell_active": shell_active and not shell_broken_permanently,
		"is_frozen": freeze_timer > 0.0,
		"is_stunned": stun_timer > 0.0,
		"is_poisoned": poison_timer > 0.0,
		"is_vulnerable": is_vulnerable or fsm.state == EnemyFSM.State.RECOVER,
		"hp_ratio": clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	}


func crack_shell() -> void:
	if shell_active or armor > 0.25:
		shell_active = false
		shell_broken_permanently = true
		hurt_flash = 0.9


func apply_freeze(slow_amt: float, dur: float) -> void:
	freeze_timer = maxf(freeze_timer, dur)
	slow_factor = maxf(slow_factor, clampf(slow_amt, 0.1, 0.85))


func apply_stun(dur: float) -> void:
	if fsm.state == EnemyFSM.State.BEING_ABSORBED or fsm.state == EnemyFSM.State.DEAD:
		return
	stun_timer = maxf(stun_timer, dur)
	shell_active = false
	fsm.transition_to(EnemyFSM.State.STUNNED, dur)


func apply_poison(dur: float) -> void:
	poison_timer = maxf(poison_timer, dur)


func take_damage(amount: float, armor_pierce: float = 0.0) -> bool:
	if fsm.state == EnemyFSM.State.DEAD or fsm.state == EnemyFSM.State.BEING_ABSORBED:
		return false
	var eff_armor := 0.0 if shell_broken_permanently else maxf(0.0, armor - armor_pierce)
	if shell_active and not shell_broken_permanently:
		eff_armor = clampf(eff_armor + 0.25, 0.0, 0.85)
	var dmg := amount * (1.0 - eff_armor)
	hp = maxf(0.0, hp - dmg)
	hurt_flash = 0.85
	if hp <= 0.0:
		fsm.transition_to(EnemyFSM.State.DEAD)
		if arena_ref != null and arena_ref.has_method("on_enemy_killed"):
			arena_ref.call("on_enemy_killed", self)
		return true
	return false


func begin_suction_into(target_node: Node2D) -> void:
	if fsm.state == EnemyFSM.State.BEING_ABSORBED or fsm.state == EnemyFSM.State.DEAD:
		return
	_absorb_target = target_node
	_absorb_elapsed = 0.0
	fsm.transition_to(EnemyFSM.State.BEING_ABSORBED, 0.20)


func is_active_combatant() -> bool:
	return fsm.state != EnemyFSM.State.DEAD and fsm.state != EnemyFSM.State.BEING_ABSORBED


func _physics_process(delta: float) -> void:
	_anim_phase += delta * 6.0
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 3.5)
	if freeze_timer > 0.0:
		freeze_timer = maxf(0.0, freeze_timer - delta)
		if freeze_timer <= 0.0:
			slow_factor = 0.0
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
	if poison_timer > 0.0:
		poison_timer = maxf(0.0, poison_timer - delta)
	if _action_cooldown > 0.0:
		_action_cooldown = maxf(0.0, _action_cooldown - delta)
	if _contact_hit_cd > 0.0:
		_contact_hit_cd = maxf(0.0, _contact_hit_cd - delta)
	if block_callout_cd > 0.0:
		block_callout_cd = maxf(0.0, block_callout_cd - delta)

	if fsm.state == EnemyFSM.State.DEAD:
		return

	if fsm.state == EnemyFSM.State.BEING_ABSORBED:
		_absorb_elapsed += delta
		if _absorb_target != null and is_instance_valid(_absorb_target):
			var to_mouth := _absorb_target.global_position - global_position
			_pull_lean = to_mouth.limit_length(12.0)
			global_position = global_position.lerp(_absorb_target.global_position, clampf(delta * 18.0, 0.0, 1.0))
			var shrink := clampf(1.0 - _absorb_elapsed * 4.8, 0.14, 1.0)
			scale = Vector2(shrink * 1.18, shrink * 0.82).rotated(to_mouth.angle()) if to_mouth.length() > 2.0 else Vector2.ONE * shrink
		if _absorb_elapsed >= 0.18:
			fsm.transition_to(EnemyFSM.State.DEAD)
			if arena_ref != null and arena_ref.has_method("finalize_enemy_suction"):
				arena_ref.call("finalize_enemy_suction", self)
		queue_redraw()
		return

	var timer_done := fsm.tick(delta)
	var player: PlayerSlime = arena_ref.get("player") if arena_ref != null else null
	var dist_to_player: float = 99999.0
	var dir_to_player: Vector2 = Vector2.ZERO
	var eff_detect: float = detect_radius

	if player != null and not player.is_dead:
		var diff := player.global_position - global_position
		dist_to_player = diff.length()
		dir_to_player = diff / maxf(0.001, dist_to_player)
		eff_detect = detect_radius * player.get_effective_visibility_multiplier()

	_update_readability_cue(player, dir_to_player, dist_to_player)

	# Decoy Twin taunt: active SlimeClones lure nearby hunters, strikers, ambushers, and tanks!
	var chase_dist := dist_to_player
	var chase_dir := dir_to_player
	if arena_ref != null and arena_ref.has_method("find_nearest_clone_decoy"):
		var decoy: Node2D = arena_ref.call("find_nearest_clone_decoy", global_position, 210.0)
		if decoy != null and is_instance_valid(decoy):
			var dvec := decoy.global_position - global_position
			chase_dist = dvec.length()
			chase_dir = dvec / maxf(0.001, chase_dist)

	var spd_mult := 1.0 - (slow_factor if freeze_timer > 0.0 else 0.0)
	var cur_spd := move_speed * spd_mult

	match fsm.state:
		EnemyFSM.State.STUNNED:
			velocity = Vector2.ZERO
			if timer_done:
				fsm.transition_to(EnemyFSM.State.WANDER, 1.5)

		EnemyFSM.State.RECOVER:
			is_vulnerable = true
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			if timer_done:
				is_vulnerable = false
				if behavior == "ambush_lunge":
					fsm.transition_to(EnemyFSM.State.AMBUSH_HIDE, 999.0)
				else:
					fsm.transition_to(EnemyFSM.State.WANDER, 1.8)

		EnemyFSM.State.AMBUSH_HIDE:
			velocity = Vector2.ZERO
			if chase_dist <= minf(175.0, eff_detect):
				attack_dir = chase_dir
				fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.66)

		EnemyFSM.State.TELEGRAPH:
			velocity = Vector2.ZERO
			if timer_done:
				if behavior == "zap_striker":
					fsm.transition_to(EnemyFSM.State.RECOVER, 1.35)
				else:
					# Ambush flower or hunter lunge covers full 185px strike range cleanly!
					fsm.transition_to(EnemyFSM.State.ATTACK, 0.42)

		EnemyFSM.State.ATTACK:
			var lunge_spd := 450.0 if behavior == "ambush_lunge" else maxf(345.0, cur_spd * 2.75)
			velocity = attack_dir * (lunge_spd * spd_mult)
			if timer_done:
				fsm.transition_to(EnemyFSM.State.RECOVER, 1.75)

		EnemyFSM.State.IDLE, EnemyFSM.State.WANDER, EnemyFSM.State.FLEE, EnemyFSM.State.CHASE:
			_run_archetype_steering(delta, timer_done, player, dist_to_player, dir_to_player, chase_dist, chase_dir, eff_detect, cur_spd)

	global_position += velocity * delta
	if arena_ref != null and arena_ref.has_method("clamp_world_point"):
		var clamped: Vector2 = arena_ref.call("clamp_world_point", global_position, get_body_radius())
		if clamped != global_position:
			global_position = clamped
			wander_dir = -wander_dir

	queue_redraw()


func _update_readability_cue(player: PlayerSlime, dir_to_p: Vector2, dist: float) -> void:
	_pull_lean = Vector2.ZERO
	if player == null or player.is_dead or dist > 440.0:
		_readability_mode = -1
		return
	var eval := AbsorptionRules.evaluate(player.build_absorption_context(), build_absorption_context())
	if bool(eval["can_absorb"]):
		_readability_mode = 0
		var suction_zone := player.get_radius() + get_body_radius() + 58.0
		if dist < suction_zone and dist > 1.0:
			_pull_lean = dir_to_p * ((1.0 - dist / suction_zone) * 7.5)
	elif str(eval["reason"]) == "armored_shell":
		_readability_mode = 1
	else:
		var eff_r := float(eval.get("effective_ratio", 0.0))
		var req_r := maxf(0.1, float(eval.get("required_ratio", 1.0)))
		if is_vulnerable or fsm.state == EnemyFSM.State.RECOVER or (is_miniboss and hp / maxf(1.0, max_hp) <= 0.45) or eff_r >= req_r * 0.78:
			_readability_mode = 2
		elif contact_damage > 0.0:
			_readability_mode = 3
		else:
			_readability_mode = -1


func _run_archetype_steering(_delta: float, timer_done: bool, player: PlayerSlime, dist: float, dir_to_p: Vector2, chase_dist: float, chase_dir: Vector2, eff_detect: float, spd: float) -> void:
	match behavior:
		"passive_hop":
			if timer_done:
				if fsm.state == EnemyFSM.State.IDLE:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, randf_range(0.7, 1.3))
				else:
					fsm.transition_to(EnemyFSM.State.IDLE, randf_range(0.5, 1.1))
			velocity = (wander_dir * spd) if fsm.state == EnemyFSM.State.WANDER else Vector2.ZERO

		"flee_strong":
			if player != null and dist < eff_detect and player.mass >= mass * 0.90:
				fsm.state = EnemyFSM.State.FLEE
				velocity = (-dir_to_p) * (spd * 1.28)
			else:
				if timer_done or fsm.state == EnemyFSM.State.FLEE:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, randf_range(1.4, 2.6))
				velocity = wander_dir * spd

		"erratic_fast":
			if timer_done:
				wander_dir = Vector2.from_angle(randf() * TAU)
				fsm.transition_to(EnemyFSM.State.WANDER, randf_range(0.55, 1.15))
			var weave := wander_dir.rotated(sin(_anim_phase * 1.8) * 0.75)
			if dist < eff_detect * 0.7:
				weave = (-dir_to_p).rotated(sin(_anim_phase * 2.2) * 0.65)
			velocity = weave * spd

		"armored_tank":
			if chase_dist < eff_detect and not shell_broken_permanently:
				shell_active = true
				velocity = chase_dir * (spd * 0.52)
			else:
				shell_active = false
				if timer_done:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, 2.2)
				velocity = wander_dir * spd

		"hazard_hopper":
			if dist < eff_detect * 0.75:
				velocity = (-dir_to_p).rotated(0.45) * spd
			else:
				if timer_done:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, 1.5)
				velocity = wander_dir * spd
			if _action_cooldown <= 0.0 and arena_ref != null:
				_action_cooldown = 2.9
				arena_ref.call("spawn_enemy_poison_pool", global_position, 40.0, 3.8, contact_damage * 1.10)

		"zap_striker":
			if chase_dist < eff_detect:
				fsm.state = EnemyFSM.State.CHASE
				velocity = chase_dir * spd
				if chase_dist < 132.0 and _action_cooldown <= 0.0 and arena_ref != null:
					_action_cooldown = 4.2
					arena_ref.call("spawn_enemy_telegraph_blast", global_position, 108.0, 0.88, contact_damage * 1.35)
					Audio.play_sfx("attack", 1.25)
					fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.88)
			else:
				if timer_done:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, 1.8)
				velocity = wander_dir * (spd * 0.75)

		"hunter_stalker":
			if chase_dist < eff_detect:
				if (hp < max_hp * 0.22 or (_readability_mode == 0 and chase_dir == dir_to_p)) and not is_miniboss:
					fsm.state = EnemyFSM.State.FLEE
					velocity = (-dir_to_p) * spd
				else:
					fsm.state = EnemyFSM.State.CHASE
					velocity = chase_dir * spd
					if chase_dist < 160.0 and _action_cooldown <= 0.0:
						_action_cooldown = 3.6 if is_miniboss else 4.6
						attack_dir = chase_dir
						fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.62 if is_miniboss else 0.52)
			else:
				if timer_done:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, 2.0)
				velocity = wander_dir * (spd * 0.8)


func can_deal_contact_hit() -> bool:
	if contact_damage <= 0.0 or _contact_hit_cd > 0.0:
		return false
	if stun_timer > 0.0 or fsm.state == EnemyFSM.State.BEING_ABSORBED or fsm.state == EnemyFSM.State.DEAD:
		return false
	return true


func mark_contact_hit_dealt() -> void:
	_contact_hit_cd = 1.08 if is_miniboss else 0.92


func _draw() -> void:
	if fsm.state == EnemyFSM.State.DEAD:
		return
	var r := get_body_radius()
	var bounce := 1.0 + 0.07 * sin(_anim_phase)
	var center := _pull_lean
	var col := color_primary.lerp(Color(1.0, 1.0, 1.0), hurt_flash * 0.7)
	if freeze_timer > 0.0:
		col = col.lerp(Color(0.55, 0.90, 1.0), 0.55)
	elif poison_timer > 0.0:
		col = col.lerp(Color(0.62, 1.0, 0.30), 0.42)

	# Diegetic absorption & danger readability indicator (instant visual clarity without UI clutter!)
	if fsm.state != EnemyFSM.State.BEING_ABSORBED and _readability_mode >= 0:
		if _readability_mode == 0:
			var pulse := 0.40 + 0.22 * sin(_anim_phase * 1.4)
			draw_arc(center, r + 5.5, 0.0, TAU, 28, Color(0.36, 1.0, 0.76, pulse), 2.3)
		elif _readability_mode == 1:
			for seg in range(6):
				var sa := float(seg) * (TAU / 6.0) + _anim_phase * 0.08
				draw_arc(center, r + 5.0, sa, sa + 0.68, 8, Color(0.70, 0.84, 0.98, 0.82), 3.2)
		elif _readability_mode == 2:
			for seg in range(8):
				var sa := float(seg) * (TAU / 8.0) - _anim_phase * 0.18
				draw_arc(center, r + 5.5, sa, sa + 0.42, 6, Color(1.0, 0.84, 0.34, 0.74), 2.4)
		elif _readability_mode == 3:
			var warn_r := r + 6.0 + 1.4 * sin(_anim_phase * 1.7)
			for seg in range(4):
				var ca := float(seg) * (PI * 0.5) + PI * 0.25
				var tip := center + Vector2.from_angle(ca) * (warn_r + 4.5)
				var b1 := center + Vector2.from_angle(ca - 0.18) * warn_r
				var b2 := center + Vector2.from_angle(ca + 0.18) * warn_r
				draw_colored_polygon(PackedVector2Array([b1, tip, b2]), Color(1.0, 0.28, 0.40, 0.78))

	# Ground shadow
	draw_circle(center + Vector2(0, r * 0.42), r * 0.82, Color(0, 0, 0, 0.30))

	# Ambush / Lunge telegraph showing FULL body-width collision corridor & travel distance
	if fsm.state == EnemyFSM.State.TELEGRAPH and behavior != "zap_striker":
		var lunge_len := 188.0 if behavior == "ambush_lunge" else 155.0
		var t_col := Color(0.92, 0.34, 1.0, 0.90) if is_miniboss else Color(1.0, 0.28, 0.36, 0.90)
		var fill_col := Color(t_col.r, t_col.g, t_col.b, 0.20)
		var end_pt := center + attack_dir * lunge_len
		var side_n := attack_dir.orthogonal() * (r * 0.95)
		draw_line(center, end_pt, fill_col, r * 1.9)
		draw_line(center + side_n, end_pt + side_n, t_col, 2.4)
		draw_line(center - side_n, end_pt - side_n, t_col, 2.4)
		draw_arc(end_pt, r * 0.95, 0.0, TAU, 24, t_col, 2.2)
		var chev := end_pt + attack_dir * 8.0
		draw_colored_polygon(PackedVector2Array([chev, end_pt - attack_dir * 10.0 + side_n * 0.55, end_pt - attack_dir * 10.0 - side_n * 0.55]), t_col)
		draw_arc(center, r * 1.32, 0.0, TAU, 24, t_col, 2.5)

	var face := velocity.normalized() if velocity.length() > 8.0 else wander_dir
	var perp := face.orthogonal()

	# Distinct creature silhouettes across ALL 8 creatures + Umbral Alpha Miniboss
	match enemy_id:
		"tiny_mushroom":
			var stem_w := r * 0.68
			var stem_h := r * 0.72
			draw_rect(Rect2(center + Vector2(-stem_w * 0.5, -r * 0.05), Vector2(stem_w, stem_h)), color_secondary)
			draw_circle(center + Vector2(0.0, stem_h * 0.58), stem_w * 0.5, color_secondary)
			var cap_y := -r * 0.18 * bounce
			var cap_pts := PackedVector2Array([
				center + Vector2(-r * 0.98, cap_y + r * 0.26),
				center + Vector2(-r * 0.82, cap_y - r * 0.42),
				center + Vector2(0.0, cap_y - r * 0.78),
				center + Vector2(r * 0.82, cap_y - r * 0.42),
				center + Vector2(r * 0.98, cap_y + r * 0.26)
			])
			draw_colored_polygon(cap_pts, col)
			draw_circle(center + Vector2(-r * 0.36, cap_y - r * 0.16), r * 0.18, color_secondary)
			draw_circle(center + Vector2(r * 0.32, cap_y - r * 0.10), r * 0.15, color_secondary)
			draw_circle(center + Vector2(0.0, cap_y - r * 0.42), r * 0.13, color_secondary)
		"forest_beetle":
			for side: float in [-1.0, 1.0]:
				for leg_i: float in [-0.42, 0.0, 0.42]:
					var swing := sin(_anim_phase * 2.6 + leg_i * 4.0) * 2.4
					var p0: Vector2 = center + face * (r * leg_i) + perp * (side * r * 0.65)
					var p1: Vector2 = p0 + perp * (side * r * 0.42) + face * swing
					draw_line(p0, p1, Color(0.16, 0.11, 0.07), 2.0)
			draw_circle(center, r * 0.90, col)
			draw_line(center - face * (r * 0.80), center + face * (r * 0.45), color_secondary.darkened(0.35), 2.0)
			draw_circle(center + face * (r * 0.66), r * 0.40, col.darkened(0.22))
			draw_line(center + face * (r * 0.84), center + (face + perp * 0.42) * (r * 1.32), color_secondary, 1.8)
			draw_line(center + face * (r * 0.84), center + (face - perp * 0.42) * (r * 1.32), color_secondary, 1.8)
		"firefly":
			var wing_off := sin(_anim_phase * 3.5) * 4.0
			draw_circle(center + Vector2(-r * 0.65, wing_off), r * 0.48, Color(0.85, 1.0, 0.98, 0.55))
			draw_circle(center + Vector2(r * 0.65, wing_off), r * 0.48, Color(0.85, 1.0, 0.98, 0.55))
			draw_circle(center + Vector2(0, r * 0.20), r * 1.05, Color(1.0, 0.95, 0.45, 0.28))
			draw_circle(center, r * 0.76, col)
		"stone_slug":
			draw_circle(center, r * bounce, col)
			if not shell_broken_permanently:
				var plate_a := 0.96 if shell_active else 0.72
				draw_circle(center + Vector2(0, -1.5), r * 0.82, Color(0.42, 0.48, 0.56, plate_a))
				draw_arc(center, r * 1.08, 0.0, TAU, 20, Color(0.86, 0.92, 0.98, plate_a), 3.8 if shell_active else 2.4)
			else:
				draw_line(center + Vector2(-r * 0.45, -r * 0.35), center + Vector2(r * 0.4, r * 0.3), Color(1.0, 0.86, 0.52), 2.5)
		"poison_toad":
			var puff := 1.0 + 0.10 * sin(_anim_phase * 1.5)
			draw_circle(center + Vector2(-r * 0.62, r * 0.34), r * 0.38, col.darkened(0.22))
			draw_circle(center + Vector2(r * 0.62, r * 0.34), r * 0.38, col.darkened(0.22))
			draw_circle(center, r * 0.96 * puff, col)
			draw_circle(center + Vector2(0, r * 0.25), r * 0.48 * puff, Color(color_secondary.r, color_secondary.g, color_secondary.b, 0.78))
			for wart: Vector2 in [Vector2(-r * 0.36, -r * 0.24), Vector2(r * 0.36, -r * 0.20), Vector2(0, -r * 0.46)]:
				draw_circle(center + wart, r * 0.19, color_secondary.darkened(0.15))
		"predator_flower":
			var open_f := 0.58 if fsm.state == EnemyFSM.State.AMBUSH_HIDE else (1.32 if is_vulnerable else 1.12)
			for i in range(6):
				var pa := (TAU / 6.0) * float(i) + _anim_phase * 0.15
				var pdir := Vector2.from_angle(pa)
				var ptang := pdir.orthogonal() * (r * 0.34)
				var ptip := center + pdir * (r * 1.12 * open_f)
				var pbase := center + pdir * (r * 0.28)
				draw_colored_polygon(PackedVector2Array([pbase - ptang, ptip, pbase + ptang]), col)
			draw_circle(center, r * 0.54, Color(0.18, 0.05, 0.10))
			draw_circle(center, r * 0.40, Color(0.42, 1.0, 0.72) if is_vulnerable else color_secondary)
			if not is_vulnerable:
				for t_i in range(5):
					var ta := (TAU / 5.0) * float(t_i) - _anim_phase * 0.2
					draw_line(center + Vector2.from_angle(ta) * (r * 0.52), center + Vector2.from_angle(ta) * (r * 0.28), Color(1.0, 0.95, 0.88), 2.0)
		"electric_beetle":
			draw_circle(center, r * 0.94, col)
			draw_arc(center, r * 0.60, 0.0, TAU, 16, color_secondary, 2.2)
			var h1 := center + (face * 1.28 + perp * 0.38) * r
			var h2 := center + (face * 1.28 - perp * 0.38) * r
			draw_line(center + perp * (r * 0.32), h1, color_secondary, 3.0)
			draw_line(center - perp * (r * 0.32), h2, color_secondary, 3.0)
			if fsm.state == EnemyFSM.State.TELEGRAPH or _action_cooldown < 0.9:
				draw_line(h1, h2, Color(1.0, 0.84, 0.26, 0.98), 2.8)
		"shadow_slime":
			for w in range(4):
				var wa := _anim_phase * 0.8 + float(w) * (TAU / 4.0)
				draw_circle(center + Vector2.from_angle(wa) * (r * 0.70), r * 0.40, Color(col.r, col.g, col.b, 0.52))
			draw_circle(center, r * 0.94 * bounce, col)
			draw_circle(center, r * 0.45, Color(color_secondary.r, color_secondary.g, color_secondary.b, 0.68))
		"umbral_alpha":
			draw_arc(center, r * 1.24, 0.0, TAU, 32, Color(0.76, 0.32, 1.0, 0.44), 3.4)
			for horn: float in [-0.62, 0.0, 0.62]:
				var ha: float = -PI * 0.5 + horn
				var tip := center + Vector2.from_angle(ha) * (r * 1.48)
				var b1 := center + Vector2.from_angle(ha - 0.22) * (r * 0.85)
				var b2 := center + Vector2.from_angle(ha + 0.22) * (r * 0.85)
				draw_colored_polygon(PackedVector2Array([b1, tip, b2]), color_secondary)
			draw_circle(center, r * bounce, col)
			var core_c := Color(0.42, 1.0, 0.74) if is_vulnerable else color_secondary
			draw_circle(center, r * 0.44, core_c)
		_:
			draw_circle(center, r * bounce, col)
			draw_circle(center, r * 0.50, Color(color_secondary.r, color_secondary.g, color_secondary.b, 0.55))

	# Eyes
	var eye_c := Color(1.0, 0.32, 0.48) if (category in ["predator", "miniboss"]) else Color(0.08, 0.10, 0.14)
	draw_circle(center + Vector2(-r * 0.28, -r * 0.10), 2.9, eye_c)
	draw_circle(center + Vector2(r * 0.28, -r * 0.10), 2.9, eye_c)

	# Stun stars
	if stun_timer > 0.0:
		for i in range(3):
			var sa := _anim_phase * 2.0 + float(i) * (TAU / 3.0)
			draw_circle(center + Vector2(cos(sa) * r * 0.8, -r - 8.0 + sin(sa) * 3.0), 3.0, Color(1.0, 0.94, 0.35))

	# HP bar when damaged or miniboss (with 30% execution-gulp notch on miniboss!)
	if hp < max_hp or is_miniboss:
		var bw := maxf(28.0, r * 1.85)
		var bh := 6.0 if is_miniboss else 4.5
		var bp := center + Vector2(-bw * 0.5, -r - (17.0 if is_miniboss else 12.0))
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.08, 0.12, 0.16, 0.85))
		var ratio := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
		var bar_c := Color(0.38, 1.0, 0.74) if _readability_mode == 0 else (Color(0.86, 0.40, 1.0) if is_miniboss else Color(1.0, 0.36, 0.44))
		draw_rect(Rect2(bp, Vector2(bw * ratio, bh)), bar_c)
		if is_miniboss:
			var tick_x := bp.x + bw * 0.22
			draw_line(Vector2(tick_x, bp.y - 1.5), Vector2(tick_x, bp.y + bh + 1.5), Color(0.45, 1.0, 0.82, 0.95), 2.0)
