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
var _anim_phase: float = 0.0
var _absorb_target: Node2D = null
var _absorb_elapsed: float = 0.0
var arena_ref: Node = null


func setup_from_config(cfg: Dictionary, spawn_pos: Vector2, p_arena: Node, difficulty_scale: float = 1.0) -> void:
	arena_ref = p_arena
	global_position = spawn_pos
	scale = Vector2.ONE
	enemy_id = str(cfg.get("id", "tiny_mushroom"))
	category = str(cfg.get("category", "flora"))
	behavior = str(cfg.get("behavior", "passive_hop"))
	is_miniboss = (category == "miniboss")
	if is_miniboss:
		behavior = "hunter_stalker"

	mass = float(cfg.get("base_mass", 8.0))
	max_hp = float(cfg.get("hp", 20.0)) * difficulty_scale
	hp = max_hp
	move_speed = float(cfg.get("move_speed", 70.0))
	armor = float(cfg.get("armor", 0.0))
	contact_damage = float(cfg.get("contact_damage", 5.0)) * lerpf(1.0, difficulty_scale, 0.5)
	detect_radius = float(cfg.get("detect_radius", 180.0))
	xp_reward = float(cfg.get("xp_reward", 12.0))
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
	_absorb_target = null
	_absorb_elapsed = 0.0
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

	if fsm.state == EnemyFSM.State.DEAD:
		return

	if fsm.state == EnemyFSM.State.BEING_ABSORBED:
		_absorb_elapsed += delta
		if _absorb_target != null and is_instance_valid(_absorb_target):
			global_position = global_position.lerp(_absorb_target.global_position, clampf(delta * 18.0, 0.0, 1.0))
			scale = Vector2.ONE * clampf(1.0 - _absorb_elapsed * 4.8, 0.15, 1.0)
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
			if dist_to_player <= eff_detect:
				attack_dir = dir_to_player
				fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.62)

		EnemyFSM.State.TELEGRAPH:
			velocity = Vector2.ZERO
			if timer_done:
				if behavior == "zap_striker":
					fsm.transition_to(EnemyFSM.State.RECOVER, 1.35)
				else:
					# Ambush flower or hunter lunge
					fsm.transition_to(EnemyFSM.State.ATTACK, 0.34)

		EnemyFSM.State.ATTACK:
			velocity = attack_dir * maxf(290.0, cur_spd * 2.6)
			if timer_done:
				fsm.transition_to(EnemyFSM.State.RECOVER, 1.55)

		EnemyFSM.State.IDLE, EnemyFSM.State.WANDER, EnemyFSM.State.FLEE, EnemyFSM.State.CHASE:
			_run_archetype_steering(delta, timer_done, player, dist_to_player, dir_to_player, eff_detect, cur_spd)

	global_position += velocity * delta
	if arena_ref != null and arena_ref.has_method("clamp_world_point"):
		var clamped: Vector2 = arena_ref.call("clamp_world_point", global_position, get_body_radius())
		if clamped != global_position:
			global_position = clamped
			wander_dir = -wander_dir

	queue_redraw()


func _run_archetype_steering(_delta: float, timer_done: bool, player: PlayerSlime, dist: float, dir_to_p: Vector2, eff_detect: float, spd: float) -> void:
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
			if dist < eff_detect and not shell_broken_permanently:
				shell_active = true
				velocity = dir_to_p * (spd * 0.45)
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
				_action_cooldown = 2.6
				arena_ref.call("spawn_enemy_poison_pool", global_position, 40.0, 3.8, contact_damage * 1.15)

		"zap_striker":
			if dist < eff_detect:
				fsm.state = EnemyFSM.State.CHASE
				velocity = dir_to_p * spd
				if dist < 135.0 and _action_cooldown <= 0.0 and arena_ref != null:
					_action_cooldown = 4.2
					arena_ref.call("spawn_enemy_telegraph_blast", global_position, 108.0, 0.85, contact_damage * 1.45)
					Audio.play_sfx("attack", 1.25)
					fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.85)
			else:
				if timer_done:
					wander_dir = Vector2.from_angle(randf() * TAU)
					fsm.transition_to(EnemyFSM.State.WANDER, 1.8)
				velocity = wander_dir * (spd * 0.75)

		"hunter_stalker":
			if player != null and dist < eff_detect:
				if hp < max_hp * 0.22 and not is_miniboss:
					fsm.state = EnemyFSM.State.FLEE
					velocity = (-dir_to_p) * spd
				else:
					fsm.state = EnemyFSM.State.CHASE
					velocity = dir_to_p * spd
					if dist < 145.0 and _action_cooldown <= 0.0:
						_action_cooldown = 3.4 if is_miniboss else 4.5
						attack_dir = dir_to_p
						fsm.transition_to(EnemyFSM.State.TELEGRAPH, 0.48)
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
	_contact_hit_cd = 0.65


func _draw() -> void:
	var r := get_body_radius()
	var bounce := 1.0 + 0.07 * sin(_anim_phase)
	var col := color_primary.lerp(Color(1.0, 1.0, 1.0), hurt_flash * 0.7)
	if freeze_timer > 0.0:
		col = col.lerp(Color(0.55, 0.90, 1.0), 0.55)
	elif poison_timer > 0.0:
		col = col.lerp(Color(0.62, 1.0, 0.30), 0.42)

	# Ground shadow
	draw_circle(Vector2(0, r * 0.42), r * 0.82, Color(0, 0, 0, 0.30))

	# Ambush / Lunge telegraph warning line & ring
	if fsm.state == EnemyFSM.State.TELEGRAPH and behavior != "zap_striker":
		draw_line(Vector2.ZERO, attack_dir * 120.0, Color(1.0, 0.25, 0.35, 0.80), 4.0)
		draw_arc(Vector2.ZERO, r * 1.45, 0.0, TAU, 24, Color(1.0, 0.28, 0.38, 0.90), 2.5)

	# Creature-specific silhouette
	match enemy_id:
		"tiny_mushroom":
			draw_circle(Vector2(0, r * 0.28), r * 0.46, color_secondary)
			draw_circle(Vector2(0, -r * 0.14 * bounce), r * 0.86, col)
			draw_circle(Vector2(-r * 0.32, -r * 0.26), r * 0.18, color_secondary)
			draw_circle(Vector2(r * 0.28, -r * 0.20), r * 0.15, color_secondary)
		"firefly":
			var wing_off := sin(_anim_phase * 3.5) * 4.0
			draw_circle(Vector2(-r * 0.65, wing_off), r * 0.48, Color(0.85, 1.0, 0.98, 0.55))
			draw_circle(Vector2(r * 0.65, wing_off), r * 0.48, Color(0.85, 1.0, 0.98, 0.55))
			draw_circle(Vector2.ZERO, r * 0.75, col)
			draw_circle(Vector2(0, r * 0.25), r * 0.95, Color(1.0, 0.95, 0.45, 0.28))
		"stone_slug":
			draw_circle(Vector2.ZERO, r * bounce, col)
			if shell_active and not shell_broken_permanently:
				draw_arc(Vector2.ZERO, r * 1.12, 0.0, TAU, 20, Color(0.86, 0.92, 0.98, 0.95), 4.2)
		"predator_flower":
			var open_f := 0.55 if fsm.state == EnemyFSM.State.AMBUSH_HIDE else 1.15
			for i in range(5):
				var pa := (TAU / 5.0) * float(i) + _anim_phase * 0.15
				draw_circle(Vector2.from_angle(pa) * (r * 0.65 * open_f), r * 0.45, col)
			draw_circle(Vector2.ZERO, r * 0.46, color_secondary if is_vulnerable else Color(0.32, 0.08, 0.18))
		_:
			draw_circle(Vector2.ZERO, r * bounce, col)
			draw_circle(Vector2.ZERO, r * 0.50, Color(color_secondary.r, color_secondary.g, color_secondary.b, 0.55))

	# Eyes
	draw_circle(Vector2(-r * 0.28, -r * 0.10), 2.8, Color(0.08, 0.10, 0.14))
	draw_circle(Vector2(r * 0.28, -r * 0.10), 2.8, Color(0.08, 0.10, 0.14))

	# Stun stars
	if stun_timer > 0.0:
		for i in range(3):
			var sa := _anim_phase * 2.0 + float(i) * (TAU / 3.0)
			draw_circle(Vector2(cos(sa) * r * 0.8, -r - 8.0 + sin(sa) * 3.0), 3.0, Color(1.0, 0.94, 0.35))

	# HP bar when damaged or miniboss
	if hp < max_hp or is_miniboss:
		var bw := r * 1.8
		var by := -r - 12.0
		draw_rect(Rect2(-bw * 0.5, by, bw, 4.5), Color(0.08, 0.12, 0.16, 0.85))
		draw_rect(Rect2(-bw * 0.5, by, bw * clampf(hp / maxf(1.0, max_hp), 0.0, 1.0), 4.5), Color(1.0, 0.36, 0.44))
