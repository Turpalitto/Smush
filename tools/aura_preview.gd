extends Node2D
## Renders the growth regalia alone, at 4x, on a flat stand-in body.
##
## Judging ornaments from a gameplay capture does not work: the floor, the props,
## the enemies and the screen grade all sit behind them, so "the crown reads as a
## wire basket" is a guess rather than an observation. This scene strips everything
## else away and draws the same SlimeAura instances the game uses, at a radius big
## enough to see the actual polygons.
##
##   AURA_OUT    output PNG (required)
##   AURA_STAGE  stage 1..15 (default 15)
##   AURA_SIZE   WxH (default 720x720)

const OUT_ENV := "AURA_OUT"
const STAGE_ENV := "AURA_STAGE"
const SIZE_ENV := "AURA_SIZE"
const RADIUS := 132.0


func _ready() -> void:
	var out_path := OS.get_environment(OUT_ENV)
	if out_path.is_empty():
		push_error("AURA_OUT is not set")
		get_tree().quit(2)
		return
	var stage := int(OS.get_environment(STAGE_ENV)) if not OS.get_environment(STAGE_ENV).is_empty() else 15
	stage = clampi(stage, 1, EvolutionStages.COUNT)
	var size_spec := OS.get_environment(SIZE_ENV)
	var w := 720
	var h := 720
	if not size_spec.is_empty():
		var parts := size_spec.split("x")
		if parts.size() == 2:
			w = int(parts[0])
			h = int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))

	# A viewport clear colour instead of a ColorRect: a Control child of a moved
	# Node2D lands half off the frame, which wasted two iterations of judging the
	# ornaments against a broken backdrop.
	RenderingServer.set_default_clear_color(Color("#2c4034"))

	var look: Dictionary = EvolutionStages.look_at(float(stage))
	var back := SlimeAura.new()
	back.front = false
	add_child(back)
	var body := BodyStandIn.new()
	body.look = look
	body.radius = RADIUS
	add_child(body)
	var front := SlimeAura.new()
	front.front = true
	add_child(front)

	position = Vector2(w * 0.5, h * 0.5 + 20.0)
	back.set_look(look, RADIUS, 1.7, 1.0)
	front.set_look(look, RADIUS, 1.7, 1.0)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image")
		get_tree().quit(4)
		return
	var err := img.save_png(out_path)
	print("AURA_PREVIEW %s stage=%d err=%d" % [out_path, stage, err])
	get_tree().quit(0 if err == OK else 5)


class BodyStandIn extends Node2D:
	## A flat disc with the stage body colour and a rim, so the ornaments are judged
	## against the same value range they will actually sit on.
	var look: Dictionary = {}
	var radius: float = 100.0

	func _draw() -> void:
		if look.is_empty():
			return
		var body: Color = look["body_c"]
		var rim: Color = look["rim_c"]
		var core: Color = look["core_c"]
		draw_circle(Vector2(0.0, radius * 0.10), radius * 0.98,
			Color(0.02, 0.05, 0.04, 0.30))
		draw_circle(Vector2.ZERO, radius, body)
		for i in range(6):
			var k := 1.0 - float(i) / 7.0
			draw_circle(Vector2.ZERO, radius * k,
				Color(core.r, core.g, core.b, 0.05))
		draw_arc(Vector2.ZERO, radius * 0.96, 0.0, TAU, 64,
			Color(rim.r, rim.g, rim.b, 0.55), radius * 0.07)
		# Eyes, so the crown has a face to sit above.
		for sx in [-1.0, 1.0]:
			var p := Vector2(sx * radius * 0.33, -radius * 0.10)
			draw_circle(p, radius * 0.18, Color(0.06, 0.09, 0.12))
			draw_circle(p + Vector2(-radius * 0.05, -radius * 0.06), radius * 0.07,
				Color(1.0, 1.0, 1.0, 0.85))
