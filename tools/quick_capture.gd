extends Node
## Fast single-frame capture for art iteration.
##
## The full automated playthrough takes ~5 minutes and writes 20+ screenshots;
## that is the wrong loop when tuning a texture. This tool boots the real game,
## walks it to a requested screen and saves one frame, so a visual change can be
## judged in ~10 seconds.
##
## Environment:
##   QUICK_CAPTURE_OUT      output PNG path (required)
##   QUICK_CAPTURE_STAGE    menu | arena   (default: arena)
##   QUICK_CAPTURE_SECONDS  arena time before the shot (default: 4)
##   QUICK_CAPTURE_SIZE     WxH, e.g. 720x1280 (default: keep project window)
##   QUICK_CAPTURE_SEED     world seed for the arena (default: 0 = random)
##   QUICK_CAPTURE_FLOOR    override floor layers, e.g. "relief=0,occlusion=0.4"
##   QUICK_CAPTURE_ZOOM     camera zoom override, to judge texture detail up close

const STAGE_ENV := "QUICK_CAPTURE_STAGE"
const OUT_ENV := "QUICK_CAPTURE_OUT"
const SECONDS_ENV := "QUICK_CAPTURE_SECONDS"
const SIZE_ENV := "QUICK_CAPTURE_SIZE"
const SEED_ENV := "QUICK_CAPTURE_SEED"
const FLOOR_ENV := "QUICK_CAPTURE_FLOOR"
const ZOOM_ENV := "QUICK_CAPTURE_ZOOM"

var main: MainRoot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot.call_deferred()


func _boot() -> void:
	var out_path := OS.get_environment(OUT_ENV)
	if out_path.is_empty():
		push_error("QUICK_CAPTURE_OUT is not set")
		get_tree().quit(2)
		return

	var size_env := OS.get_environment(SIZE_ENV)
	if not size_env.is_empty():
		var parts := size_env.split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

	var packed := load("res://scenes/Main.tscn") as PackedScene
	main = packed.instantiate() as MainRoot
	get_tree().root.add_child(main)
	for _i in range(6):
		await get_tree().process_frame

	var stage := OS.get_environment(STAGE_ENV)
	if stage.is_empty():
		stage = "arena"

	if stage != "menu":
		await _enter_arena()
		# QUICK_CAPTURE_SEED was declared here from the start but never applied, so
		# every capture compared a DIFFERENT forest: generate_world(0) seeds itself
		# from the clock. Any two art variants were therefore judged on two different
		# worlds, which quietly made every A/B in this project meaningless.
		var seed_env := OS.get_environment(SEED_ENV)
		if not seed_env.is_empty() and main.arena != null and main.arena.world != null:
			main.arena.world.generate_world(int(seed_env))
			main.arena.world.stream_around(main.arena.player.global_position, true)
			print("QUICK_CAPTURE seed_requested=%s seed_active=%d props=%d decor=%d chunks=%d" % [
				seed_env, main.arena.world._world_seed, main.arena.world.obstacles.size(),
				main.arena.world.decor_flora.size(), main.arena.world.streamed_chunk_count()])
			await get_tree().process_frame
		# Optional teleport, so the arena border can be inspected without walking there.
		var pos_env := OS.get_environment("QUICK_CAPTURE_POS")
		if not pos_env.is_empty():
			var parts := pos_env.split(",")
			if parts.size() == 2 and main.arena != null and main.arena.player != null:
				main.arena.player.global_position = Vector2(float(parts[0]), float(parts[1]))
		# Optional mass, so every growth stage can be photographed without eating
		# for five minutes. Goes through the same _sync_mass_metrics the game uses,
		# so the body, the aura and the world's bloom all follow from it.
		var mass_env := OS.get_environment("QUICK_CAPTURE_MASS")
		if not mass_env.is_empty() and main.arena != null and main.arena.player != null:
			main.arena.player.mass = float(mass_env)
			main.arena.player._sync_mass_metrics()
			print("QUICK_CAPTURE mass=%s stage=%d" % [
				mass_env, main.arena.player.visual.stage if main.arena.player.visual != null else -1])
		# The game auto-pauses on window focus loss (right for a phone, wrong for an
		# unattended capture: the frame would show the pause overlay). Reclaim focus
		# and resume if the pause already fired.
		DisplayServer.window_move_to_foreground()
		if App.state == App.State.PAUSED:
			App.change_state(App.State.PLAYING)
		_apply_floor_overrides()
		var seconds := 4.0
		var sec_env := OS.get_environment(SECONDS_ENV)
		if not sec_env.is_empty():
			seconds = float(sec_env)
		await _wait_in_arena(maxf(0.2, seconds))
		# After the wait, because the camera lerps its zoom every frame.
		_apply_zoom_override()

	# A couple of extra frames so the last shader/filter pass is definitely on screen.
	for _i in range(4):
		await get_tree().process_frame

	if App.state == App.State.PAUSED:
		App.change_state(App.State.PLAYING)
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("capture produced no image")
		get_tree().quit(3)
		return
	var err := img.save_png(out_path)
	print("QUICK_CAPTURE %s %dx%d err=%d state=%d paused=%s" % [
		out_path, img.get_width(), img.get_height(), err, App.state, str(get_tree().paused)])
	get_tree().quit(0 if err == OK else 4)


func _enter_arena() -> void:
	## Two attempts, and a hard refusal to photograph the menu. A tap can land
	## before the menu has finished laying out; during the fifteen-stage sweep one
	## run captured the main menu instead of the arena and the sheet showed an
	## "ИГРАТЬ" button where a slime should have been. A capture that silently
	## measures the wrong screen is worse than no capture.
	for attempt in range(2):
		var play_btn := main.menus.find_child("PlayButton", true, false) as Button
		if play_btn != null:
			await _tap(play_btn)
		for _i in range(4):
			await get_tree().process_frame

		var start_btn := _find_button(main.menus, Loc.t("mode.start_btn"))
		if start_btn != null:
			await _tap(start_btn)
		for _i in range(12):
			await get_tree().process_frame
			if App.state == App.State.PLAYING:
				break
		if App.state == App.State.PLAYING:
			break
		push_warning("quick_capture: arena did not start (attempt %d), retrying" % (attempt + 1))

	if App.state != App.State.PLAYING:
		push_error("quick_capture: could not enter the arena; refusing to capture the menu")
		get_tree().quit(5)
		return

	print("WORLD chunks=%d props=%d decor=%d children=%d" % [
		main.arena.world.streamed_chunk_count(),
		main.arena.world.obstacles.size(),
		main.arena.world.decor_flora.size(),
		main.arena.world.get_node("Chunks").get_child_count() if main.arena.world.get_node_or_null("Chunks") != null else -1,
	])


func _wait_in_arena(seconds: float) -> void:
	## Waits out the run before the shot. With QUICK_CAPTURE_MOVE=1 the slime is
	## actually driven around instead of standing still, because a trail, a wake or a
	## camera lead cannot be photographed on a stationary subject: the previous
	## captures all showed the slime parked at spawn and any motion-dependent effect
	## was invisible in them. The path is a slow circle, which is what a player's
	## thumb produces and what makes a trail curve.
	var move := OS.get_environment("QUICK_CAPTURE_MOVE") == "1"
	var start_pos := Vector2.ZERO
	if main != null and main.arena != null and main.arena.player != null:
		start_pos = main.arena.player.global_position
	var elapsed := 0.0
	var step := 1.0 / 60.0
	var phase := 0.0
	while elapsed < seconds:
		# A capture that lands on the mutation draft photographs the wrong screen,
		# which is exactly the failure this tool exists to avoid. Pick the first card
		# and keep playing, the same way the playthrough driver does.
		if App.state == App.State.MUTATION_DRAFT:
			_dismiss_draft()
		if move and main != null and main.arena != null and main.arena.player != null:
			phase += step * 1.35
			# Drive the joystick, not the player. GameHUD._process copies
			# `joystick.output_vector` into `player.move_input` every frame, so writing
			# move_input directly is a race against the HUD: it won in some captures and
			# lost in others, and the frames that lost showed a slime parked at spawn
			# with no trail at all. output_vector is only ever written by the joystick's
			# own touch handlers, so it is the one input that stays put.
			var dir := Vector2(cos(phase), sin(phase * 1.7)).normalized()
			if main.hud != null and main.hud.joystick != null:
				main.hud.joystick.output_vector = dir
			main.arena.player.move_input = dir
		await get_tree().create_timer(step).timeout
		elapsed += step
	if move and main != null and main.arena != null and main.arena.player != null:
		main.arena.player.move_input = Vector2.ZERO
		if main.hud != null and main.hud.joystick != null:
			main.hud.joystick.output_vector = Vector2.ZERO
		print("QUICK_CAPTURE moved %.0f px in a circle over %.1fs (trail lit=%d radius=%s strength=%s)" % [
			main.arena.player.global_position.distance_to(start_pos), seconds,
			main.arena.trail_point_count(),
			str(main.arena.canopy_mat.get_shader_parameter("trail_radius")),
			str(main.arena.canopy_mat.get_shader_parameter("trail_strength"))])


func _dismiss_draft() -> void:
	if main == null or main.draft_overlay == null:
		return
	var box: Node = main.draft_overlay._cards_box
	if box == null or box.get_child_count() == 0:
		return
	var card := box.get_child(0) as Button
	if card != null:
		card.pressed.emit()
		print("QUICK_CAPTURE dismissed a mutation draft")


func _apply_floor_overrides() -> void:
	## Art-tuning hook: lets one capture vary the floor layers without editing the
	## constants in ArenaController, so variants can be compared side by side.
	var spec := OS.get_environment(FLOOR_ENV)
	if spec.is_empty() or main.arena == null or main.arena.canopy_mat == null:
		return
	for pair in spec.split(","):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		main.arena.canopy_mat.set_shader_parameter(kv[0].strip_edges(), float(kv[1]))
		print("QUICK_CAPTURE floor %s=%s" % [kv[0].strip_edges(), kv[1]])


func _apply_zoom_override() -> void:
	var spec := OS.get_environment(ZOOM_ENV)
	if spec.is_empty() or main.arena == null or main.arena.camera == null:
		return
	main.arena.camera.zoom = Vector2.ONE * float(spec)


func _find_button(root_node: Node, match_text: String) -> Button:
	if root_node is Button and (root_node as Control).visible:
		if match_text.is_empty() or (root_node as Button).text == match_text:
			return root_node as Button
	for ch in root_node.get_children():
		var found := _find_button(ch, match_text)
		if found != null:
			return found
	return null


func _tap(ctrl: Control) -> void:
	# Same delivery path as the playthrough driver: a real touch event through the
	# engine input pipeline, so the frame shows what a player's tap produces.
	var sp := get_viewport().get_final_transform() * ctrl.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 5
	down.pressed = true
	down.position = sp
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 5
	up.pressed = false
	up.position = sp
	Input.parse_input_event(up)
	await get_tree().process_frame
