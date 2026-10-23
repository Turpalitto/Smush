class_name OverlaysController
extends Control
## Screens 5, 6, 7: Pause Modal, Victory Results Screen, and Defeat / Voluntary Revive Screen.

signal navigate_to_upgrades()
signal navigate_to_main_menu()

var arena: ArenaController = null

var _pause_root: Control
var _pause_card: PanelContainer
var _pause_title: Label
var _pause_build_lbl: Label
var _pause_resume_btn: Button
var _pause_walk_btn: Button
var _pause_joy_btn: Button
var _pause_restart_btn: Button
var _pause_quit_btn: Button

var _result_root: Control
var _result_card: PanelContainer
var _result_title: Label
var _result_stats: Label
var _result_essence: Label
var _result_difficulty: Label
var _result_record: Label
var _revive_btn: Button
var _double_btn: Button
var _ad_status_lbl: Label
var _again_btn: Button
var _upgrades_btn: Button
var _menu_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_pause_panel()
	_build_result_panel()
	resized.connect(_adapt_modal_widths)
	_adapt_modal_widths()
	Events.game_state_changed.connect(_on_state_changed)


func _adapt_modal_widths() -> void:
	var target_w := clampf(size.x - 44.0, 290.0, 520.0)
	if _pause_card != null:
		_pause_card.custom_minimum_size = Vector2(target_w, 0.0)
	if _result_card != null:
		_result_card.custom_minimum_size = Vector2(target_w, 0.0)


func bind_arena(p_arena: ArenaController) -> void:
	arena = p_arena


func _make_modal_backdrop() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.06, 0.08, 0.82)
	root.add_child(dim)
	add_child(root)
	return root


func _build_pause_panel() -> void:
	_pause_root = _make_modal_backdrop()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	_pause_root.add_child(margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)

	var card := PanelContainer.new()
	_pause_card = card
	card.custom_minimum_size = Vector2(300, 0)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	_pause_title = Label.new()
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title.add_theme_font_size_override("font_size", 28)
	vb.add_child(_pause_title)

	_pause_build_lbl = Label.new()
	_pause_build_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_build_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_build_lbl.add_theme_font_size_override("font_size", 16)
	_pause_build_lbl.add_theme_color_override("font_color", Color(0.70, 0.96, 0.88))
	vb.add_child(_pause_build_lbl)

	_pause_resume_btn = Button.new()
	_pause_resume_btn.custom_minimum_size = Vector2(0, 56)
	UIThemeBuilder.style_primary_cta(_pause_resume_btn)
	_pause_resume_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		App.change_state(App.State.PLAYING)
	)
	vb.add_child(_pause_resume_btn)

	# Zen has no Guardian, so the player needs a way to end the walk on their own
	# terms. Hidden in every other mode, where the run has a natural ending.
	_pause_walk_btn = Button.new()
	_pause_walk_btn.custom_minimum_size = Vector2(0, 56)
	_pause_walk_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.end_zen_walk()
	)
	vb.add_child(_pause_walk_btn)

	_pause_joy_btn = Button.new()
	_pause_joy_btn.custom_minimum_size = Vector2(0, 52)
	_pause_joy_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		var cur := str(SaveData.get_setting("joystick_mode", "floating"))
		SaveData.set_setting("joystick_mode", "fixed" if cur == "floating" else "floating")
		_refresh_pause_texts()
	)
	vb.add_child(_pause_joy_btn)

	_pause_restart_btn = Button.new()
	_pause_restart_btn.custom_minimum_size = Vector2(0, 52)
	_pause_restart_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.start_new_run(arena.mode_id)
	)
	vb.add_child(_pause_restart_btn)

	_pause_quit_btn = Button.new()
	_pause_quit_btn.custom_minimum_size = Vector2(0, 52)
	_pause_quit_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		navigate_to_main_menu.emit()
	)
	vb.add_child(_pause_quit_btn)


func _build_result_panel() -> void:
	_result_root = _make_modal_backdrop()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	_result_root.add_child(margin)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(center)

	var card := PanelContainer.new()
	_result_card = card
	card.custom_minimum_size = Vector2(300, 0)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_title.add_theme_font_size_override("font_size", 28)
	vb.add_child(_result_title)

	_result_stats = Label.new()
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats.add_theme_font_size_override("font_size", 18)
	vb.add_child(_result_stats)

	_result_essence = Label.new()
	_result_essence.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_essence.add_theme_font_size_override("font_size", 23)
	_result_essence.add_theme_color_override("font_color", Color(0.55, 1.0, 0.82))
	vb.add_child(_result_essence)

	_result_difficulty = Label.new()
	_result_difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_difficulty.add_theme_font_size_override("font_size", 15)
	_result_difficulty.add_theme_color_override("font_color", Color(0.72, 0.83, 0.87))
	vb.add_child(_result_difficulty)

	_result_record = Label.new()
	_result_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_record.add_theme_font_size_override("font_size", 16)
	vb.add_child(_result_record)

	_revive_btn = Button.new()
	_revive_btn.custom_minimum_size = Vector2(0, 56)
	UIThemeBuilder.style_primary_cta(_revive_btn)
	_revive_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.try_revive_with_ad(func(_ok: bool, _r: String) -> void:
				_refresh_result_panel()
			)
	)
	vb.add_child(_revive_btn)

	_double_btn = Button.new()
	_double_btn.custom_minimum_size = Vector2(0, 54)
	_double_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.try_double_run_reward_with_ad(func(ok: bool, _r: String) -> void:
				if ok:
					_double_btn.disabled = true
					_double_btn.text = Loc.t("result.double_claimed")
				_refresh_result_panel()
			)
	)
	vb.add_child(_double_btn)

	_ad_status_lbl = Label.new()
	_ad_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ad_status_lbl.add_theme_font_size_override("font_size", 14)
	_ad_status_lbl.add_theme_color_override("font_color", Color(0.68, 0.78, 0.80))
	vb.add_child(_ad_status_lbl)

	_again_btn = Button.new()
	_again_btn.custom_minimum_size = Vector2(0, 56)
	UIThemeBuilder.style_primary_cta(_again_btn)
	_again_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.commit_run_rewards()
			arena.start_new_run(arena.mode_id)
	)
	vb.add_child(_again_btn)

	_upgrades_btn = Button.new()
	_upgrades_btn.custom_minimum_size = Vector2(0, 52)
	_upgrades_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.commit_run_rewards()
		navigate_to_upgrades.emit()
	)
	vb.add_child(_upgrades_btn)

	_menu_btn = Button.new()
	_menu_btn.custom_minimum_size = Vector2(0, 52)
	_menu_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		if arena != null:
			arena.commit_run_rewards()
		navigate_to_main_menu.emit()
	)
	vb.add_child(_menu_btn)


func _on_state_changed(_old: int, new_st: int) -> void:
	_pause_root.visible = (new_st == App.State.PAUSED)
	_result_root.visible = (new_st == App.State.VICTORY or new_st == App.State.DEFEAT)
	mouse_filter = Control.MOUSE_FILTER_STOP if (_pause_root.visible or _result_root.visible) else Control.MOUSE_FILTER_IGNORE

	if _pause_root.visible:
		_refresh_pause_texts()
	elif _result_root.visible:
		_refresh_result_panel()


func _refresh_pause_texts() -> void:
	_pause_title.text = Loc.t("pause.title")
	_pause_resume_btn.text = Loc.t("pause.resume")
	var jmode := str(SaveData.get_setting("joystick_mode", "floating"))
	_pause_joy_btn.text = "%s: %s" % [Loc.t("settings.joystick"), Loc.t("settings.joystick." + jmode)]
	_pause_restart_btn.text = Loc.t("pause.restart")
	_pause_quit_btn.text = Loc.t("pause.quit")
	_pause_walk_btn.text = Loc.t("pause.finish_walk")
	_pause_walk_btn.visible = (arena != null and arena.is_zen())

	if arena != null and arena.player != null:
		var parts: Array[String] = []
		for mid in arena.player.mutations.levels.keys():
			var cfg := ConfigDB.get_mutation(str(mid))
			parts.append("%s (%d)" % [Loc.t(str(cfg.get("name_key", mid))), arena.player.mutations.get_level(str(mid))])
		for sid in arena.player.mutations.active_synergies.keys():
			var scfg: Dictionary = ConfigDB.synergies.get(str(sid), {})
			parts.append("★ " + Loc.t(str(scfg.get("name_key", sid))))
		_pause_build_lbl.text = ", ".join(parts) if not parts.is_empty() else Loc.t("pause.active_build")


func _refresh_result_panel() -> void:
	var sum: Dictionary = App.last_run_summary
	var victory: bool = (App.state == App.State.VICTORY)
	var outcome := str(sum.get("outcome", "victory" if victory else "defeat"))
	# Three outcomes now: a Guardian kill, a defeat, and a zen walk the player chose
	# to end. The walk is neither a win nor a loss, so it gets its own wording and a
	# calm colour - showing "DEFEAT" for a deliberate end would be a lie.
	var title_key := "result.victory" if victory else "result.defeat"
	var title_col := Color(0.55, 1.0, 0.78) if victory else Color(1.0, 0.52, 0.56)
	if outcome == "walk":
		title_key = "result.walk"
		title_col = Color(0.72, 0.94, 1.0)
	_result_title.text = Loc.t(title_key)
	_result_title.add_theme_color_override("font_color", title_col)

	var sec: int = int(sum.get("duration_sec", 0.0))
	var t_str := "%02d:%02d" % [sec / 60, sec % 60]
	_result_stats.text = Loc.t("result.stats", {
		"time": t_str,
		"mass": str(sum.get("peak_mass", 10.0)),
		"absorbed": str(sum.get("absorbed", 0)),
		"mutations": str(sum.get("mutations_count", 0))
	})
	# The ascension loop is the whole point of the endless mode; a run that reached
	# loop 3 must not look identical to one that never left loop 0.
	var loop_idx := int(sum.get("ascension_loop", 0))
	if loop_idx > 0:
		_result_stats.text += "\n" + Loc.t("hud.ascension_loop", {"n": str(loop_idx)})
	_result_essence.text = Loc.t("result.essence_earned", {"essence": str(sum.get("final_essence", 0))})
	_refresh_result_record(sum)

	var can_rev: bool = bool(sum.get("can_revive", false)) and Ads.can_offer(Ads.PLACEMENT_REVIVE)
	_revive_btn.visible = (not victory) and can_rev
	_revive_btn.text = Loc.t("result.revive_ad")

	var can_dbl := (arena != null and not arena.reward_doubled and Ads.can_offer(Ads.PLACEMENT_DOUBLE_REWARD))
	_double_btn.visible = can_dbl or (arena != null and arena.reward_doubled)
	_double_btn.disabled = (arena != null and arena.reward_doubled)
	_double_btn.text = Loc.t("result.double_claimed") if (arena != null and arena.reward_doubled) else Loc.t("result.double_ad")

	# Only claim "ads are offline" on a platform that can actually serve them, and only
	# when none of the placements is obtainable. Desktop builds have no ad backend at
	# all, so the line there would be permanent noise under the result card.
	_ad_status_lbl.visible = (not can_rev and not can_dbl and (arena == null or not arena.reward_doubled)
		and Ads.platform_supports_ads() and not Ads.any_placement_available())
	_ad_status_lbl.text = Loc.t("result.ad_unavailable")

	_again_btn.text = Loc.t("result.play_again")
	_upgrades_btn.text = Loc.t("result.to_upgrades")
	_menu_btn.text = Loc.t("result.to_menu")


func _format_run_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _refresh_result_record(sum: Dictionary) -> void:
	## Records are committed together with the essence reward, so on a defeat screen
	## (revive still offered) the fresh record is not in the summary yet — fall back to
	## the stored personal best and simply do not claim a new record.
	var diff_id := str(sum.get("difficulty", SaveData.get_difficulty_id()))
	var dcfg: Dictionary = ConfigDB.get_difficulty(diff_id)
	var is_custom_diff := diff_id != ConfigDB.get_default_difficulty_id()
	_result_difficulty.visible = is_custom_diff
	_result_difficulty.text = Loc.t("result.difficulty", {"name": Loc.t(str(dcfg.get("name_key", diff_id)))})

	var rec: Dictionary = {}
	if typeof(sum.get("record")) == TYPE_DICTIONARY:
		rec = sum["record"]
	var new_time := bool(rec.get("is_new_best_time", false))
	var new_mass := bool(rec.get("is_new_best_mass", false))
	if rec.is_empty():
		var prev: Dictionary = SaveData.get_record(str(sum.get("mode", "standard")), diff_id)
		rec = {"best_time": prev.get("best_time", 0.0), "best_mass": prev.get("best_mass", 0.0)}

	var parts: Array[String] = []
	if new_time:
		parts.append(Loc.t("result.new_record"))
	elif float(rec.get("best_time", 0.0)) > 0.0:
		parts.append(Loc.t("result.record_line", {"time": _format_run_time(float(rec["best_time"]))}))
	if new_mass:
		parts.append(Loc.t("result.new_best_mass", {"mass": str(int(round(float(rec.get("best_mass", 0.0)))))}))
	_result_record.text = "\n".join(parts)
	_result_record.visible = not parts.is_empty()
	_result_record.add_theme_color_override("font_color", Color(1.0, 0.86, 0.40) if (new_time or new_mass) else Color(0.72, 0.83, 0.87))

