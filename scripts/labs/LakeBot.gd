class_name LakeBot
extends Node
## Autoplayer for the lake lab: swims from the dewy glade toward the dive line, eats what it can, avoids what it cannot, picks the
## first mutation card, casts the Lunar Nova when a crowd or the guardian is close, dashes when it has the mutation, then dives
## and swims on underwater. At the end it prints one LAKE_BOT line (distance, mass, evolution, kills, hp trouble, ...) so a whole
## run can be checked without a human: it finds crashes, stuck spots and impossible stretches, not balance or feel.
##
## Run:  godot --path . scenes/labs/LakeProto25D.tscn -- --lake-bot=<sim seconds> [--lake-bot-speed=<x>] [--lake-mute]
## The simulation clock is Engine.time_scale-accelerated (default x4). The bot never edits the world; it only steers and presses
## the same inputs a player has.

var lab: Node2D
var active := false
var duration := 240.0
var speed := 4.0
var sim_time := 0.0
var max_progress := 0.0
var dived_at := -1.0
var finished := false
var stuck_time := 0.0
var _last_pos := Vector2.ZERO
var _stuck_check := 0.0
var longest_stuck := 0.0
var draft_choices_taken := 0
var novas := 0
var dashes := 0
var _draft_wait := 0.0
var min_hp_frac := 1.0
var _tick := 0
var samples: Array[String] = []
var _trace := 0


func setup(p_lab: Node2D) -> void:
	lab = p_lab
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lake-bot="):
			duration = float(a.trim_prefix("--lake-bot="))
			active = true
		elif a.begins_with("--lake-bot-speed="):
			speed = float(a.trim_prefix("--lake-bot-speed="))
	if active:
		# GameManager pauses the run when a window loses focus (mobile safety). An unattended run must not freeze when another
		# window is in front, and it already knows how to skip that for tools: it looks for this variable.
		OS.set_environment("QUICK_CAPTURE_OUT", "lake-bot")
		Engine.time_scale = speed
		_last_pos = lab.player.global_position


func _physics_process(delta: float) -> void:
	if not active or finished or lab == null:
		return
	var pl: PlayerSlime = lab.player
	sim_time += delta / maxf(Engine.time_scale, 0.0001) * Engine.time_scale   # delta is already scaled; this keeps sim seconds
	_tick += 1
	var combat: LakeCombat = lab.combat
	var mf: LakeMutations = lab.mutations_fx
	max_progress = maxf(max_progress, combat.progress_at(pl.global_position))
	min_hp_frac = minf(min_hp_frac, pl.hp / pl.max_hp)
	if lab.dive > 0.9 and dived_at < 0.0:
		dived_at = sim_time
	# the card overlay: take the first card after a short pause
	if mf.is_draft_open():
		_draft_wait += delta
		if _draft_wait > 0.4 and not mf._stub.current_draft_choices.is_empty():
			mf._on_card_chosen(String(mf._stub.current_draft_choices[0]["id"]))
			draft_choices_taken += 1
			_draft_wait = 0.0
		return
	_draft_wait = 0.0
	pl.move_input = _decide(pl, combat)
	if _trace > 0:
		_trace -= 1
		samples.append("TRACE pos=(%.1f,%.1f) vel=(%.0f,%.0f) in=(%.2f,%.2f) mass=%.1f r=%.1f dash=%s" % [pl.global_position.x, pl.global_position.y, pl.velocity.x, pl.velocity.y, pl.move_input.x, pl.move_input.y, pl.mass, pl.get_radius(), str(pl.is_dashing)])
	_special_moves(pl, combat, mf)
	# stuck detection: a swimmer that is not moving for seconds while it should be
	_stuck_check += delta
	if _stuck_check >= 1.0:
		if pl.global_position.distance_to(_last_pos) < 12.0 and pl.move_input.length() > 0.3:
			stuck_time += _stuck_check
			longest_stuck = maxf(longest_stuck, stuck_time)
			if stuck_time >= 4.0 and stuck_time < 5.1:
				var near_solid := ""
				for d in lab.solids:
					var n: Node2D = d["node"]
					if is_instance_valid(n) and n.position.distance_to(pl.global_position) < 120.0:
						near_solid += "%s(r%.0f) " % [String(n.name).split("_")[0], float(d["radius"])]
				var nearest_s := ""
				var nd := 1.0e9
				for d2 in lab.solids:
					var n2: Node2D = d2["node"]
					if is_instance_valid(n2):
						var c2: Vector2 = n2.position + Vector2(0.0, -float(d2["radius"]) * 0.6)
						var dd := c2.distance_to(pl.global_position) - float(d2["radius"])
						if dd < nd:
							nd = dd
							nearest_s = "%s r%.0f gap%.0f at(%d,%d)" % [String(n2.name), float(d2["radius"]), dd, int(n2.position.x), int(n2.position.y)]
				var tgt := ""
				for f in lab.food:
					if pl.global_position.distance_to(f["pos"]) < 150.0:
						tgt += "food(%d,%d) " % [int(f["pos"].x), int(f["pos"].y)]
				_trace = 8
				var cols := ""
				for ci in range(pl.get_slide_collision_count()):
					var col := pl.get_slide_collision(ci)
					cols += "%s@%s " % [String(col.get_collider().name) if col.get_collider() != null else "?", str(col.get_position())]
				samples.append("STUCK-STATE paused=%s app_state=%d phys=%s dead=%s mode=%d inv=%.2f" % [str(get_tree().paused), int(App.state), str(pl.is_physics_processing()), str(pl.is_dead), int(pl.process_mode), pl.invulnerable_timer])
				samples.append("STUCK-COLLISIONS count=%d [%s] layer=%d mask=%d" % [pl.get_slide_collision_count(), cols, pl.collision_layer, pl.collision_mask])
				samples.append("STUCK-DETAIL nearest_solid=[%s] food=[%s] bounds=%s" % [nearest_s, tgt, str(lab.play_bounds())])
				samples.append("STUCK at (%d,%d) dive=%.1f vel=%d input=(%.1f,%.1f) near=[%s] boss=%s draft=%s" % [int(pl.global_position.x), int(pl.global_position.y), lab.dive, int(pl.velocity.length()), pl.move_input.x, pl.move_input.y, near_solid, str(lab.combat.boss != null), str(mf.is_draft_open())])
		else:
			stuck_time = 0.0
		_last_pos = pl.global_position
		_stuck_check = 0.0
		if int(sim_time) % 20 == 0:
			samples.append("t=%d y=%d mass=%.0f lvl=%d hp=%.0f en=%d" % [int(sim_time), int(pl.global_position.y), pl.mass, pl.evolution_level, pl.hp, combat.enemies.size()])
	var under_long: bool = dived_at >= 0.0 and sim_time - dived_at > 40.0
	if sim_time >= duration or under_long:
		_finish()


func _decide(pl: PlayerSlime, combat: LakeCombat) -> Vector2:
	var pos := pl.global_position
	var p_ctx := pl.mutations.build_player_absorption_context(pl.mass, pl.is_dashing, pl.mimicry_ambush_ready)
	var steer := Vector2.ZERO
	var best := 1.0e9
	var target := Vector2.ZERO
	var have_target := false
	# food
	for f in lab.food:
		var d := pos.distance_to(f["pos"])
		if d < best and d < 420.0:
			best = d
			target = f["pos"]
			have_target = true
	# edible enemies
	for en in combat.enemies:
		if not is_instance_valid(en) or not en.is_active_combatant():
			continue
		var d := pos.distance_to(en.global_position)
		var verdict := AbsorptionRules.evaluate(p_ctx, en.build_absorption_context())
		if bool(verdict.get("can_absorb", false)):
			if d < best and d < 420.0:
				best = d
				target = en.global_position
				have_target = true
		elif d < 150.0 and en.contact_damage > 0.0:
			steer += (pos - en.global_position).normalized() * (1.0 - d / 150.0) * 2.2
	if combat.boss != null and is_instance_valid(combat.boss):
		var bd := pos.distance_to(combat.boss.global_position)
		if bd < 260.0:
			steer += (pos - combat.boss.global_position).normalized() * (1.0 - bd / 260.0) * 2.5
	var goal_y := LakeProto25D.WORLD_TOP + 200.0 if lab.dive > 0.5 else LakeProto25D.DIVE_Y - 140.0
	var go := Vector2(sin(sim_time * 0.35) * 160.0, goal_y) - pos
	if have_target and best < 380.0 and lab.dive < 0.5:
		steer += (target - pos).normalized() * 1.0
	else:
		steer += go.normalized()
	# the soft solids push back by themselves; a little weave keeps a swimmer from hugging one
	return steer.limit_length(1.0)


func _special_moves(pl: PlayerSlime, combat: LakeCombat, mf: LakeMutations) -> void:
	var pos := pl.global_position
	var near := 0
	for en in combat.enemies:
		if is_instance_valid(en) and en.contact_damage > 0.0 and en.global_position.distance_to(pos) < 380.0:
			near += 1
	var boss_close: bool = combat.boss != null and is_instance_valid(combat.boss) and combat.boss.global_position.distance_to(pos) < 420.0
	if lab.legends.nova_ready and (near >= 4 or boss_close):
		if lab.legends.cast_nova():
			novas += 1
	if pl.mutations.has_mutation("dash") and pl.dash_cooldown <= 0.0 and near >= 2:
		if mf.dash():
			dashes += 1
	# the lab's rare spirits: hunt the one that appears (it is elusive; the bot only tries)
	if not lab.legends.spirit.is_empty() and lab.dive < 0.3:
		var sp: Node2D = lab.legends.spirit["node"]
		if is_instance_valid(sp) and sp.global_position.distance_to(pos) < 300.0:
			pl.move_input = (sp.global_position - pos).normalized()


func _finish() -> void:
	finished = true
	var pl: PlayerSlime = lab.player
	var combat: LakeCombat = lab.combat
	var mut_levels := ""
	for id in LakeMutations.SUPPORTED:
		var lv: int = pl.mutations.get_level(id)
		if lv > 0:
			mut_levels += "%s%d " % [id, lv]
	print("LAKE_BOT sim=%.0fs progress=%.2f y=%d mass=%.1f evo=%d absorbed=%d kills=%d waves=%d boss=%s boss_beaten=%d dived=%s hp_min=%.2f mends=%d drafts=%d mut=[%s] novas=%d dashes=%d catches=%d longest_stuck=%.0fs" % [
		sim_time, max_progress, int(pl.global_position.y), pl.mass, pl.evolution_level, combat.absorbed, combat.kills, combat.waves_spawned,
		str(combat.boss != null), combat.boss_defeated_count, str(dived_at >= 0.0), min_hp_frac, combat.mends, draft_choices_taken,
		mut_levels.strip_edges(), novas, dashes, lab.legends.catches, longest_stuck])
	for line in samples:
		print("LAKE_BOT_SAMPLE ", line)
	Engine.time_scale = 1.0
	lab.quit_cleanly()
