class_name MutationDraftOverlay
extends Control
## Screen 4: Mutation Choice Modal presenting 3 weighted-random mutations,
## synergy completion preview badges, and optional 1x Reroll (No Ads free or Rewarded Ad).
##
## The modal sits on a frosted pane rather than a flat wash (see
## shaders/draft_glass.gdshader), and each card flies up into place over
## CARD_FLY_SEC with a short stagger, so the choice arrives instead of blinking
## into existence. Both are timing constants, not magic numbers, because the
## tests assert on them.

## Seconds a single card takes to travel from CARD_FLY_OFFSET to its slot.
const CARD_FLY_SEC: float = 0.22
## Extra delay per card index. Three cards therefore settle by 0.31 s.
const CARD_STAGGER_SEC: float = 0.045
## Pixels a card starts below its final slot. Far enough to read as motion,
## small enough that the text is never outside the card's own footprint.
const CARD_FLY_OFFSET: float = 46.0
const CARD_FLY_SCALE: float = 0.92
const GLASS_FADE_SEC: float = 0.18
const MIN_CARD_H: float = 126.0

## Opaque enough that body text keeps its contrast even when the blurred forest
## behind it is bright: measured against the lightest backdrop the glass can
## produce, not against a typical one.
const CARD_BG: Color = Color(0.072, 0.148, 0.178, 0.94)
const RARITY_COMMON: Color = Color(0.35, 0.85, 0.72)
const RARITY_RARE: Color = Color(0.38, 0.75, 1.0)
const RARITY_EPIC: Color = Color(0.88, 0.52, 1.0)

## Pane tint and how much of the world survives it. Pushed onto the material in
## _ready rather than left to the shader's own defaults, because
## ShaderMaterial.get_shader_parameter() returns null for a parameter that was
## never set — it does not fall back to the value declared in the shader. Anything
## that wants to read the pane's actual settings at runtime (the readability test,
## the QUICK_CAPTURE_GLASS sweep) would otherwise be reading null.
const GLASS_TINT: Color = Color(0.030, 0.078, 0.098)
const GLASS_TRANSMISSION: float = 0.30

var arena: ArenaController = null

var _glass: ColorRect
var _title_lbl: Label
var _cards_box: VBoxContainer
var _reroll_btn: Button
var _cards: Array[Button] = []
var _glass_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	_glass = ColorRect.new()
	_glass.name = "DraftGlass"
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The shader writes every pixel of the pane, so the ColorRect's own colour is
	# only a carrier; modulate.a is what the open animation fades.
	_glass.color = Color.WHITE
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/draft_glass.gdshader") as Shader
	mat.set_shader_parameter("glass_tint", GLASS_TINT)
	mat.set_shader_parameter("transmission", GLASS_TRANSMISSION)
	_glass.material = mat
	_glass.modulate.a = 0.0
	add_child(_glass)

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
	# A dark outline because the title now sits on translucent glass: over a bright
	# patch of blurred forest a bare mint label was legible only by luck.
	_title_lbl.add_theme_constant_override("outline_size", 5)
	_title_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.85))
	center.add_child(_title_lbl)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	center.add_child(_cards_box)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(0, 52)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	center.add_child(_reroll_btn)

	Events.mutation_draft_requested.connect(_populate_choices)
	Events.game_state_changed.connect(_on_state_changed)
	# The open animation hangs off visibility rather than off the state signal, so
	# the standalone draft preview tool (tools/draft_preview.gd) gets the same
	# frost-in as the real draft instead of a permanently invisible pane.
	visibility_changed.connect(_on_visibility_changed)


func bind_arena(p_arena: ArenaController) -> void:
	arena = p_arena


# --- Palette -----------------------------------------------------------------
# Pure functions rather than inline constants so the readability test measures
# the colours the overlay actually paints, instead of a copy of them.

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":
			return RARITY_RARE
		"epic":
			return RARITY_EPIC
	return RARITY_COMMON


static func card_background(rarity: String) -> Color:
	return CARD_BG.lerp(rarity_color(rarity), 0.10)


static func card_header_color(rarity: String) -> Color:
	return rarity_color(rarity).lightened(0.25)


func card_count() -> int:
	return _cards.size()


func card_at(index: int) -> Button:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


func glass_rect() -> ColorRect:
	return _glass


# --- Open / close ------------------------------------------------------------

func _on_state_changed(_old: int, new_st: int) -> void:
	visible = new_st == App.State.MUTATION_DRAFT


func _on_visibility_changed() -> void:
	if visible:
		_play_open_animation()
	else:
		if _glass_tween != null and _glass_tween.is_valid():
			_glass_tween.kill()
		_glass.modulate.a = 0.0


func _play_open_animation() -> void:
	## The pane frosts in over GLASS_FADE_SEC instead of appearing at full
	## strength. Fading a screen-texture quad blends the blurred pane against the
	## sharp frame underneath, which reads as ice crystallising over the world.
	_glass.modulate.a = 0.0
	if _glass_tween != null and _glass_tween.is_valid():
		_glass_tween.kill()
	_glass_tween = create_tween()
	_glass_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_glass_tween.tween_property(_glass, "modulate:a", 1.0, GLASS_FADE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _fly_in(btn: Button, wrap: Control, index: int) -> void:
	btn.modulate.a = 0.0
	btn.scale = Vector2.ONE * CARD_FLY_SCALE
	btn.position = Vector2(0.0, CARD_FLY_OFFSET)
	wrap.resized.connect(func() -> void:
		if is_instance_valid(btn):
			btn.size = wrap.size
			btn.pivot_offset = wrap.size * 0.5
	)
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# The stagger must be its own SEQUENTIAL step. Calling set_parallel(true)
	# before the interval puts the interval and the property tweens in one
	# parallel group, and all three cards then fly in lock-step — which is what
	# the first version did, measurably: every card sat at y=36.3, alpha=0.105.
	if index > 0:
		t.tween_interval(CARD_STAGGER_SEC * float(index))
	t.tween_property(btn, "position", Vector2.ZERO, CARD_FLY_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_parallel(true)
	t.tween_property(btn, "modulate:a", 1.0, CARD_FLY_SEC * 0.72)
	t.tween_property(btn, "scale", Vector2.ONE, CARD_FLY_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Content -----------------------------------------------------------------

func _populate_choices(choices: Array) -> void:
	_title_lbl.text = Loc.t("draft.title")
	for ch in _cards_box.get_children():
		# Remove immediately so chained drafts never show two sets of cards.
		_cards_box.remove_child(ch)
		ch.queue_free()
	_cards.clear()

	for idx in range(choices.size()):
		var item: Dictionary = choices[idx]
		var mid: String = str(item.get("id", ""))
		var cfg := ConfigDB.get_mutation(mid)
		var rarity: String = str(item.get("rarity", "common"))
		var cur_lv: int = int(item.get("current_level", 0))
		var next_lv: int = int(item.get("next_level", 1))
		var max_lv: int = int(item.get("max_level", 5))
		var syn_id: String = str(item.get("completes_synergy", ""))

		var border_col := rarity_color(rarity)
		var card_bg := card_background(rarity)
		var halo := Color(border_col.r, border_col.g, border_col.b, 0.20)
		var halo_hi := Color(border_col.r, border_col.g, border_col.b, 0.36)

		# The card lives inside a bare Control wrapper. VBoxContainer owns the
		# wrapper's slot and never touches the Button, so the fly-in can animate
		# position/scale without a layout pass fighting it back to zero — which is
		# exactly what happened when the Button was the direct container child.
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(0, MIN_CARD_H)
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards_box.add_child(wrap)

		var btn := Button.new()
		btn.add_theme_stylebox_override("normal",
			UIThemeBuilder.make_box(card_bg, border_col, 18, 3, 14, 12, halo, 9))
		btn.add_theme_stylebox_override("hover",
			UIThemeBuilder.make_box(card_bg.lightened(0.06), border_col.lightened(0.25), 18, 3, 14, 12, halo_hi, 15))
		btn.add_theme_stylebox_override("pressed",
			UIThemeBuilder.make_box(Color(0.06, 0.14, 0.17, 1.0), Color(0.85, 1.0, 0.92), 18, 3, 14, 12, halo_hi, 12))
		btn.pressed.connect(func() -> void:
			if arena != null:
				arena.select_draft_mutation(mid)
		)
		wrap.add_child(btn)
		# The wrapper's resize callback fits the card once layout resolves its
		# initial zero-width slot, avoiding the style's minimum-width overflow.
		btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_cards.append(btn)

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
		header.add_theme_color_override("font_color", card_header_color(rarity))
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
			if is_instance_valid(wrap) and is_instance_valid(pad):
				wrap.custom_minimum_size.y = maxf(MIN_CARD_H, pad.get_combined_minimum_size().y + 12.0)
		)
		wrap.custom_minimum_size.y = maxf(MIN_CARD_H, pad.get_combined_minimum_size().y + 12.0)

		_fly_in(btn, wrap, idx)

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
			if idx >= 0 and idx < _cards.size():
				var card_btn := _cards[idx]
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
