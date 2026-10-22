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
var max_hp: float = 3750.0
var hp: float = 3750.0
var phase: int = 1
var move_speed: float = 98.0
var armor: float = 0.34
var contact_damage: float = 20.0

var action_state: ActionState = ActionState.PURSUIT
var _state_timer: float = 2.2
var _charge_dir: Vector2 = Vector2.DOWN
var _cross_diagonal_toggle: bool = false
var _summon_cooldown: float = 0.0
var _contact_cd: float = 0.0
var phase_shield_timer: float = 0.0
var freeze_timer: float = 0.0
var slow_factor: float = 0.0
var hurt_flash: float = 0.0
var _anim_time: float = 0.0
var arena_ref: Node = null


func setup_boss(cfg: Dictionary, spawn_pos: Vector2, p_arena: Node, hp_mult: float = 1.0, damage_mult: float = 1.0) -> void:
	arena_ref = p_arena
	global_position = spawn_pos
	boss_id = str(cfg.get("id", "ancient_guardian"))
	mass = float(cfg.get("base_mass", 85.0))
	max_hp = float(cfg.get("hp", 3750.0)) * maxf(0.1, hp_mult)
	hp = max_hp
	move_speed = float(cfg.get("move_speed", 98.0))
	armor = float(cfg.get("armor", 0.34))
	contact_damage = float(cfg.get("contact_damage", 20.0)) * maxf(0.1, damage_mult)
	phase = 1
	action_state = ActionState.PURSUIT
	_state_timer = 2.4
	_cross_diagonal_toggle = false
	_summon_cooldown = 2.0
	phase_shield_timer = 0.0
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
	var vul_mult := 1.48 if is_vulnerable() else 1.0
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
		if hp > 0.0:
			action_state = ActionState.PURSUIT
			_state_timer = 1.65
		Audio.play_sfx("boss_warning", 1.0 + float(phase - 1) * 0.12)
		if arena_ref != null:
			if phase == 2 and arena_ref.has_method("spawn_boss_minions"):
				arena_ref.call("spawn_boss_minions", global_position, 3)
			if arena_ref.has_method("spawn_boss_dew_spores"):
				arena_ref.call("spawn_boss_dew_spores", global_position, 3)

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
	# Exposed vulnerable core & pre-attack windups are safe punish windows for melee slimes!
	if action_state in [ActionState.DEFEATED, ActionState.VULNERABLE_RECOVER, ActionState.TELEGRAPH_SLAM, ActionState.TELEGRAPH_CROSS, ActionState.TELEGRAPH_CHARGE]:
		return false
	return _contact_cd <= 0.0


func mark_contact_hit_dealt() -> void:
	_contact_cd = 1.15


func get_active_contact_damage() -> float:
	# Full battering-ram damage during CHARGING; lighter bark-thorn graze when lumbering in PURSUIT!
	return contact_damage * 1.15 if action_state == ActionState.CHARGING else contact_damage * 0.55


func _physics_process(delta: float) -> void:
	if action_state == ActionState.DEFEATED:
		return

	_anim_time += delta
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 3.5)
	if phase_shield_timer > 0.0:
		phase_shield_timer = maxf(0.0, phase_shield_timer - delta)
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
				_state_timer = 1.90
				if arena_ref != null and arena_ref.has_method("spawn_boss_dew_spores"):
					arena_ref.call("spawn_boss_dew_spores", global_position, 2)

		ActionState.TELEGRAPH_CROSS:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.VULNERABLE_RECOVER
				_state_timer = 1.85
				if arena_ref != null and arena_ref.has_method("spawn_boss_dew_spores"):
					arena_ref.call("spawn_boss_dew_spores", global_position, 2)

		ActionState.TELEGRAPH_CHARGE:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.CHARGING
				_state_timer = 0.50
				Audio.play_sfx("attack", 0.78)

		ActionState.CHARGING:
			velocity = _charge_dir * (spd * 2.95)
			if _state_timer <= 0.0:
				action_state = ActionState.VULNERABLE_RECOVER
				_state_timer = 2.10
				if arena_ref != null and arena_ref.has_method("spawn_boss_dew_spores"):
					arena_ref.call("spawn_boss_dew_spores", global_position, 2)

		ActionState.VULNERABLE_RECOVER:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				action_state = ActionState.PURSUIT
				_state_timer = maxf(1.85, 2.85 - float(phase - 1) * 0.42)

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
		_state_timer = 1.30
		arena_ref.call("spawn_boss_telegraph_slam", global_position + to_player * 38.0, 126.0, 1.26, contact_damage * 1.25)
	elif phase == 2:
		action_state = ActionState.TELEGRAPH_CROSS
		_state_timer = 1.24
		var base_ang := (PI * 0.25) if _cross_diagonal_toggle else 0.0
		_cross_diagonal_toggle = not _cross_diagonal_toggle
		for i in range(4):
			var dir := Vector2.from_angle(base_ang + float(i) * (PI * 0.5))
			arena_ref.call("spawn_boss_telegraph_slam", global_position + dir * 130.0, 74.0, 1.20, contact_damage * 1.15)
			arena_ref.call("spawn_boss_telegraph_slam", global_position + dir * 235.0, 66.0, 1.20, contact_damage * 1.10)
	else:
		# Phase 3: readable Living Root Charge corridor + outer ring pods leaving flank dodge pockets!
		_charge_dir = to_player
		action_state = ActionState.TELEGRAPH_CHARGE
		_state_timer = 1.12
		for i in range(6):
			var ang := (TAU / 6.0) * float(i) + 0.52
			arena_ref.call("spawn_boss_telegraph_slam", global_position + Vector2.from_angle(ang) * 195.0, 64.0, 1.10, contact_damage * 1.12)


func _draw() -> void:
	var r := get_body_radius()
	draw_circle(Vector2(0, 20), r * 0.95, Color(0, 0, 0, 0.38))

	# Diegetic opportunity ring when Vulnerable OR ready for <=6% HP Core Execution!
	if hp / maxf(1.0, max_hp) <= 0.06:
		var exec_p := 0.55 + 0.35 * sin(_anim_time * 8.0)
		draw_arc(Vector2.ZERO, r + 14.0, 0.0, TAU, 36, Color(0.36, 1.0, 0.78, exec_p), 4.0)
	elif is_vulnerable():
		var vul_p := 0.45 + 0.25 * sin(_anim_time * 6.0)
		draw_arc(Vector2.ZERO, r + 10.0, 0.0, TAU, 36, Color(0.45, 1.0, 0.72, vul_p), 3.2)

	# Charge corridor telegraph in Phase 3 (full collision width + side rails + arrowhead)
	if action_state == ActionState.TELEGRAPH_CHARGE:
		var end_p := _charge_dir * 320.0
		var side_c := _charge_dir.orthogonal() * (r * 0.92)
		draw_line(Vector2.ZERO, end_p, Color(1.0, 0.18, 0.32, 0.28), r * 1.84)
		draw_line(side_c, end_p + side_c, Color(1.0, 0.46, 0.36, 0.94), 3.0)
		draw_line(-side_c, end_p - side_c, Color(1.0, 0.46, 0.36, 0.94), 3.0)
		draw_colored_polygon(PackedVector2Array([end_p + _charge_dir * 16.0, end_p - _charge_dir * 12.0 + side_c * 0.55, end_p - _charge_dir * 12.0 - side_c * 0.55]), Color(1.0, 0.55, 0.35, 0.92))

	# Gnarled ancient root buttresses & phase crystal thorns
	var root_cnt: int = 8
	for i in range(root_cnt):
		var a := (TAU / float(root_cnt)) * float(i) + _anim_time * (0.35 + float(phase) * 0.22)
		var dir_r := Vector2.from_angle(a)
		var p1 := dir_r * (r * 0.80)
		var p2 := dir_r * (r * 1.28)
		var tang := dir_r.orthogonal() * 12.5
		var rc := Color(0.24, 0.56, 0.38) if phase == 1 else (Color(0.28, 0.64, 0.62) if phase == 2 else Color(0.86, 0.28, 0.42))
		draw_colored_polygon(PackedVector2Array([p1 - tang, p2, p1 + tang]), rc)
		draw_line(p1, p2, rc.lightened(0.28), 2.0)

	# Layered ancient bark carapace + mossy shoulder plates
	var bark_outer := Color(0.14, 0.34, 0.25)
	var bark_inner := Color(0.22, 0.50, 0.36)
	var vein_col := Color(0.52, 0.98, 0.74, 0.68)
	if phase == 2:
		bark_outer = Color(0.16, 0.36, 0.42)
		bark_inner = Color(0.24, 0.52, 0.58)
		vein_col = Color(1.0, 0.82, 0.36, 0.78)
	elif phase == 3:
		bark_outer = Color(0.32, 0.14, 0.24)
		bark_inner = Color(0.48, 0.22, 0.36)
		vein_col = Color(1.0, 0.36, 0.52, 0.86)
	bark_outer = bark_outer.lerp(Color.WHITE, hurt_flash * 0.65)
	bark_inner = bark_inner.lerp(Color.WHITE, hurt_flash * 0.65)
	draw_circle(Vector2.ZERO, r, bark_outer)
	draw_circle(Vector2(0.0, -3.0), r * 0.84, bark_inner)
	draw_arc(Vector2.ZERO, r * 0.92, 0.0, TAU, 32, vein_col, 2.6)

	# Upper elder-antler crown
	for side_h: float in [-1.0, 1.0]:
		var h_base := Vector2(side_h * r * 0.46, -r * 0.72)
		var h_mid := Vector2(side_h * r * 0.74, -r * 1.12)
		var h_tip := Vector2(side_h * r * 0.54, -r * 1.38)
		draw_polyline(PackedVector2Array([h_base, h_mid, h_tip]), bark_outer.darkened(0.18), 7.0)
		draw_line(h_mid, h_mid + Vector2(side_h * 11.0, -9.0), bark_outer.darkened(0.18), 4.5)

	# Glowing Ancient Heart Core positioned on lower chest so eyes stay high-contrast above it!
	var core_pos := Vector2(0.0, r * 0.18)
	var core_r := r * (0.42 if is_vulnerable() else 0.26)
	var core_col := Color(0.45, 1.0, 0.74) if is_vulnerable() else (Color(1.0, 0.82, 0.35) if phase < 3 else Color(1.0, 0.34, 0.46))
	draw_circle(core_pos, core_r * 1.32, Color(core_col.r, core_col.g, core_col.b, 0.32))
	draw_circle(core_pos, core_r, core_col)
	draw_circle(core_pos + Vector2(-core_r * 0.24, -core_r * 0.24), core_r * 0.32, Color(1.0, 1.0, 0.92, 0.85))

	# High-contrast fierce dark-socket eyes above the heart core
	for side_e: float in [-1.0, 1.0]:
		var ep := Vector2(side_e * r * 0.32, -r * 0.24)
		draw_circle(ep, 8.2, Color(0.04, 0.08, 0.10, 0.94))
		var iris_c := Color(0.55, 1.0, 0.84) if is_vulnerable() else (Color(1.0, 0.92, 0.38) if phase < 3 else Color(1.0, 0.38, 0.52))
		draw_circle(ep, 5.2, iris_c)
		if not is_vulnerable():
			draw_line(ep + Vector2(-side_e * 8.0, -2.0), ep + Vector2(side_e * 8.0, -7.5), bark_outer.darkened(0.42), 3.4)
