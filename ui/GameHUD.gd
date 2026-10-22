class_name GameHUD
extends Control
## In-game mobile HUD (Screen 3): HP, Mass, Evolution XP, Timer, Essence, Active Mutations,
## Boss HP bar, contextual Tutorial/Toast banner, Virtual Joystick, and Dash button.

var arena: ArenaController = null
var joystick: VirtualJoystick

var _hp_bar: ProgressBar
var _hp_label: Label
var _evo_bar: ProgressBar
var _mass_label: Label
var _timer_label: Label
var _essence_label: Label
var _boss_box: PanelContainer
var _boss_name_lbl: Label
var _boss_bar: ProgressBar
var _mut_strip: HBoxContainer
var _toast_panel: PanelContainer
var _toast_label: Label
var _dash_btn: Button
var _pause_btn: Button
var _toast_timer: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_layout()
	_connect_signals()


func bind_arena(p_arena: ArenaController) -> void:
	arena = p_arena


func _build_layout() -> void:
	# 1. Full-lower-half touch region for one-finger Virtual Joystick
	joystick = VirtualJoystick.new()
	joystick.name = "VirtualJoystick"
	joystick.anchor_left = 0.0
	joystick.anchor_right = 1.0
	joystick.anchor_top = 0.22
	joystick.anchor_bottom = 1.0
	add_child(joystick)

	# 2. Top Safe-Area HUD Margin
	var top_margin := MarginContainer.new()
	top_margin.anchor_left = 0.0
	top_margin.anchor_right = 1.0
	top_margin.anchor_top = 0.0
	top_margin.offset_bottom = 230.0
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_margin.add_theme_constant_override("margin_top", 16)
	add_child(top_margin)

	var top_vbox := VBoxContainer.new()
	top_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_vbox.add_theme_constant_override("separation", 8)
	top_margin.add_child(top_vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	top_vbox.add_child(row1)

	var stats_col := VBoxContainer.new()
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.add_theme_constant_override("separation", 6)
	row1.add_child(stats_col)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 22)
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("fill", UIThemeBuilder.make_box(Color(0.95, 0.34, 0.44), Color.TRANSPARENT, 8, 0, 2, 2))
	stats_col.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_bar.add_child(_hp_label)

	_evo_bar = ProgressBar.new()
	_evo_bar.custom_minimum_size = Vector2(0, 22)
	_evo_bar.show_percentage = false
	stats_col.add_child(_evo_bar)

	_mass_label = Label.new()
	_mass_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mass_label.add_theme_font_size_override("font_size", 14)
	_evo_bar.add_child(_mass_label)

	var right_info := VBoxContainer.new()
	right_info.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_child(right_info)

	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 19)
	right_info.add_child(_timer_label)

	_essence_label = Label.new()
	_essence_label.text = "✦ 0"
	_essence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_essence_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.86))
	_essence_label.add_theme_font_size_override("font_size", 17)
	right_info.add_child(_essence_label)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.custom_minimum_size = Vector2(54, 54)
	_pause_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		App.change_state(App.State.PAUSED)
	)
	row1.add_child(_pause_btn)

	# Active Mutations & Synergies mini-icon strip
	_mut_strip = HBoxContainer.new()
	_mut_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mut_strip.add_theme_constant_override("separation", 6)
	top_vbox.add_child(_mut_strip)

	# Boss Health Bar (shown when Ancient Forest Guardian awakens)
	_boss_box = PanelContainer.new()
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	_boss_box.add_child(bv)
	_boss_name_lbl = Label.new()
	_boss_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_boss_name_lbl.add_theme_font_size_override("font_size", 17)
	bv.add_child(_boss_name_lbl)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 18)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("fill", UIThemeBuilder.make_box(Color(1.0, 0.42, 0.35), Color.TRANSPARENT, 8, 0, 2, 2))
	bv.add_child(_boss_bar)
	top_vbox.add_child(_boss_box)

	# Contextual Tutorial / Toast notification banner
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Label.new()
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 17)
	_toast_panel.add_child(_toast_label)
	top_vbox.add_child(_toast_panel)

	# Bottom-Right Active Dash Thumb Button (shown once 'dash' mutation is acquired)
	_dash_btn = Button.new()
	_dash_btn.name = "DashButton"
	_dash_btn.visible = false
	_dash_btn.text = Loc.t("hud.dash")
	_dash_btn.custom_minimum_size = Vector2(118, 86)
	_dash_btn.anchor_left = 1.0
	_dash_btn.anchor_right = 1.0
	_dash_btn.anchor_top = 1.0
	_dash_btn.anchor_bottom = 1.0
	_dash_btn.offset_left = -140.0
	_dash_btn.offset_right = -22.0
	_dash_btn.offset_top = -132.0
	_dash_btn.offset_bottom = -46.0
	UIThemeBuilder.style_primary_cta(_dash_btn)
	_dash_btn.pressed.connect(func() -> void:
		if arena != null and arena.player != null:
			arena.player.trigger_dash()
	)
	add_child(_dash_btn)


func _connect_signals() -> void:
	Events.player_hp_changed.connect(func(cur: float, mx: float) -> void:
		_hp_bar.max_value = maxf(1.0, mx)
		_hp_bar.value = cur
		_hp_label.text = "%s: %d / %d" % [Loc.t("hud.hp"), int(ceil(cur)), int(round(mx))]
	)
	Events.player_mass_changed.connect(func(_m: float, _r: float) -> void:
		_refresh_evo_label()
	)
	Events.evolution_progress_changed.connect(func(xp: float, thresh: float, _lv: int) -> void:
		_evo_bar.max_value = maxf(1.0, thresh)
		_evo_bar.value = xp
		_refresh_evo_label()
	)
	Events.run_timer_updated.connect(func(sec: float, _target: float) -> void:
		var mins: int = int(sec) / 60
		var rem: int = int(sec) % 60
		_timer_label.text = "%02d:%02d" % [mins, rem]
	)
	Events.essence_collected.connect(func(_amt: int, total: int) -> void:
		_essence_label.text = "✦ %d" % total
	)
	Events.run_started.connect(func(_mode: String) -> void:
		_boss_box.visible = false
		_essence_label.text = "✦ 0"
		_dash_btn.visible = false
		joystick.reset_stick()
		_rebuild_mutation_strip()
	)
	Events.mutation_applied.connect(func(_mid: String, _lv: int) -> void:
		_rebuild_mutation_strip()
		if arena != null and arena.player != null:
			_dash_btn.visible = arena.player.mutations.has_mutation("dash")
	)
	Events.synergy_activated.connect(func(sid: String) -> void:
		_rebuild_mutation_strip()
		var sname := Loc.t(str(ConfigDB.synergies.get(sid, {}).get("name_key", sid)))
		show_toast("%s %s!" % [Loc.t("hud.synergy_unlocked"), sname], Color(1.0, 0.90, 0.42), 4.0)
	)
	Events.active_skill_cooldown_updated.connect(func(skill_id: String, rem: float, _dur: float) -> void:
		if skill_id == "dash":
			_dash_btn.disabled = rem > 0.05
			_dash_btn.text = ("%.1fs" % rem) if rem > 0.05 else Loc.t("hud.dash")
	)
	Events.boss_spawned.connect(func(_bid: String, mx: float) -> void:
		_boss_box.visible = true
		_boss_bar.max_value = mx
		_boss_bar.value = mx
		_boss_name_lbl.text = "%s (I)" % Loc.t("boss.ancient_guardian.name")
	)
	Events.boss_updated.connect(func(cur: float, mx: float, phase: int) -> void:
		_boss_bar.max_value = maxf(1.0, mx)
		_boss_bar.value = cur
		var numerals := ["I", "II", "III"]
		var rom: String = numerals[clampi(phase - 1, 0, 2)]
		_boss_name_lbl.text = "%s (%s)" % [Loc.t("boss.ancient_guardian.name"), rom]
	)
	Events.boss_defeated.connect(func(_bid: String) -> void:
		_boss_box.visible = false
	)
	Events.tutorial_step_shown.connect(func(_idx: int, tkey: String) -> void:
		show_toast(Loc.t(tkey), Color(0.68, 1.0, 0.88), 6.0)
	)
	Events.tutorial_completed.connect(func() -> void:
		_toast_panel.visible = false
	)
	Events.toast_requested.connect(func(msg: String, col: Color) -> void:
		show_toast(msg, col, 3.2)
	)


func _refresh_evo_label() -> void:
	if arena == null or arena.player == null:
		return
	_mass_label.text = "%s: %.1f  |  %s %d" % [
		Loc.t("hud.mass"),
		arena.player.mass,
		Loc.t("hud.evo"),
		arena.player.evolution_level + 1
	]


func show_toast(msg: String, col: Color, dur: float = 3.5) -> void:
	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", col)
	_toast_panel.visible = true
	_toast_timer = dur


func _rebuild_mutation_strip() -> void:
	for ch in _mut_strip.get_children():
		ch.queue_free()
	if arena == null or arena.player == null:
		return
	for mid in arena.player.mutations.levels.keys():
		var lv: int = arena.player.mutations.get_level(str(mid))
		var cfg := ConfigDB.get_mutation(str(mid))
		var tex := AssetRegistry.get_texture(str(cfg.get("icon", "")))
		var badge := HBoxContainer.new()
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(28, 28)
			badge.add_child(tr)
		var lbl := Label.new()
		lbl.text = str(lv)
		lbl.add_theme_font_size_override("font_size", 14)
		badge.add_child(lbl)
		_mut_strip.add_child(badge)

	for sid in arena.player.mutations.active_synergies.keys():
		var scfg: Dictionary = ConfigDB.synergies.get(str(sid), {})
		var stex := AssetRegistry.get_texture(str(scfg.get("icon", "")))
		if stex != null:
			var str_rect := TextureRect.new()
			str_rect.texture = stex
			str_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			str_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			str_rect.custom_minimum_size = Vector2(32, 32)
			_mut_strip.add_child(str_rect)


func _process(delta: float) -> void:
	if arena != null and arena.player != null and App.state == App.State.PLAYING:
		arena.player.move_input = joystick.output_vector
		if Input.is_action_just_pressed("ui_accept"):
			arena.player.trigger_dash()

	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_panel.visible = false
