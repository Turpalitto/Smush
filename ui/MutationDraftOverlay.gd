class_name MutationDraftOverlay
extends Control
## Screen 4: Mutation Choice Modal presenting 3 weighted-random mutations,
## synergy completion preview badges, and optional 1x Reroll (No Ads free or Rewarded Ad).

var arena: ArenaController = null
var _title_lbl: Label
var _cards_box: VBoxContainer
var _reroll_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.06, 0.08, 0.80)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	margin.add_child(center)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_font_size_override("font_size", 26)
	_title_lbl.add_theme_color_override("font_color", Color(0.65, 1.0, 0.86))
	center.add_child(_title_lbl)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	center.add_child(_cards_box)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(0, 52)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	center.add_child(_reroll_btn)

	Events.mutation_draft_requested.connect(_populate_choices)
	Events.game_state_changed.connect(func(_old: int, new_st: int) -> void:
		visible = (new_st == App.State.MUTATION_DRAFT)
	)


func bind_arena(p_arena: ArenaController) -> void:
	arena = p_arena


func _populate_choices(choices: Array) -> void:
	_title_lbl.text = Loc.t("draft.title")
	for ch in _cards_box.get_children():
		# Remove immediately so chained drafts never show two sets of cards.
		_cards_box.remove_child(ch)
		ch.queue_free()

	for idx in range(choices.size()):
		var item: Dictionary = choices[idx]
		var mid: String = str(item.get("id", ""))
		var cfg := ConfigDB.get_mutation(mid)
		var rarity: String = str(item.get("rarity", "common"))
		var cur_lv: int = int(item.get("current_level", 0))
		var next_lv: int = int(item.get("next_level", 1))
		var max_lv: int = int(item.get("max_level", 5))
		var syn_id: String = str(item.get("completes_synergy", ""))

		var border_col := Color(0.35, 0.85, 0.72)
		if rarity == "rare":
			border_col = Color(0.38, 0.75, 1.0)
		elif rarity == "epic":
			border_col = Color(0.88, 0.52, 1.0)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 128)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_stylebox_override("normal", UIThemeBuilder.make_box(Color(0.08, 0.17, 0.20, 0.98), border_col, 18, 3, 14, 12))
		btn.add_theme_stylebox_override("hover", UIThemeBuilder.make_box(Color(0.13, 0.25, 0.28, 1.0), border_col.lightened(0.25), 18, 3, 14, 12))
		btn.add_theme_stylebox_override("pressed", UIThemeBuilder.make_box(Color(0.06, 0.14, 0.17, 1.0), Color(0.85, 1.0, 0.92), 18, 3, 14, 12))
		btn.pressed.connect(func() -> void:
			if arena != null:
				arena.select_draft_mutation(mid)
		)

		var hbox := HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 14)
		var pad := MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", 14)
		pad.add_theme_constant_override("margin_right", 14)
		pad.add_theme_constant_override("margin_top", 10)
		pad.add_theme_constant_override("margin_bottom", 10)
		pad.add_child(hbox)
		btn.add_child(pad)

		var tex := AssetRegistry.get_texture(str(cfg.get("icon", "")))
		if tex != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(64, 64)
			icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(icon_rect)

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.alignment = BoxContainer.ALIGNMENT_CENTER
		text_col.add_theme_constant_override("separation", 4)
		text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(text_col)

		var lv_tag := ("%s %d→%d/%d" % [Loc.t("common.level"), cur_lv, next_lv, max_lv]) if cur_lv > 0 else ("%s 1/%d ★" % [Loc.t("common.level"), max_lv])
		var header := Label.new()
		header.text = "%s  [%s · %s]" % [
			Loc.t(str(cfg.get("name_key", mid))),
			lv_tag,
			Loc.t("draft.rarity." + rarity)
		]
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", border_col.lightened(0.25))
		text_col.add_child(header)

		var desc := Label.new()
		desc.text = Loc.t(str(cfg.get("desc_key", "")))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 15)
		text_col.add_child(desc)

		if not syn_id.is_empty():
			var scfg: Dictionary = ConfigDB.synergies.get(syn_id, {})
			var syn_lbl := Label.new()
			syn_lbl.text = "★ %s %s!" % [Loc.t("draft.synergy_ready"), Loc.t(str(scfg.get("name_key", syn_id)))]
			syn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			syn_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.36))
			syn_lbl.add_theme_font_size_override("font_size", 15)
			text_col.add_child(syn_lbl)

		pad.minimum_size_changed.connect(func() -> void:
			if is_instance_valid(btn) and is_instance_valid(pad):
				btn.custom_minimum_size.y = maxf(126.0, pad.get_combined_minimum_size().y + 12.0)
		)
		_cards_box.add_child(btn)
		btn.custom_minimum_size.y = maxf(126.0, pad.get_combined_minimum_size().y + 12.0)

	_refresh_reroll_button()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or App.state != App.State.MUTATION_DRAFT or arena == null:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var idx := -1
			if ke.keycode == KEY_1 or ke.keycode == KEY_KP_1:
				idx = 0
			elif ke.keycode == KEY_2 or ke.keycode == KEY_KP_2:
				idx = 1
			elif ke.keycode == KEY_3 or ke.keycode == KEY_KP_3:
				idx = 2
			if idx >= 0 and idx < _cards_box.get_child_count():
				var card_btn := _cards_box.get_child(idx) as Button
				if card_btn != null:
					card_btn.pressed.emit()
					get_viewport().set_input_as_handled()


func _refresh_reroll_button() -> void:
	if arena != null and arena.free_rerolls_left > 0:
		_reroll_btn.visible = true
		_reroll_btn.disabled = false
		_reroll_btn.text = Loc.t("draft.free_reroll")
	elif Ads.can_offer(Ads.PLACEMENT_EXTRA_MUTATION):
		_reroll_btn.visible = true
		_reroll_btn.disabled = false
		_reroll_btn.text = Loc.t("draft.ad_reroll")
	else:
		_reroll_btn.visible = false


func _on_reroll_pressed() -> void:
	Audio.play_sfx("button_click")
	if arena == null:
		return
	if arena.free_rerolls_left > 0:
		arena.reroll_draft_choices()
	else:
		arena.reroll_draft_with_ad(func(_ok: bool, _r: String) -> void:
			_refresh_reroll_button()
		)
