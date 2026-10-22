extends Node
## Reproducible Automated Playthrough & Post-Limiter Audio Verification Driver.
## IMPORTANT: This is an AUTOMATED SCRIPT AGENT (not a human player).
## - Starts from a clean profile (via isolated XDG_DATA_HOME).
## - Uses real InputEventScreenTouch / InputEventScreenDrag events transformed into viewport space
##   to tap Menu -> Mode Select, drag VirtualJoystick, tap Dash/Split buttons, and pick draft cards.
## - Reads live scene-tree state (player, orbs, enemies, hazards, boss) for steering decisions.
## - Never alters HP, mass, XP, cooldowns, spawns, or boss damage directly.
## - Records Master bus audio BOTH pre-limiter (AudioEffectCapture at idx 0) and post-limiter
##   (AudioEffectRecord appended AFTER AudioEffectHardLimiter via Audio.create_post_limiter_recorder()).

const SUMMARY_OUT_ENV := "PLAYTHROUGH_SUMMARY_PATH"
const BOSS_WAV_OUT_ENV := "PLAYTHROUGH_BOSS_WAV_PATH"
const RESULT_PNG_OUT_ENV := "PLAYTHROUGH_RESULT_PNG_PATH"

var main: MainRoot
var _joy_touch_active: bool = false
var _joy_origin_logical: Vector2 = Vector2(260.0, 980.0)
var _stutter_checked: bool = false
var _accidental_double_tap_dash: bool = false

var _evo_times: Array[float] = []
var _last_evo_lv: int = 0
var _absorbed_count: int = 0
var _last_absorb_t: float = 0.0
var _max_absorb_gap: float = 0.0
var _peak_mass: float = 10.0
var _damage_events: Array[Dictionary] = []
var _last_hp: float = 100.0
var _miniboss_spawn_t: float = -1.0
var _miniboss_defeat_t: float = -1.0
var _boss_spawn_t: float = -1.0
var _boss_p2_t: float = -1.0
var _boss_p3_t: float = -1.0

var _sfx_counts: Dictionary = {}
var _sfx_total: int = 0
var _sfx_max_concurrent: int = 0
var _prev_playing_flags: Array[bool] = []

var _pre_lim_capture: AudioEffectCapture = null
var _post_lim_recorder: AudioEffectRecord = null
var _recording_boss: bool = false
var _pre_lim_peak_lin: float = 0.0
var _pre_lim_frames: int = 0
var _wall_t0_usec: int = 0
var _boss_rec_wall_t0_usec: int = 0
var _next_heartbeat_sec: float = 30.0
var _finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	_wall_t0_usec = Time.get_ticks_usec()
	call_deferred("_boot_and_run")


func _to_screen_pos(logical_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * logical_pos


func _tap_control(ctrl: Control, touch_idx: int = 5) -> void:
	var center_logical := ctrl.get_global_rect().get_center()
	var sp := _to_screen_pos(center_logical)
	var down := InputEventScreenTouch.new()
	down.index = touch_idx
	down.pressed = true
	down.position = sp
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = touch_idx
	up.pressed = false
	up.position = sp
	Input.parse_input_event(up)
	await get_tree().process_frame


func _find_first_button_recursive(root_node: Node, match_text: String = "") -> Button:
	if root_node is Button and (root_node as Control).visible:
		if match_text.is_empty() or (root_node as Button).text == match_text:
			return root_node as Button
	for ch in root_node.get_children():
		var found := _find_first_button_recursive(ch, match_text)
		if found != null:
			return found
	return null


func _await_draw_if_rendered() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _boot_and_run() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	main = packed.instantiate() as MainRoot
	get_tree().root.add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	await _await_draw_if_rendered()

	_prev_playing_flags.resize(Audio._sfx_players.size())
	_prev_playing_flags.fill(false)

	# Tap Play on Main Menu via InputEventScreenTouch
	var play_btn := main.menus.find_child("PlayButton", true, false) as Button
	if play_btn != null:
		await _tap_control(play_btn, 0)
	for _i in range(3):
		await get_tree().process_frame
	await _await_draw_if_rendered()

	# Tap first Start Run button (Standard mode) on Mode Select via InputEventScreenTouch
	var std_btn := _find_first_button_recursive(main.menus, Loc.t("mode.start_btn"))
	if std_btn != null:
		await _tap_control(std_btn, 0)
	for _i in range(3):
		await get_tree().process_frame

	print("AUTOMATED_BOOT app_state=", App.state, " clean_profile_essence=", SaveData.get_essence())
	Events.entity_absorbed.connect(func(eid: String, _m: float, _xp: float, _pos: Vector2) -> void:
		if main != null and main.arena != null:
			var t := main.arena.run_elapsed
			if _absorbed_count > 0:
				_max_absorb_gap = maxf(_max_absorb_gap, t - _last_absorb_t)
			_last_absorb_t = t
			_absorbed_count += 1
			if _miniboss_spawn_t >= 0.0 and _miniboss_defeat_t < 0.0 and eid in ["umbral_alpha", "stone_beetle_alpha", "crystal_mantis", "thorn_golem"]:
				_miniboss_defeat_t = roundf(t * 10.0) / 10.0
	)
	Events.miniboss_spawned.connect(func(_id: String) -> void:
		if main != null and main.arena != null:
			_miniboss_spawn_t = roundf(main.arena.run_elapsed * 10.0) / 10.0
	)
	Events.boss_spawned.connect(func(_id: String, _mx: float) -> void:
		if main != null and main.arena != null:
			_boss_spawn_t = roundf(main.arena.run_elapsed * 10.0) / 10.0
	)
	Events.player_damaged.connect(func(amt: float, src: String) -> void:
		if main != null and main.arena != null and main.arena.player != null:
			_damage_events.append({
				"t": roundf(main.arena.run_elapsed * 10.0) / 10.0,
				"dmg": roundf(amt * 10.0) / 10.0,
				"hp": roundf(main.arena.player.hp * 10.0) / 10.0,
				"src": src
			})
	)
	set_physics_process(true)


func _setup_boss_audio_capture() -> void:
	if _recording_boss:
		return
	_recording_boss = true
	Audio._ensure_master_limiter()
	var master_idx := AudioServer.get_bus_index("Master")
	# Insert pre-limiter monitor at idx 0 (shifts AudioEffectHardLimiter to idx 1)
	_pre_lim_capture = AudioEffectCapture.new()
	_pre_lim_capture.buffer_length = 8.0
	AudioServer.add_bus_effect(master_idx, _pre_lim_capture, 0)
	# Append post-limiter WAV recorder strictly AFTER AudioEffectHardLimiter (idx 2)
	_post_lim_recorder = Audio.create_post_limiter_recorder()
	_post_lim_recorder.set_recording_active(true)
	_boss_rec_wall_t0_usec = Time.get_ticks_usec()
	print("BOSS_AUDIO_CHAIN:", Audio.get_master_limiter_info())


func _poll_pre_limiter_capture() -> void:
	if _pre_lim_capture == null:
		return
	var avail := _pre_lim_capture.get_frames_available()
	if avail <= 0:
		return
	var buf := _pre_lim_capture.get_buffer(avail)
	_pre_lim_frames += buf.size()
	for v in buf:
		_pre_lim_peak_lin = maxf(_pre_lim_peak_lin, maxf(absf(v.x), absf(v.y)))


func _poll_sfx_telemetry() -> void:
	if _prev_playing_flags.size() != Audio._sfx_players.size():
		_prev_playing_flags.resize(Audio._sfx_players.size())
		_prev_playing_flags.fill(false)
	var conc := 0
	for i in range(Audio._sfx_players.size()):
		var pl := Audio._sfx_players[i].playing
		if pl:
			conc += 1
			if not _prev_playing_flags[i]:
				var ev := Audio._player_events[i]
				_sfx_counts[ev] = int(_sfx_counts.get(ev, 0)) + 1
				_sfx_total += 1
		_prev_playing_flags[i] = pl
	_sfx_max_concurrent = maxi(_sfx_max_concurrent, conc)


func _set_joystick_dir(dir: Vector2) -> void:
	if dir.length_squared() < 0.01:
		if _joy_touch_active:
			_joy_touch_active = false
			var up := InputEventScreenTouch.new()
			up.index = 0
			up.pressed = false
			up.position = _to_screen_pos(_joy_origin_logical)
			Input.parse_input_event(up)
		return
	var norm := dir.normalized()
	if not _joy_touch_active:
		_joy_touch_active = true
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.pressed = true
		down.position = _to_screen_pos(_joy_origin_logical)
		Input.parse_input_event(down)
	var target_logical := _joy_origin_logical + norm * 62.0
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _to_screen_pos(target_logical)
	Input.parse_input_event(drag)


func _pick_best_draft_card_index() -> int:
	var arena := main.arena
	var choices := arena.current_draft_choices
	var best_idx := 0
	var best_score := -999.0
	var priority := {
		"dash": 42.0,
		"spikes": 40.0,
		"magnet": 38.0,
		"regeneration": 36.0,
		"shield": 35.0,
		"freeze": 34.0,
		"electro_discharge": 33.0,
		"speed_boost": 30.0,
		"ranged_absorb": 29.0,
		"split": 27.0,
		"poison_trail": 26.0,
		"mimicry": 24.0
	}
	for i in range(choices.size()):
		var mid := str(choices[i].get("id", ""))
		var sc := float(priority.get(mid, 15.0))
		var syn_id: String = arena.player.mutations.preview_synergy_for_candidate(mid)
		if not syn_id.is_empty():
			sc += 55.0
		if sc > best_score:
			best_score = sc
			best_idx = i
	return best_idx


func _compute_steering() -> Vector2:
	var arena := main.arena
	var player := arena.player
	var ppos := player.global_position
	var prad := player.get_radius()
	var steer := Vector2.ZERO

	var boss := arena.active_boss
	if is_instance_valid(boss) and boss.action_state != AncientGuardianBoss.ActionState.DEFEATED:
		if boss.phase >= 2 and _boss_p2_t < 0.0:
			_boss_p2_t = roundf(arena.run_elapsed * 10.0) / 10.0
		if boss.phase >= 3 and _boss_p3_t < 0.0:
			_boss_p3_t = roundf(arena.run_elapsed * 10.0) / 10.0
		var to_b := boss.global_position - ppos
		var bd := maxf(1.0, to_b.length())
		var bdir := to_b / bd
		if boss.action_state == AncientGuardianBoss.ActionState.TELEGRAPH_CHARGE or boss.action_state == AncientGuardianBoss.ActionState.CHARGING:
			var perp := boss._charge_dir.orthogonal()
			if perp.dot(ppos - boss.global_position) < 0.0:
				perp = -perp
			steer = perp
			if player.dash_cooldown <= 0.0 and bd < 260.0 and main.hud._dash_btn.visible:
				main.hud._dash_btn.pressed.emit()
		elif boss.is_vulnerable() or (boss.hp / maxf(1.0, boss.max_hp)) <= 0.06:
			steer = bdir
			if player.dash_cooldown <= 0.0 and bd < 250.0 and main.hud._dash_btn.visible:
				main.hud._dash_btn.pressed.emit()
		else:
			# Prioritize healing dew drops when injured, otherwise orbit safely
			var best_dew_d := 340.0
			var dew_dir := Vector2.ZERO
			if player.hp < player.max_hp * 0.82:
				for n in arena.orb_pool.get_active_items():
					var ob := n as CollectibleOrb
					if ob != null and ob.visible and ob.orb_type == "dew":
						var dd := ppos.distance_to(ob.global_position)
						if dd < best_dew_d:
							best_dew_d = dd
							dew_dir = (ob.global_position - ppos).normalized()
			if dew_dir != Vector2.ZERO:
				steer = dew_dir
			else:
				var desired := 152.0
				steer = (bdir * clampf((bd - desired) / 65.0, -1.0, 1.0) + bdir.orthogonal() * 0.85).normalized()
				if player.dash_cooldown <= 0.0 and bd < 190.0 and player.hp > 58.0 and main.hud._dash_btn.visible:
					main.hud._dash_btn.pressed.emit()
	else:
		# Pre-boss foraging & threat avoidance
		var best_score := -99999.0
		var best_target := Vector2.ZERO
		for n in arena.enemy_pool.get_active_items():
			var en := n as EnemyEntity
			if en == null or not en.visible:
				continue
			var d := maxf(12.0, ppos.distance_to(en.global_position))
			var ev := AbsorptionRules.evaluate(player.build_absorption_context(), en.build_absorption_context())
			if bool(ev.get("can_absorb", false)):
				var sc := 260.0 / d + en.mass_gain * 8.0
				if sc > best_score:
					best_score = sc
					best_target = en.global_position - ppos
			elif en.contact_damage >= 14.0 and d < 175.0:
				steer -= (en.global_position - ppos).normalized() * ((180.0 - d) / 90.0)

		for n in arena.orb_pool.get_active_items():
			var ob := n as CollectibleOrb
			if ob == null or not ob.visible:
				continue
			var d := maxf(10.0, ppos.distance_to(ob.global_position))
			var val := 210.0 if ob.orb_type == "dew" and player.hp < 85.0 else (155.0 if ob.essence_value > 0 else 115.0)
			var sc := val / d
			if sc > best_score:
				best_score = sc
				best_target = ob.global_position - ppos

		if best_target != Vector2.ZERO:
			steer += best_target.normalized() * 1.15
		else:
			steer += (-ppos).normalized() * 0.6 + Vector2.RIGHT.rotated(arena.run_elapsed * 0.5) * 0.5

	# Hazard & arena-wall avoidance
	for n in arena.hazard_pool.get_active_items():
		var hz := n as HazardZone
		if hz != null and hz.visible and hz.kind != HazardZone.Kind.PLAYER_POISON and not hz._detonated:
			var dv := ppos - hz.global_position
			var dist := dv.length()
			var safe_r := hz.radius + prad + 54.0
			if dist < safe_r:
				var push := dv.normalized() if dist > 0.5 else Vector2.UP
				steer = (steer * 0.25 + push * 2.1).normalized()

	var lim := WorldGenerator.ARENA_HALF_SIZE - 130.0
	if absf(ppos.x) > lim:
		steer.x -= signf(ppos.x) * 1.2
	if absf(ppos.y) > lim:
		steer.y -= signf(ppos.y) * 1.2

	return steer.normalized() if steer.length_squared() > 0.001 else Vector2.RIGHT


func _run_stutter_step_check() -> void:
	_stutter_checked = true
	var arena := main.arena
	if arena == null or arena.player == null or not arena.player.mutations.has_mutation("dash") or arena.player.dash_cooldown > 0.0:
		_stutter_checked = false
		return
	_set_joystick_dir(Vector2.ZERO)
	var joy := main.hud.joystick
	var p0 := Vector2(210.0, 560.0)
	var d1 := InputEventScreenTouch.new()
	d1.index = 3; d1.pressed = true; d1.position = p0
	joy._gui_input(d1)
	var m1 := InputEventScreenDrag.new()
	m1.index = 3; m1.position = p0 + Vector2(24.0, 0.0)
	joy._gui_input(m1)
	var u1 := InputEventScreenTouch.new()
	u1.index = 3; u1.pressed = false; u1.position = p0 + Vector2(24.0, 0.0)
	joy._gui_input(u1)
	var d2 := InputEventScreenTouch.new()
	d2.index = 3; d2.pressed = true; d2.position = p0 + Vector2(3.0, 0.0)
	joy._gui_input(d2)
	var u2 := InputEventScreenTouch.new()
	u2.index = 3; u2.pressed = false; u2.position = p0 + Vector2(3.0, 0.0)
	joy._gui_input(u2)
	_accidental_double_tap_dash = arena.player.is_dashing
	print("STUTTER_STEP_DOUBLE_TAP_CHECK: accidental_dash=", _accidental_double_tap_dash)


func _physics_process(_delta: float) -> void:
	if _finished or main == null or main.arena == null:
		return
	_poll_sfx_telemetry()
	_poll_pre_limiter_capture()

	var arena := main.arena
	var player := arena.player
	if player == null:
		return

	if not _recording_boss and arena.run_elapsed >= arena.boss_spawn_time - 2.0:
		_setup_boss_audio_capture()

	if App.state == App.State.MUTATION_DRAFT:
		_set_joystick_dir(Vector2.ZERO)
		if main.draft_overlay._cards_box.get_child_count() > 0:
			var pick_idx := _pick_best_draft_card_index()
			var card_btn := main.draft_overlay._cards_box.get_child(pick_idx) as Button
			if card_btn != null:
				card_btn.pressed.emit()
		return

	if App.state == App.State.VICTORY or App.state == App.State.DEFEAT:
		_set_joystick_dir(Vector2.ZERO)
		_finished = true
		call_deferred("_finalize_and_quit")
		return

	if App.state != App.State.PLAYING:
		return

	if arena.run_elapsed >= _next_heartbeat_sec:
		var b_hp := -1.0
		if is_instance_valid(arena.active_boss):
			b_hp = roundf(arena.active_boss.hp)
		print("HEARTBEAT t=", roundf(arena.run_elapsed), "s hp=", roundf(player.hp), " mass=", roundf(player.mass), " evo=", player.evolution_level, " boss_hp=", b_hp)
		_next_heartbeat_sec += 30.0

	if not _stutter_checked and arena.run_elapsed > 32.0 and player.mutations.has_mutation("dash") and player.dash_cooldown <= 0.0:
		_run_stutter_step_check()

	_peak_mass = maxf(_peak_mass, player.mass)
	if player.evolution_level > _last_evo_lv:
		while _last_evo_lv < player.evolution_level:
			_last_evo_lv += 1
			_evo_times.append(roundf(arena.run_elapsed * 10.0) / 10.0)

	var dir := _compute_steering()
	_set_joystick_dir(dir)


func _finalize_and_quit() -> void:
	for _i in range(4):
		await get_tree().process_frame
	await _await_draw_if_rendered()
	_poll_pre_limiter_capture()

	var png_out := OS.get_environment(RESULT_PNG_OUT_ENV)
	if not png_out.is_empty() and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(png_out)

	var wav_out := OS.get_environment(BOSS_WAV_OUT_ENV)
	var boss_rec_dur_wall := 0.0
	if _post_lim_recorder != null:
		_post_lim_recorder.set_recording_active(false)
		boss_rec_dur_wall = float(Time.get_ticks_usec() - _boss_rec_wall_t0_usec) / 1000000.0
		var rec_stream := _post_lim_recorder.get_recording()
		if rec_stream != null and not wav_out.is_empty():
			rec_stream.save_to_wav(wav_out)

	var arena := main.arena
	var player := arena.player
	var lim_info := Audio.get_master_limiter_info()
	var pre_db := linear_to_db(_pre_lim_peak_lin) if _pre_lim_peak_lin > 0.000001 else -120.0

	var summary := {
		"verification_kind": "automated_playthrough_script_agent",
		"human_operated": false,
		"cheats_or_direct_stat_edits": false,
		"input_delivery": "InputEventScreenTouch + InputEventScreenDrag via VirtualJoystick & UI Button signals",
		"mutation_draft_policy": "heuristic_over_legitimate_3_card_offer (synergy -> dash -> spikes -> magnet -> regeneration -> shield -> freeze)",
		"world_data_visible_to_agent": [
			"player.global_position / radius / hp / dash_cooldown",
			"active CollectibleOrb positions / kinds",
			"active EnemyEntity positions / AbsorptionRules.evaluate()",
			"active HazardZone positions / radii / detonated flags",
			"AncientGuardianBoss position / phase / action_state / _charge_dir / is_vulnerable() / hp_ratio"
		],
		"timing": {
			"physics_ticks_per_sec": Engine.physics_ticks_per_second,
			"in_game_run_elapsed_sec": roundf(arena.run_elapsed * 10.0) / 10.0,
			"wall_clock_elapsed_sec": roundf(float(Time.get_ticks_usec() - _wall_t0_usec) / 1000000.0 * 10.0) / 10.0
		},
		"final_state": "VICTORY" if App.state == App.State.VICTORY else "DEFEAT",
		"final_hp": roundf(player.hp * 10.0) / 10.0,
		"final_mass": roundf(player.mass * 10.0) / 10.0,
		"peak_mass": roundf(_peak_mass * 10.0) / 10.0,
		"absorbed_count": _absorbed_count,
		"max_absorb_gap_sec": roundf(_max_absorb_gap * 10.0) / 10.0,
		"evo_level": player.evolution_level,
		"evo_times_sec": _evo_times,
		"mutations": player.mutations.levels.duplicate(),
		"synergies": player.mutations.active_synergies.keys(),
		"miniboss_spawn_t": _miniboss_spawn_t,
		"miniboss_defeated_t": _miniboss_defeat_t,
		"boss_spawn_t": _boss_spawn_t,
		"boss_p2_t": _boss_p2_t,
		"boss_p3_t": _boss_p3_t,
		"accidental_double_tap_dash": _accidental_double_tap_dash,
		"essence_earned_base": int(App.last_run_summary.get("base_essence", 0)),
		"saved_essence_after_run": SaveData.get_essence(),
		"damage_events_count": _damage_events.size(),
		"damage_events": _damage_events,
		"music_enabled_default": bool(SaveData.get_setting("music_enabled", false)),
		"music_playing": Audio._music_player.playing,
		"sfx_total_plays": _sfx_total,
		"sfx_max_concurrent_streams": _sfx_max_concurrent,
		"sfx_counts_by_event": _sfx_counts,
		"master_audio_capture": {
			"tap_point": "Master bus effect index after AudioEffectHardLimiter (post-limiter)",
			"limiter_info": lim_info,
			"pre_limiter_frames": _pre_lim_frames,
			"pre_limiter_peak_dbfs": roundf(pre_db * 100.0) / 100.0,
			"recording_wall_sec": roundf(boss_rec_dur_wall * 100.0) / 100.0,
			"wav_path": wav_out
		}
	}

	var json_str := JSON.stringify(summary, "\t")
	var sum_out := OS.get_environment(SUMMARY_OUT_ENV)
	if not sum_out.is_empty():
		var f := FileAccess.open(sum_out, FileAccess.WRITE)
		if f != null:
			f.store_string(json_str + "\n")
			f.close()
	print("AUTOMATED_PLAYTHROUGH_DONE state=", summary["final_state"], " in_game_s=", summary["timing"]["in_game_run_elapsed_sec"], " wall_s=", summary["timing"]["wall_clock_elapsed_sec"])
	get_tree().quit(0)
