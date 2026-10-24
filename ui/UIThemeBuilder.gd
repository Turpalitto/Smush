class_name UIThemeBuilder
extends RefCounted
## Generates a cohesive, high-contrast mobile UI Theme for SLIME RUSH: EVOLUTION.


static func make_box(bg: Color, border: Color, radius: int = 16, border_w: int = 2, pad_h: int = 16, pad_v: int = 12,
		glow: Color = Color.TRANSPARENT, glow_size: int = 0) -> StyleBoxFlat:
	## `glow` draws a soft coloured halo outside the border. StyleBoxFlat cannot hold
	## a gradient, so the only way to make a card look lit rather than pasted on is
	## its shadow: same colour as the border, zero offset, large blur.
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	if glow_size > 0 and glow.a > 0.001:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
		sb.shadow_offset = Vector2.ZERO
	return sb


static func build_theme() -> Theme:
	var th := Theme.new()
	var custom_font := AssetRegistry.get_ui_font()
	if custom_font != null:
		th.default_font = custom_font
	th.default_font_size = 20

	var btn_normal := make_box(Color(0.09, 0.24, 0.26, 0.94), Color(0.34, 0.90, 0.74, 0.86), 16, 2, 20, 14,
		Color(0.16, 0.78, 0.64, 0.18), 8)
	var btn_hover := make_box(Color(0.14, 0.34, 0.35, 0.98), Color(0.58, 1.0, 0.86, 1.0), 16, 2, 20, 14,
		Color(0.28, 0.95, 0.78, 0.28), 10)
	var btn_pressed := make_box(Color(0.07, 0.18, 0.20, 1.0), Color(0.75, 1.0, 0.90, 1.0), 16, 3, 20, 14,
		Color(0.24, 0.90, 0.74, 0.22), 6)
	var btn_disabled := make_box(Color(0.10, 0.15, 0.17, 0.72), Color(0.26, 0.34, 0.36, 0.48), 16, 1, 20, 14)

	th.set_stylebox("normal", "Button", btn_normal)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("focus", "Button", btn_hover)
	th.set_stylebox("disabled", "Button", btn_disabled)
	th.set_color("font_color", "Button", Color(0.95, 1.0, 0.98))
	th.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	th.set_color("font_disabled_color", "Button", Color(0.52, 0.60, 0.62))

	var panel_sb := make_box(Color(0.05, 0.12, 0.15, 0.94), Color(0.28, 0.74, 0.62, 0.74), 20, 2, 18, 18,
		Color(0.02, 0.06, 0.08, 0.50), 12)
	th.set_stylebox("panel", "PanelContainer", panel_sb)

	var bar_bg := make_box(Color(0.04, 0.09, 0.11, 0.88), Color(0.24, 0.56, 0.50, 0.72), 10, 1, 2, 2,
		Color(0.01, 0.04, 0.05, 0.45), 5)
	var bar_fill := make_box(Color(0.22, 0.90, 0.68, 0.95), Color(0.75, 1.0, 0.90, 0.35), 10, 1, 2, 2)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)

	th.set_color("font_color", "Label", Color(0.93, 0.99, 0.97))
	return th


static func style_primary_cta(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", make_box(Color(0.13, 0.66, 0.50, 0.98), Color(0.72, 1.0, 0.88, 1.0), 18, 3, 24, 16,
		Color(0.22, 0.95, 0.74, 0.32), 12))
	btn.add_theme_stylebox_override("hover", make_box(Color(0.18, 0.78, 0.60, 1.0), Color(0.88, 1.0, 0.94, 1.0), 18, 3, 24, 16,
		Color(0.32, 1.0, 0.82, 0.40), 14))
	btn.add_theme_stylebox_override("pressed", make_box(Color(0.10, 0.54, 0.42, 1.0), Color(0.85, 1.0, 0.92, 1.0), 18, 3, 24, 16,
		Color(0.22, 0.90, 0.72, 0.25), 8))
	btn.add_theme_font_size_override("font_size", 24)
