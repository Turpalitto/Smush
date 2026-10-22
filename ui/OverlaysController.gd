class_name OverlaysController
extends Control
## Screens 5, 6, 7: Pause Modal, Victory Results Screen, and Defeat / Voluntary Revive Screen.

signal navigate_to_upgrades()
signal navigate_to_main_menu()

var arena: ArenaController = null

var _pause_root: Control
var _pause_title: Label
var _pause_build_lbl: Label
var _pause_resume_btn: Button
var _pause_joy_btn: Button
var _pause_restart_btn: Button
var _pause_quit_btn: Button

var _result_root: Control
var _result_title: Label
var _result_stats: Label
var _result_essence: Label
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
	Events.game_state_changed.connect(_on_state_changed)


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
	card.custom_minimum_size = Vector2(520, 0)
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
	card.custom_minimum_size = Vector2(540, 0)
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
	_result_title.text = Loc.t("result.victory" if victory else "result.defeat")
	_result_title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.78) if victory else Color(1.0, 0.52, 0.56))

	var sec: int = int(sum.get("duration_sec", 0.0))
	var t_str := "%02d:%02d" % [sec / 60, sec % 60]
	_result_stats.text = Loc.t("result.stats", {
		"time": t_str,
		"mass": str(sum.get("peak_mass", 10.0)),
		"absorbed": str(sum.get("absorbed", 0)),
		"mutations": str(sum.get("mutations_count", 0))
	})
	_result_essence.text = Loc.t("result.essence_earned", {"essence": str(sum.get("final_essence", 0))})

	var can_rev: bool = bool(sum.get("can_revive", false)) and Ads.can_offer(Ads.PLACEMENT_REVIVE)
	_revive_btn.visible = (not victory) and can_rev
	_revive_btn.text = Loc.t("result.revive_ad")

	var can_dbl := (arena != null and not arena.reward_doubled and Ads.can_offer(Ads.PLACEMENT_DOUBLE_REWARD))
	_double_btn.visible = can_dbl or (arena != null and arena.reward_doubled)
	_double_btn.disabled = (arena != null and arena.reward_doubled)
	_double_btn.text = Loc.t("result.double_claimed") if (arena != null and arena.reward_doubled) else Loc.t("result.double_ad")

	_ad_status_lbl.visible = (not can_rev and not can_dbl and (arena == null or not arena.reward_doubled))
	_ad_status_lbl.text = Loc.t("result.ad_unavailable")

	_again_btn.text = Loc.t("result.play_again")
	_upgrades_btn.text = Loc.t("result.to_upgrades")
	_menu_btn.text = Loc.t("result.to_menu")
