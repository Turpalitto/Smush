class_name AncientGuardianBoss
extends CharacterBody2D
## Full 3-Phase Boss: Древний страж леса (Ancient Forest Guardian).
## Phase 1 (100%-66% HP): Pursuit + Telegraphed Root Shockwave Slam + Vulnerable Core window.
## Phase 2 (66%-33% HP): Forest Minion Summon + Cross-Root Eruption Lanes.
## Phase 3 (33%-0% HP): Awakened Core Overdrive — Telegraphed Living Root Charge + Spore Ring.

enum ActionState {
	PURSUIT,
	TELEGRAPH_SLAM,
	TELEGRAPH_CROSS,
	TELEGRAPH_CHARGE,
	CHARGING,
	VULNERABLE_RECOVER,
	DEFEATED
}

var boss_id: String = "ancient_guardian"
var mass: float = 85.0
var max_hp: float = 920.0
var hp: float = 920.0
var phase: int = 1
var move_speed: float = 116.0
var armor: float = 0.28
var contact_damage: float = 24.0

var action_state: ActionState = ActionState.PURSUIT
var _state_timer: float = 1.8
var _charge_dir: Vector2 = Vector2.DOWN
var _summon_cooldown: float = 0.0
var _contact_cd: float = 0.0
var freeze_timer: float = 0.0
var slow_factor: float = 0.0
var hurt_flash: float = 0.0
var _anim_time: float = 0.0
var arena_ref: Node = null


func setup_boss(cfg: Dictionary, spawn_pos: Vector2, p_arena: Node) -> void:
	arena_ref = p_arena
	global_position = spawn_pos
	boss_id = str(cfg.get("id", "ancient_guardian"))
	mass = float(cfg.get("base_mass", 85.0))
	max_hp = float(cfg.get("hp", 920.0))
	hp = max_hp
	move_speed = float(cfg.get("move_speed", 116.0))
	armor = float(cfg.get("armor", 0.28))
	contact_damage = float(cfg.get("contact_damage", 24.0))
	phase = 1
	action_state = ActionState.PURSUIT
	_state_timer = 2.0
	_summon_cooldown = 1.5
	Events.boss_spawned.emit(boss_id, max_hp)
	Events.boss_updated.emit(hp, max_hp, phase)
	Audio.play_sfx("boss_warning", 1.0)


func get_body_radius() -> float:
	return 52.0


func is_vulnerable() -> bool:
	return action_state == ActionState.VULNERABLE_RECOVER


func build_absorption_context() -> Dictionary:
	return {
		"category": "boss",
		"mass": mass,
		"armor": 0.0 if is_vulnerable() else armor,
		"shell_active": false,
		"is_frozen": freeze_timer > 0.0,
		"is_stunned": false,
		"is_poisoned": false,
		"is_vulnerable": is_vulnerable(),
		"hp_ratio": clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	}


func apply_freeze(slow_amt: float, dur: float) -> void:
	# Boss chill slow capped at 35% per mutation balance spec
	freeze_timer = maxf(freeze_timer, dur * 0.75)
	slow_factor = minf(0.35, slow_amt)


func take_damage(amount: float, armor_pierce: float = 0.0) -> bool:
	if action_state == ActionState.DEFEATED:
		return false
	var eff_armor := 0.0 if is_vulnerable() else maxf(0.0, armor - armor_pierce)
	var vul_mult := 1.45 if is_vulnerable() else 1.0
	var dmg := amount * (1.0 - eff_armor) * vul_mult
	hp = maxf(0.0, hp - dmg)
	hurt_flash = 0.85

	var new_phase := 1
	var ratio := hp / maxf(1.0, max_hp)
	if ratio <= 0.33:
		new_phase = 3
	elif ratio <= 0.66:
		new_phase = 2

	if new_phase != phase:
		phase = new_phase
		Audio.play_sfx("boss_warning", 1.0 + float(phase - 1) * 0.12)
		if phase == 2 and arena_ref != null and arena_ref.has_method("spawn_boss_minions"):
			arena_ref.call("spawn_boss_minions", global_position, 4)

	Events.boss_updated.emit(hp, max_hp, phase)

	if hp <= 0.0:
		_trigger_defeat()
		return true
	return false


func _trigger_defeat() -> void:
	if action_state == ActionState.DEFEATED:
		return
	action_state = ActionState.DEFEATED
	hp = 0.0
	Events.boss_updated.emit(0.0, max_hp, phase)
	Events.boss_defeated.emit(boss_id)
	if arena_ref != null and arena_ref.has_method("on_boss_defeated"):
		arena_ref.call("on_boss_defeated", self)


func can_deal_contact_hit() -> bool:
	return action_state != ActionState.DEFEATED and _contact_cd <= 0.0


func mark_contact_hit_dealt() -> void:
	_contact_cd = 0.65


func _physics_process(delta: float) -> void:
	if action_state == ActionState.DEFEATED:
		return

	_anim_time += delta
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 3.5)
	if _contact_cd > 0.0:
		_contact_cd = maxf(0.0, _contact_cd - delta)
	if _summon_cooldown > 0.0:
		_summon_cooldown = maxf(0.0, _summon_cooldown - delta)
	if freeze_timer > 0.0:
		freeze_timer = maxf(0.0, freeze_timer - delta)
		if freeze_timer <= 0.0:
			slow_factor = 0.0

	var player: PlayerSlime = arena_ref.get("player") if arena_ref != null else null
	var to_player := Vector2.DOWN
	var dist := 300.0
	if player != null and not player.is_dead:
		var diff := player.global_position - global_position
		dist = diff.length()
		to_player = diff / maxf(0.001, dist)

	var spd := move_speed * (1.0 + float(phase - 1) * 0.14) * (1.0 - slow_factor)
	_state_timer -= delta

	match action_state:
		ActionState.PURSUIT:
			velocity = to_player * spd
			if phase >= 2 and _summon_cooldown <= 0.0 and arena_ref != null:
				_summon_cooldown = 11.5
				arena_ref.call("spawn_boss_minions", global_position, 3)

			if _state_timer <= 0.0:
				_choose_next_special(to_player, dist)

		ActionState.TELEGRAPH_SLAM:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.VULNERABLE_RECOVER
				_state_timer = 1.55

		ActionState.TELEGRAPH_CROSS:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.VULNERABLE_RECOVER
				_state_timer = 1.45

		ActionState.TELEGRAPH_CHARGE:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.CHARGING
				_state_timer = 0.55
				Audio.play_sfx("attack", 0.78)

		ActionState.CHARGING:
			velocity = _charge_dir * (spd * 3.1)
			if _state_timer <= 0.0:
				action_state = ActionState.VULNERABLE_RECOVER
				_state_timer = 1.70

		ActionState.VULNERABLE_RECOVER:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.PURSUIT
				_state_timer = maxf(1.6, 2.8 - float(phase - 1) * 0.45)

	global_position += velocity * delta
	if arena_ref != null and arena_ref.has_method("clamp_world_point"):
		global_position = arena_ref.call("clamp_world_point", global_position, get_body_radius())

	queue_redraw()


func _choose_next_special(to_player: Vector2, _dist: float) -> void:
	if arena_ref == null:
		_state_timer = 2.0
		return

	if phase == 1:
		action_state = ActionState.TELEGRAPH_SLAM
		_state_timer = 1.05
		arena_ref.call("spawn_boss_telegraph_slam", global_position + to_player * 55.0, 140.0, 1.0, contact_damage * 1.35)
	elif phase == 2:
		action_state = ActionState.TELEGRAPH_CROSS
		_state_timer = 1.05
		for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			arena_ref.call("spawn_boss_telegraph_slam", global_position + dir * 135.0, 82.0, 1.0, contact_damage * 1.2)
	else:
		# Phase 3 alternates between Living Root Charge and Ring Nova
		_charge_dir = to_player
		action_state = ActionState.TELEGRAPH_CHARGE
		_state_timer = 0.88
		for i in range(6):
			var ang := (TAU / 6.0) * float(i)
			arena_ref.call("spawn_boss_telegraph_slam", global_position + Vector2.from_angle(ang) * 155.0, 68.0, 0.88, contact_damage * 1.15)


func _draw() -> void:
	var r := get_body_radius()
	draw_circle(Vector2(0, 20), r * 0.95, Color(0, 0, 0, 0.38))

	# Charge corridor telegraph in Phase 3
	if action_state == ActionState.TELEGRAPH_CHARGE:
		var end_p := _charge_dir * 340.0
		draw_line(Vector2.ZERO, end_p, Color(1.0, 0.22, 0.34, 0.42), r * 1.35)
		draw_line(Vector2.ZERO, end_p, Color(1.0, 0.55, 0.35, 0.92), 4.0)

	# Crown of ancient roots & crystals
	var root_cnt: int = 8
	for i in range(root_cnt):
		var a := (TAU / float(root_cnt)) * float(i) + _anim_time * (0.4 + float(phase) * 0.25)
		var p1 := Vector2.from_angle(a) * (r * 0.82)
		var p2 := Vector2.from_angle(a) * (r * 1.22)
		var tang := Vector2.from_angle(a).orthogonal() * 11.0
		var rc := Color(0.28, 0.65, 0.44) if phase < 3 else Color(0.88, 0.35, 0.42)
		draw_colored_polygon(PackedVector2Array([p1 - tang, p2, p1 + tang]), rc)

	var bark_col := Color(0.18, 0.48, 0.34)
	if phase == 2:
		bark_col = Color(0.24, 0.52, 0.56)
	elif phase == 3:
		bark_col = Color(0.45, 0.22, 0.34)
	bark_col = bark_col.lerp(Color.WHITE, hurt_flash * 0.65)
	draw_circle(Vector2.ZERO, r, bark_col)

	# Glowing Ancient Heart Core (bright gold-emerald when exposed/vulnerable!)
	var core_r := r * (0.50 if is_vulnerable() else 0.34)
	var core_col := Color(0.55, 1.0, 0.72) if is_vulnerable() else (Color(1.0, 0.82, 0.35) if phase < 3 else Color(1.0, 0.36, 0.42))
	draw_circle(Vector2.ZERO, core_r * 1.25, Color(core_col.r, core_col.g, core_col.b, 0.32))
	draw_circle(Vector2.ZERO, core_r, core_col)

	# Ancient glowing eyes
	draw_circle(Vector2(-16, -10), 5.5, Color(1.0, 0.95, 0.55))
	draw_circle(Vector2(16, -10), 5.5, Color(1.0, 0.95, 0.55))
