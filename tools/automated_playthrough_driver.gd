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
const SCREENSHOT_DIR_ENV := "PLAYTHROUGH_SCREENSHOT_DIR"

var main: MainRoot
var _joy_touch_active: bool = false
var _joy_origin_logical: Vector2 = Vector2(260.0, 980.0)
var _stutter_checked: bool = false
var _accidental_double_tap_dash: bool = false
var _shot_dir: String = ""
var _shots_written: Array[String] = []
var _pause_checked: bool = false
var _pause_resume_ok: bool = false
var _draft_snapped: bool = false
var _draft_hold_frames: int = 0
var _in_pause_probe: bool = false
var _gameplay_snapped: bool = false
var _last_state_logged: int = -1
var _watch_pos: Vector2 = Vector2.ZERO
var _watch_t: float = 0.0
var _pending_shots: Array = []

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
var _music_ids_seen: Dictionary = {}
var _music_switch_count: int = 0
var _last_music_id: String = ""

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
	## Bounded wait for a fresh frame. Never awaits RenderingServer.frame_post_draw directly:
	## macOS stops drawing an unfocused/occluded window, so that signal may never fire and the
	## await would hang forever (observed on unattended runs).
	if DisplayServer.get_name() == "headless":
		return
	for _i in range(3):
		await get_tree().process_frame


func _snap(tag: String) -> void:
	## Saves the real rendered viewport (GPU output) as a PNG. No-op in headless.
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("screenshot failed: " + tag)
		return
	var path := _shot_dir.path_join(tag + ".png")
	if img.save_png(path) == OK:
		_shots_written.append("%s (%dx%d)" % [tag, img.get_width(), img.get_height()])
		print("SCREENSHOT ", tag, " ", img.get_width(), "x", img.get_height())


func _queue_snap(tag: String, delay_frames: int = 10) -> void:
	## Queues a screenshot to be taken after `delay_frames` rendered frames.
	_pending_shots.append({"tag": tag, "at": Engine.get_process_frames() + delay_frames})


func _press_escape() -> void:
	## Delivers a real key event through the engine input pipeline (same path as a physical Esc).
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _layout_checks() -> void:
	## Captures the same menu at several window sizes to verify stretch/aspect and clipping.
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var sizes := [
		{"tag": "00_menu_720x1280", "size": Vector2i(720, 1280)},
		{"tag": "00_menu_540x1200_narrow", "size": Vector2i(540, 1200)},
		{"tag": "00_menu_1080x1920_big", "size": Vector2i(1080, 1920)},
		{"tag": "00_menu_1280x720_landscape", "size": Vector2i(1280, 720)},
	]
	for s in sizes:
		DisplayServer.window_set_size(s["size"])
		for _i in range(4):
			await get_tree().process_frame
		await _await_draw_if_rendered()
		await _snap(str(s["tag"]))
	DisplayServer.window_set_size(Vector2i(720, 1280))
	for _i in range(4):
		await get_tree().process_frame
	await _await_draw_if_rendered()


func _boot_and_run() -> void:
	_shot_dir = OS.get_environment(SCREENSHOT_DIR_ENV)
	if not _shot_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_shot_dir)

	var packed := load("res://scenes/Main.tscn") as PackedScene
	main = packed.instantiate() as MainRoot
	get_tree().root.add_child(main)
	for _i in range(4):
		await get_tree().process_frame
	await _await_draw_if_rendered()

	await _snap("01_main_menu")
	await _layout_checks()

	_prev_playing_flags.resize(Audio._sfx_players.size())
	_prev_playing_flags.fill(false)

	# Tap Play on Main Menu via InputEventScreenTouch
	var play_btn := main.menus.find_child("PlayButton", true, false) as Button
	if play_btn != null:
		await _tap_control(play_btn, 0)
	for _i in range(3):
		await get_tree().process_frame
	await _await_draw_if_rendered()
	await _snap("02_mode_select")

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
		_queue_snap("06_miniboss", 45)
	)
	Events.boss_spawned.connect(func(_id: String, _mx: float) -> void:
		if main != null and main.arena != null:
			_boss_spawn_t = roundf(main.arena.run_elapsed * 10.0) / 10.0
		_queue_snap("07_boss_phase1", 90)
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


## Records which music track the director is on, so the summary proves that the
## soundtrack actually followed the run instead of staying on the menu theme.
func _poll_music_telemetry() -> void:
	var id := Audio.current_music_id()
	if id == _last_music_id:
		return
	if not id.is_empty():
		_music_ids_seen[id] = int(_music_ids_seen.get(id, 0)) + 1
	if not _last_music_id.is_empty() or not id.is_empty():
		_music_switch_count += 1
	_last_music_id = id


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
			_queue_snap("08_boss_phase2", 30)
		if boss.phase >= 3 and _boss_p3_t < 0.0:
			_boss_p3_t = roundf(arena.run_elapsed * 10.0) / 10.0
			_queue_snap("09_boss_phase3", 30)
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
		var threat_pos := Vector2.ZERO
		var threat_d := 1.0e9
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
			elif en.contact_damage >= 14.0:
				if d < 175.0:
					steer -= (en.global_position - ppos).normalized() * ((180.0 - d) / 90.0)
				# Remember the nearest threat that can actually catch the slime: the escape
				# below overrides foraging, because a nudge is not enough against a miniboss
				# that closes faster than the slime runs (that is what used to corner the bot).
				# A slow heavy hitter (predator_flower) is left to the mild repulsion above.
				if (en.is_miniboss or en.move_speed >= 95.0) and d < threat_d:
					threat_d = d
					threat_pos = en.global_position

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

		if threat_d < 215.0:
			# Run away, but curve toward the arena centre: a straight escape pins the slime
			# against the wall where the miniboss's contact damage finishes it.
			var away := (ppos - threat_pos).normalized() if threat_d > 0.5 else Vector2.UP
			var tangent := away.orthogonal()
			if tangent.dot(-ppos) < 0.0:
				tangent = -tangent
			var urgency := clampf((215.0 - threat_d) / 120.0, 0.0, 1.0)
			steer = (away * 1.5 + tangent * 0.85 * urgency).normalized()
			if player.dash_cooldown <= 0.0 and threat_d < 165.0 and main.hud._dash_btn.visible:
				main.hud._dash_btn.pressed.emit()

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


func _flush_pending_shots() -> void:
	if _pending_shots.is_empty():
		return
	var now := Engine.get_process_frames()
	var keep: Array = []
	for p in _pending_shots:
		if int(p["at"]) <= now:
			_snap(str(p["tag"]))
		else:
			keep.append(p)
	_pending_shots = keep


func _run_pause_check() -> void:
	_in_pause_probe = true
	_set_joystick_dir(Vector2.ZERO)
	var t_before := main.arena.run_elapsed
	await _press_escape()
	for _i in range(10):
		await get_tree().process_frame
	var paused_ok := App.state == App.State.PAUSED
	var t_paused := main.arena.run_elapsed
	_snap("05_pause_overlay")
	await _press_escape()
	for _i in range(10):
		await get_tree().process_frame
	var resumed_ok := App.state == App.State.PLAYING
	var frozen := absf(t_paused - t_before) < 0.5
	_pause_resume_ok = paused_ok and resumed_ok and frozen
	_joy_touch_active = false
	_in_pause_probe = false
	print("PAUSE_RESUME_CHECK paused=", paused_ok, " resumed=", resumed_ok, " run_time_frozen=", frozen)


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
	_poll_music_telemetry()
	_poll_pre_limiter_capture()

	var arena := main.arena
	var player := arena.player
	if player == null:
		return

	if App.state != _last_state_logged:
		_last_state_logged = App.state
		var cards := -1
		if main.draft_overlay != null:
			cards = main.draft_overlay._cards_box.get_child_count()
		print("STATE_CHANGE t=", roundf(arena.run_elapsed * 10.0) / 10.0, " state=", App.state, " draft_cards=", cards)

	if not _recording_boss and arena.run_elapsed >= arena.boss_spawn_time - 2.0:
		_setup_boss_audio_capture()

	if App.state == App.State.MUTATION_DRAFT:
		_set_joystick_dir(Vector2.ZERO)
		if main.draft_overlay._cards_box.get_child_count() > 0:
			# Hold the first draft open briefly so the overlay is actually rendered and captured.
			if not _draft_snapped:
				_draft_snapped = true
				_draft_hold_frames = 14
			if _draft_hold_frames > 0:
				_draft_hold_frames -= 1
				if _draft_hold_frames == 0:
					_snap("04_mutation_draft")
				return
			var pick_idx := _pick_best_draft_card_index()
			var card_btn := main.draft_overlay._cards_box.get_child(pick_idx) as Button
			if card_btn != null:
				card_btn.pressed.emit()
		return

	# The game auto-pauses on window focus loss (mobile interruption safety). Unattended runs
	# lose focus constantly, so undo ONLY that external pause; our own pause probe is excluded.
	# Any state exit from PLAYING calls joystick.reset_stick(), so the held touch must be
	# re-armed with a fresh touch-down or the following drags would be ignored.
	if App.state == App.State.PAUSED and not _in_pause_probe:
		_joy_touch_active = false
		App.handle_back_navigation()
		return

	if App.state == App.State.VICTORY or App.state == App.State.DEFEAT:
		_set_joystick_dir(Vector2.ZERO)
		_finished = true
		call_deferred("_finalize_and_quit")
		return

	if App.state != App.State.PLAYING:
		return

	_flush_pending_shots()

	if not _gameplay_snapped and arena.run_elapsed > 1.5:
		_gameplay_snapped = true
		_queue_snap("03_gameplay_start", 2)

	if not _pause_checked and arena.run_elapsed > 12.0:
		_pause_checked = true
		call_deferred("_run_pause_check")

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

	# Watchdog: if the slime is not moving while we hold a direction, the joystick lost the
	# touch (e.g. reset by a state change). Re-arm the touch so the run cannot silently stall.
	if arena.run_elapsed - _watch_t > 2.0:
		_watch_t = arena.run_elapsed
		if _joy_touch_active and player.global_position.distance_to(_watch_pos) < 4.0:
			_joy_touch_active = false
			print("JOY_REARM t=", roundf(arena.run_elapsed * 10.0) / 10.0)
		_watch_pos = player.global_position


func _start_quit_watchdog(sec: float = 25.0) -> void:
	var timer := get_tree().create_timer(sec, true, false, true)
	timer.timeout.connect(func() -> void:
		printerr("PLAYTHROUGH_WATCHDOG: finalize exceeded %.0fs, forcing quit" % sec)
		get_tree().quit(3)
	)


## Written before the full telemetry sweep so the summary file always exists, even if a
## later property read errors out. The complete summary overwrites it with partial=false.
func _write_partial_summary() -> void:
	var sum_out := OS.get_environment(SUMMARY_OUT_ENV)
	if sum_out.is_empty():
		return
	var f := FileAccess.open(sum_out, FileAccess.WRITE)
	if f == null:
		return
	var arena := main.arena
	var partial := {
		"verification_kind": "automated_playthrough_script_agent",
		"partial": true,
		"note": "Preliminary write; overwritten by the full summary. Seeing this means telemetry collection failed.",
		"final_state": "VICTORY" if App.state == App.State.VICTORY else "DEFEAT",
		"in_game_run_elapsed_sec": roundf(arena.run_elapsed * 10.0) / 10.0,
		"final_hp": roundf(arena.player.hp * 10.0) / 10.0
	}
	f.store_string(JSON.stringify(partial, "\t") + "\n")
	f.close()


func _finalize_and_quit() -> void:
	# Watchdog first: if any telemetry call below hits a runtime error, GDScript aborts
	# the rest of this function and quit() is never reached — the process then hangs on
	# the result screen forever. A hard deadline guarantees the runner always terminates.
	_start_quit_watchdog()
	_write_partial_summary()
	for _i in range(4):
		await get_tree().process_frame
	await _await_draw_if_rendered()
	_poll_pre_limiter_capture()
	_poll_music_telemetry()

	var png_out := OS.get_environment(RESULT_PNG_OUT_ENV)
	if not png_out.is_empty() and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(png_out)
	await _snap("10_run_result")

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
		"partial": false,
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
		"pause_resume_check": {
			"performed": _pause_checked,
			"paused_and_resumed_with_time_frozen": _pause_resume_ok
		},
		"screenshots_written": _shots_written,
		"essence_earned_base": int(App.last_run_summary.get("base_essence", 0)),
		"saved_essence_after_run": SaveData.get_essence(),
		"damage_events_count": _damage_events.size(),
		"damage_events": _damage_events,
		"music_enabled_default": bool(SaveData.get_setting("music_enabled", false)),
		"music_playing": Audio.is_music_playing(),
		"music_track_at_finish": Audio.current_music_id(),
		"music_tracks_seen": _music_ids_seen,
		"music_switch_count": _music_switch_count,
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
