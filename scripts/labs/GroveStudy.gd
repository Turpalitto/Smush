class_name GroveStudy
extends Node2D
## Opt-in art study for ClaudeVisualLab. No gameplay, save or run dependencies.
const GLOW: Texture2D = preload("res://resources/effects/soft_glow.tres")
const NAMES := ["Мшистая роща", "Янтарная заводь", "Сумеречный сад"]
const FOOD_NAMES := ["Светящиеся капли", "Споры", "Минералы"]
const FOOD_COLORS := [Color("74f3cd"), Color("d6a0ef"), Color("edbb68")]
const PALETTES := [
	[Color("102b25"), Color("1b4538"), Color("61bda0")],
	[Color("29261a"), Color("49442a"), Color("d5b474")],
	[Color("151e36"), Color("283652"), Color("8dabe0")],
]
const PROPS := [
	["fern_cluster", "glow_shrooms", "broadleaf_clump", "root_pillar"],
	["grass_tuft", "bloom_bells", "fallen_branch", "ancient_lantern"],
	["glow_shrooms", "mana_crystal", "bloom_flower", "rune_stone"],
]
var mood: int = 0
var clock: float = 0.0
var _layer: CanvasLayer
var _floor: ColorRect
var _mat: ShaderMaterial
var _textures: Dictionary = {}


func _ready() -> void:
	z_index = -10
	_layer = CanvasLayer.new()
	_layer.layer = -10
	add_child(_layer)
	_floor = ColorRect.new()
	_floor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/forest_canopy.gdshader")
	ArenaController.apply_floor_texture(_mat, 0.35)
	_mat.set_shader_parameter("floor_tile_px", 1400.0)
	_floor.material = _mat
	_layer.add_child(_floor)
	for group in PROPS:
		for id in group:
			_textures[id] = AssetRegistry.get_texture(WorldGenerator.PROP_TEXTURES[id])
	set_mood(0)


func set_mood(index: int) -> void:
	mood = clampi(index, 0, NAMES.size() - 1)
	if _mat == null:
		return
	var p: Array = PALETTES[mood]
	_mat.set_shader_parameter("moss_dark", p[0])
	_mat.set_shader_parameter("moss_mid", p[1])
	_mat.set_shader_parameter("canopy_glow", p[2])
	_mat.set_shader_parameter("beam_warm", Vector3(p[2].r, p[2].g, p[2].b))
	queue_redraw()


func update_view(center: Vector2, zoom: float, growth: float, time: float) -> void:
	clock = time
	_mat.set_shader_parameter("world_offset", center)
	_mat.set_shader_parameter("camera_zoom", zoom)
	_mat.set_shader_parameter("view_size", get_viewport_rect().size)
	_mat.set_shader_parameter("growth", growth * 0.5)
	queue_redraw()


func _draw() -> void:
	# Fixed positions across moods; leave the character's silhouette clear.
	var col: Color = PALETTES[mood][2]
	for i in range(12):
		var angle := float(i) * 2.39996
		var distance := 180.0 + float(i % 4) * 92.0
		var pos := Vector2.from_angle(angle) * distance
		var tex: Texture2D = _textures.get(PROPS[mood][i % 4])
		if tex == null:
			continue
		var side := 72.0 + float(i % 3) * 22.0
		var sway := sin(clock * 0.65 + float(i)) * 0.018
		draw_set_transform(pos, sway)
		draw_texture_rect(GLOW, Rect2(-side * 0.7, -side * 0.4, side * 1.4, side), false,
			Color(col.r, col.g, col.b, 0.12))
		draw_texture_rect(tex, Rect2(Vector2(-side * 0.5, -side * 0.7), Vector2.ONE * side), false,
			Color.WHITE.lerp(col, 0.17))
	draw_set_transform(Vector2.ZERO)


class FoodEcho extends Node2D:
	## A small, bounded visual memory. Lower body only: eyes and core stay clear.
	const MAX_ECHOES := 6
	const LIFETIME := 18.0
	var visual: SlimeVisualClaude
	var echoes: Array[Dictionary] = []
	var clock: float = 0.0
	var _serial: int = 0

	func remember(kind: int) -> void:
		if kind < 0 or kind >= FOOD_COLORS.size():
			return
		echoes.append({"kind": kind, "age": 0.0, "phase": float(_serial) * 2.39996})
		_serial += 1
		if echoes.size() > MAX_ECHOES:
			echoes.pop_front()

	func advance(delta: float) -> void:
		clock += delta
		for echo in echoes:
			echo["age"] = float(echo["age"]) + delta
		for i in range(echoes.size() - 1, -1, -1):
			if float(echoes[i]["age"]) >= LIFETIME:
				echoes.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		if visual == null:
			return
		var r := visual.radius
		var opacity := visual.stealth_alpha * (1.0 - visual.death_progress)
		var count := mini(echoes.size(), 3 if visual.quality == 0 else MAX_ECHOES)
		for i in range(count):
			var echo := echoes[echoes.size() - 1 - i]
			var kind: int = echo["kind"]
			var age: float = echo["age"]
			var phase: float = echo["phase"]
			var fade := smoothstep(0.0, 0.6, age) * (1.0 - smoothstep(10.0, LIFETIME, age)) * opacity
			var col: Color = FOOD_COLORS[kind]
			var drift := sin(phase + clock * 0.23)
			var pos := Vector2(drift * 0.48,
				0.53 + cos(phase + clock * 0.27) * 0.07) * r + visual._lag * r * 0.12
			var size := r * (0.055 if kind == 0 else 0.08)
			draw_texture_rect(GLOW, Rect2(pos - Vector2.ONE * size * 2.5, Vector2.ONE * size * 5.0), false,
				Color(col.r, col.g, col.b, 0.35 * fade))
			if kind == 1:
				draw_arc(pos, size, 0.0, TAU, 12, Color(col.r, col.g, col.b, 0.62 * fade), 1.0, true)
			elif kind == 2:
				draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -size), pos + Vector2(size * 0.6, 0),
					pos + Vector2(0, size), pos - Vector2(size * 0.6, 0)]), Color(col.r, col.g, col.b, 0.7 * fade))
			else:
				draw_circle(pos, size, Color(col.r, col.g, col.b, 0.8 * fade), true, -1.0, true)
