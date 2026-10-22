class_name MenuScreens
extends Control
## Implements all out-of-run mobile UI screens cleanly and adaptively:
## - Screen 1: Главный экран (Main Menu with animated living Slime preview)
## - Screen 2: Выбор режима (Mode Select + Form selector)
## - Screen 8: Постоянные улучшения (Upgrades, Unlock Mutations, Achievements)
## - Screen 9: Коллекция существ (Bestiary Codex + Slime Forms & Trails)
## - Screen 10: Настройки (SFX/Music, Fixed/Floating Joystick, Auto-Absorb, FX Quality, RU/EN, Consent, Restore)
## - Screen 11: Магазин (Fair Non-P2W Store: No Ads, Cosmetic Skins, Decorative FX)
## - Screen 12: Политика конфиденциальности и информация о приложении

signal start_run_requested(mode_id: String)

enum Page {
	HOME,
	MODE_SELECT,
	UPGRADES,
	COLLECTION,
	SETTINGS,
	SHOP,
	PRIVACY
}

var current_page: Page = Page.HOME
var _upg_tab: int = 0
var _col_tab: int = 0

var _essence_lbl: Label
var _page_container: MarginContainer
var _hero_slime_holder: Control
var _hero_slime: SlimeVisual


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := load("res://shaders/forest_canopy.gdshader") as Shader
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		bg.material = mat
	else:
		bg.color = Color(0.06, 0.14, 0.17)
	add_child(bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	# Top persistent Essence header bar
	var top_bar := MarginContainer.new()
	top_bar.add_theme_constant_override("margin_left", 20)
	top_bar.add_theme_constant_override("margin_right", 20)
	top_bar.add_theme_constant_override("margin_top", 18)
	root_vbox.add_child(top_bar)

	var top_h := HBoxContainer.new()
	top_bar.add_child(top_h)

	var brand := Label.new()
	brand.text = "SLIME RUSH"
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", Color(0.62, 0.95, 0.84))
	top_h.add_child(brand)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(spacer)

	_essence_lbl = Label.new()
	_essence_lbl.add_theme_font_size_override("font_size", 20)
	_essence_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.84))
	top_h.add_child(_essence_lbl)

	_page_container = MarginContainer.new()
	_page_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_container.add_theme_constant_override("margin_left", 22)
	_page_container.add_theme_constant_override("margin_right", 22)
	_page_container.add_theme_constant_override("margin_top", 10)
	_page_container.add_theme_constant_override("margin_bottom", 24)
	root_vbox.add_child(_page_container)

	Events.locale_changed.connect(func(_l: String) -> void: show_page(current_page))
	Billing.purchase_succeeded.connect(func(_s: String) -> void: show_page(current_page))
	Billing.purchases_restored.connect(func(_r: Array[String]) -> void: show_page(current_page))

	show_page(Page.HOME)


func show_page(page: Page) -> void:
	current_page = page
	_essence_lbl.text = "%s: ✦ %d" % [Loc.t("common.essence"), SaveData.get_essence()]
	for ch in _page_container.get_children():
		ch.queue_free()

	match page:
		Page.HOME:
			_build_home_page()
		Page.MODE_SELECT:
			_build_mode_select_page()
		Page.UPGRADES:
			_build_upgrades_page()
		Page.COLLECTION:
			_build_collection_page()
		Page.SETTINGS:
			_build_settings_page()
		Page.SHOP:
			_build_shop_page()
		Page.PRIVACY:
			_build_privacy_page()


func _make_header_with_back(title_text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var back_btn := Button.new()
	back_btn.text = "← " + Loc.t("common.back")
	back_btn.custom_minimum_size = Vector2(120, 50)
	back_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		show_page(Page.HOME)
	)
	hb.add_child(back_btn)

	var lbl := Label.new()
	lbl.text = title_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	hb.add_child(lbl)
	return hb


func _build_home_page() -> void:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	_page_container.add_child(vb)

	var title := Label.new()
	title.text = Loc.t("app.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.68, 1.0, 0.88))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = Loc.t("app.subtitle")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	vb.add_child(sub)

	# Animated interactive Slime mascot preview
	_hero_slime_holder = Control.new()
	_hero_slime_holder.custom_minimum_size = Vector2(0, 175)
	vb.add_child(_hero_slime_holder)
	_hero_slime = SlimeVisual.new()
	_hero_slime.radius = 48.0
	_hero_slime_holder.add_child(_hero_slime)
	_hero_slime_holder.resized.connect(func() -> void:
		if is_instance_valid(_hero_slime):
			_hero_slime.position = _hero_slime_holder.size * 0.5
	)
	_hero_slime.position = Vector2(338, 88)

	var play_btn := Button.new()
	play_btn.name = "PlayButton"
	play_btn.text = Loc.t("menu.play")
	play_btn.custom_minimum_size = Vector2(0, 68)
	UIThemeBuilder.style_primary_cta(play_btn)
	play_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		App.change_state(App.State.MODE_SELECT)
		show_page(Page.MODE_SELECT)
	)
	vb.add_child(play_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)

	var nav_items := [
		["menu.upgrades", Page.UPGRADES],
		["menu.collection", Page.COLLECTION],
		["menu.shop", Page.SHOP],
		["menu.settings", Page.SETTINGS]
	]
	for entry in nav_items:
		var nb := Button.new()
		nb.text = Loc.t(str(entry[0]))
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 58)
		var target_page: Page = entry[1]
		nb.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			show_page(target_page)
		)
		grid.add_child(nb)

	var priv_btn := Button.new()
	priv_btn.text = Loc.t("menu.privacy")
	priv_btn.custom_minimum_size = Vector2(0, 48)
	priv_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		show_page(Page.PRIVACY)
	)
	vb.add_child(priv_btn)


func _build_mode_select_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("mode.title")))

	for mode_info in [
		["standard", "mode.standard.name", "mode.standard.desc"],
		["quick", "mode.quick.name", "mode.quick.desc"]
	]:
		var mid: String = mode_info[0]
		var card := PanelContainer.new()
		vb.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		var mtitle := Label.new()
		mtitle.text = Loc.t(mode_info[1])
		mtitle.add_theme_font_size_override("font_size", 22)
		mtitle.add_theme_color_override("font_color", Color(0.62, 1.0, 0.86))
		cv.add_child(mtitle)

		var mdesc := Label.new()
		mdesc.text = Loc.t(mode_info[2])
		mdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mdesc.add_theme_font_size_override("font_size", 16)
		cv.add_child(mdesc)

		var start_btn := Button.new()
		start_btn.text = Loc.t("mode.start_btn")
		start_btn.custom_minimum_size = Vector2(0, 56)
		UIThemeBuilder.style_primary_cta(start_btn)
		start_btn.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			start_run_requested.emit(mid)
		)
		cv.add_child(start_btn)

	# Quick Slime Form Selector
	var form_lbl := Label.new()
	form_lbl.text = Loc.t("mode.select_form")
	form_lbl.add_theme_font_size_override("font_size", 18)
	vb.add_child(form_lbl)

	var form_row := HFlowContainer.new()
	form_row.add_theme_constant_override("h_separation", 8)
	form_row.add_theme_constant_override("v_separation", 8)
	vb.add_child(form_row)
	var unlocked_forms: Array = SaveData.data.get("unlocked_forms", ["forest_drop"])
	var cur_form := str(SaveData.data.get("selected_form", "forest_drop"))
	for fid in unlocked_forms:
		var fcfg: Dictionary = ConfigDB.slime_forms.get(str(fid), {})
		var fb := Button.new()
		var fname := Loc.t(str(fcfg.get("name_key", fid)))
		fb.text = ("✓ " + fname) if str(fid) == cur_form else fname
		fb.custom_minimum_size = Vector2(130, 48)
		fb.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			SaveData.select_form(str(fid))
			show_page(Page.MODE_SELECT)
		)
		form_row.add_child(fb)


func _build_upgrades_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("upgrades.title")))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for idx in range(3):
		var keys := ["upgrades.tab_stats", "upgrades.tab_mutations", "upgrades.tab_achievements"]
		var tb := Button.new()
		tb.text = Loc.t(keys[idx])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 48)
		if idx == _upg_tab:
			UIThemeBuilder.style_primary_cta(tb)
			tb.add_theme_font_size_override("font_size", 16)
		var captured := idx
		tb.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			_upg_tab = captured
			show_page(Page.UPGRADES)
		)
		tabs.add_child(tb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	if _upg_tab == 0:
		for uid in ConfigDB.upgrade_order:
			var cfg: Dictionary = ConfigDB.upgrades[uid]
			var lv := SaveData.get_upgrade_level(uid)
			var max_lv: int = int(cfg.get("max_level", 8))
			var cost := ConfigDB.get_upgrade_cost(uid, lv)
			var card := PanelContainer.new()
			list.add_child(card)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			card.add_child(hb)

			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			var nl := Label.new()
			nl.text = "%s (%s %d/%d)" % [Loc.t(str(cfg["name_key"])), Loc.t("common.level"), lv, max_lv]
			nl.add_theme_font_size_override("font_size", 19)
			info.add_child(nl)
			var dl := Label.new()
			dl.text = Loc.t(str(cfg["desc_key"]))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 15)
			info.add_child(dl)

			var buy := Button.new()
			buy.custom_minimum_size = Vector2(130, 54)
			if lv >= max_lv:
				buy.text = Loc.t("common.max")
				buy.disabled = true
			else:
				buy.text = "✦ %d" % cost
				buy.disabled = SaveData.get_essence() < cost
			buy.pressed.connect(func() -> void:
				if SaveData.buy_upgrade(uid):
					Audio.play_sfx("mutation_pick")
					show_page(Page.UPGRADES)
			)
			hb.add_child(buy)

	elif _upg_tab == 1:
		for mid in ConfigDB.mutation_order:
			var mcfg := ConfigDB.get_mutation(mid)
			var unlocked := SaveData.is_mutation_unlocked(mid)
			var cost: int = int(mcfg.get("unlock_cost", 0))
			if bool(mcfg.get("unlocked_by_default", true)):
				continue
			var card := PanelContainer.new()
			list.add_child(card)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			card.add_child(hb)

			var tex := AssetRegistry.get_texture(str(mcfg.get("icon", "")))
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = Vector2(56, 56)
				hb.add_child(tr)

			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			var nl := Label.new()
			nl.text = Loc.t(str(mcfg["name_key"]))
			nl.add_theme_font_size_override("font_size", 19)
			info.add_child(nl)
			var dl := Label.new()
			dl.text = Loc.t(str(mcfg["desc_key"]))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 15)
			info.add_child(dl)

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(130, 52)
			if unlocked:
				btn.text = Loc.t("common.unlocked")
				btn.disabled = true
			else:
				btn.text = "✦ %d" % cost
				btn.disabled = SaveData.get_essence() < cost
			btn.pressed.connect(func() -> void:
				if SaveData.unlock_mutation(mid):
					Audio.play_sfx("evolution")
					show_page(Page.UPGRADES)
			)
			hb.add_child(btn)

	else:
		var unlocked_ach: Array = SaveData.data.get("achievements", [])
		for aid in ConfigDB.achievement_order:
			var acfg: Dictionary = ConfigDB.achievements[aid]
			var done := unlocked_ach.has(aid)
			var card := PanelContainer.new()
			list.add_child(card)
			var hb := HBoxContainer.new()
			card.add_child(hb)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			var nl := Label.new()
			nl.text = ("%s ✓" if done else "%s") % Loc.t(str(acfg["name_key"]))
			nl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.80) if done else Color(0.85, 0.92, 0.90))
			info.add_child(nl)
			var dl := Label.new()
			dl.text = "%s (+✦%d)" % [Loc.t(str(acfg["desc_key"])), int(acfg.get("reward_essence", 0))]
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 15)
			info.add_child(dl)


func _build_collection_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("collection.title")))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for idx in range(2):
		var keys := ["collection.tab_creatures", "collection.tab_forms"]
		var tb := Button.new()
		tb.text = Loc.t(keys[idx])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 48)
		if idx == _col_tab:
			UIThemeBuilder.style_primary_cta(tb)
			tb.add_theme_font_size_override("font_size", 16)
		var cap := idx
		tb.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			_col_tab = cap
			show_page(Page.COLLECTION)
		)
		tabs.add_child(tb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	if _col_tab == 0:
		var all_ids: Array[String] = ConfigDB.enemy_order.duplicate()
		all_ids.append("umbral_alpha")
		all_ids.append("ancient_guardian")
		for cid in all_ids:
			var cfg := ConfigDB.get_enemy(cid)
			var seen_cnt := SaveData.get_creature_count(cid)
			var card := PanelContainer.new()
			list.add_child(card)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			card.add_child(hb)

			var tex := AssetRegistry.get_texture(str(cfg.get("icon", "")))
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.modulate = Color.WHITE if seen_cnt > 0 else Color(0.15, 0.20, 0.22, 0.85)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = Vector2(58, 58)
				hb.add_child(tr)

			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			var nl := Label.new()
			nl.text = Loc.t(str(cfg["name_key"])) if seen_cnt > 0 else Loc.t("collection.unknown")
			nl.add_theme_font_size_override("font_size", 19)
			info.add_child(nl)
			var dl := Label.new()
			dl.text = ("%s\n%s" % [Loc.t(str(cfg["desc_key"])), Loc.t("collection.seen_count", {"count": seen_cnt})]) if seen_cnt > 0 else Loc.t("collection.unknown_desc")
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 14)
			info.add_child(dl)
	else:
		var unlocked_forms: Array = SaveData.data.get("unlocked_forms", ["forest_drop"])
		var cur_form := str(SaveData.data.get("selected_form", "forest_drop"))
		for fid in ConfigDB.form_order:
			var fcfg: Dictionary = ConfigDB.slime_forms[fid]
			var is_un := unlocked_forms.has(fid)
			var card := PanelContainer.new()
			list.add_child(card)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			card.add_child(hb)

			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(46, 46)
			swatch.color = Color(str(fcfg.get("body_color", "#22d0a8")))
			hb.add_child(swatch)

			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			var nl := Label.new()
			nl.text = Loc.t(str(fcfg["name_key"]))
			info.add_child(nl)
			var dl := Label.new()
			dl.text = Loc.t(str(fcfg["desc_key"]))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 14)
			info.add_child(dl)

			var act := Button.new()
			act.custom_minimum_size = Vector2(130, 50)
			if is_un:
				act.text = Loc.t("common.equipped") if fid == cur_form else Loc.t("common.select")
				act.disabled = (fid == cur_form)
				act.pressed.connect(func() -> void:
					Audio.play_sfx("button_click")
					SaveData.select_form(fid)
					show_page(Page.COLLECTION)
				)
			elif str(fcfg.get("unlock_type", "")) == "essence":
				var c: int = int(fcfg.get("essence_cost", 60))
				act.text = "✦ %d" % c
				act.disabled = SaveData.get_essence() < c
				act.pressed.connect(func() -> void:
					if SaveData.unlock_form_with_essence(fid):
						SaveData.select_form(fid)
						Audio.play_sfx("evolution")
						show_page(Page.COLLECTION)
				)
			else:
				act.text = Loc.t("common.locked")
				act.disabled = true
			hb.add_child(act)


func _build_settings_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("settings.title")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	# SFX Volume
	var sfx_lbl := Label.new()
	sfx_lbl.text = "%s: %d%%" % [Loc.t("settings.sfx"), int(round(float(SaveData.get_setting("sfx_volume", 0.85)) * 100.0))]
	list.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = float(SaveData.get_setting("sfx_volume", 0.85))
	sfx_slider.value_changed.connect(func(v: float) -> void:
		SaveData.set_setting("sfx_volume", v)
		sfx_lbl.text = "%s: %d%%" % [Loc.t("settings.sfx"), int(round(v * 100.0))]
	)
	list.add_child(sfx_slider)

	# Music Toggle (OFF by default per Section 12!) & Music Volume
	var mus_chk := CheckButton.new()
	mus_chk.text = Loc.t("settings.music_toggle")
	mus_chk.button_pressed = bool(SaveData.get_setting("music_enabled", false))
	mus_chk.toggled.connect(func(on: bool) -> void:
		SaveData.set_setting("music_enabled", on)
	)
	list.add_child(mus_chk)

	var mus_slider := HSlider.new()
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = float(SaveData.get_setting("music_volume", 0.55))
	mus_slider.value_changed.connect(func(v: float) -> void:
		SaveData.set_setting("music_volume", v)
	)
	list.add_child(mus_slider)

	# Joystick Mode (Fixed vs Floating)
	var jmode := str(SaveData.get_setting("joystick_mode", "floating"))
	var joy_btn := Button.new()
	joy_btn.custom_minimum_size = Vector2(0, 52)
	joy_btn.text = "%s: %s" % [Loc.t("settings.joystick"), Loc.t("settings.joystick." + jmode)]
	joy_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		SaveData.set_setting("joystick_mode", "fixed" if jmode == "floating" else "floating")
		show_page(Page.SETTINGS)
	)
	list.add_child(joy_btn)

	# Auto-absorb toggle
	var auto_chk := CheckButton.new()
	auto_chk.text = Loc.t("settings.auto_absorb")
	auto_chk.button_pressed = bool(SaveData.get_setting("auto_absorb", true))
	auto_chk.toggled.connect(func(on: bool) -> void:
		SaveData.set_setting("auto_absorb", on)
	)
	list.add_child(auto_chk)

	# FX Quality cycle
	var fxq := str(SaveData.get_setting("fx_quality", "high"))
	var fx_btn := Button.new()
	fx_btn.custom_minimum_size = Vector2(0, 52)
	fx_btn.text = "%s: %s" % [Loc.t("settings.fx_quality"), Loc.t("settings.fx." + fxq)]
	fx_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		var order := ["low", "medium", "high"]
		var nxt: String = order[(order.find(fxq) + 1) % order.size()]
		SaveData.set_setting("fx_quality", nxt)
		show_page(Page.SETTINGS)
	)
	list.add_child(fx_btn)

	# Language RU / EN switch
	var cur_loc := Loc.current_locale
	var lang_btn := Button.new()
	lang_btn.custom_minimum_size = Vector2(0, 52)
	lang_btn.text = "%s: %s" % [Loc.t("settings.language"), "Русский" if cur_loc == "ru" else "English"]
	lang_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		SaveData.set_setting("locale", "en" if cur_loc == "ru" else "ru")
	)
	list.add_child(lang_btn)

	# Privacy-friendly Analytics Consent
	var consent_chk := CheckButton.new()
	consent_chk.text = Loc.t("settings.consent")
	consent_chk.button_pressed = bool(SaveData.get_setting("analytics_consent", false))
	consent_chk.toggled.connect(func(on: bool) -> void:
		SaveData.set_setting("analytics_consent", on)
	)
	list.add_child(consent_chk)

	# Restore IAP
	var rest_btn := Button.new()
	rest_btn.custom_minimum_size = Vector2(0, 52)
	rest_btn.text = Loc.t("settings.restore_iap")
	rest_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		Billing.restore_purchases()
	)
	list.add_child(rest_btn)


func _build_shop_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("shop.title")))

	var sub := Label.new()
	sub.text = Loc.t("shop.subtitle")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.68, 0.96, 0.85))
	vb.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for sku in ConfigDB.store_order:
		var item: Dictionary = ConfigDB.store_catalog[sku]
		var owned := Billing.is_sku_owned(sku)
		var card := PanelContainer.new()
		list.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		var nl := Label.new()
		nl.text = Loc.t(str(item["name_key"]))
		nl.add_theme_font_size_override("font_size", 20)
		nl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.50) if sku.ends_with("no_ads") else Color(0.68, 1.0, 0.88))
		cv.add_child(nl)

		var dl := Label.new()
		dl.text = Loc.t(str(item["desc_key"]))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_font_size_override("font_size", 15)
		cv.add_child(dl)

		var buy_btn := Button.new()
		buy_btn.custom_minimum_size = Vector2(0, 52)
		if owned:
			buy_btn.text = Loc.t("common.owned")
			buy_btn.disabled = true
		else:
			buy_btn.text = "%s — %s" % [Loc.t("common.buy"), Billing.get_display_price(sku)]
			buy_btn.disabled = not Billing.is_store_available()
		buy_btn.pressed.connect(func() -> void:
			Audio.play_sfx("button_click")
			Billing.purchase_sku(sku)
		)
		cv.add_child(buy_btn)

	var restore_btn := Button.new()
	restore_btn.custom_minimum_size = Vector2(0, 50)
	restore_btn.text = Loc.t("shop.restore")
	restore_btn.pressed.connect(func() -> void:
		Audio.play_sfx("button_click")
		Billing.restore_purchases()
	)
	vb.add_child(restore_btn)


func _build_privacy_page() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_page_container.add_child(vb)
	vb.add_child(_make_header_with_back(Loc.t("privacy.title")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)

	var card_vb := VBoxContainer.new()
	card_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_vb.add_theme_constant_override("separation", 14)
	card.add_child(card_vb)

	var body := Label.new()
	body.text = Loc.t("privacy.body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	card_vb.add_child(body)

	var privacy_options := Button.new()
	privacy_options.text = "Настройки рекламной конфиденциальности" if Loc.current_locale == "ru" else "Ad privacy choices"
	privacy_options.custom_minimum_size.y = 56
	privacy_options.pressed.connect(Ads.show_privacy_options)
	card_vb.add_child(privacy_options)

	var license_button := Button.new()
	license_button.text = "Лицензия Godot (MIT)" if Loc.current_locale == "ru" else "Godot license (MIT)"
	license_button.custom_minimum_size.y = 56
	card_vb.add_child(license_button)
	var license_text := Label.new()
	license_text.text = FileAccess.get_file_as_string("res://licenses/GODOT_LICENSE.txt")
	license_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	license_text.add_theme_font_size_override("font_size", 14)
	license_text.visible = false
	card_vb.add_child(license_text)
	license_button.pressed.connect(func() -> void: license_text.visible = not license_text.visible)
