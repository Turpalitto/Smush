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
##   QUICK_CAPTURE_BIOME    0..1 biome strength override (0 = the pre-biome floor)
##   QUICK_CAPTURE_WONDER   walk to the nearest Wonder: "asleep" | "awake"
##   QUICK_CAPTURE_DRAFT    1 = hold the mutation draft open instead of dismissing it
##   QUICK_CAPTURE_DRAFT_T  seconds to wait after the draft opens (default 0.6)

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
		_apply_biome_override()
		_walk_to_wonder()
		var seconds := 4.0
		var sec_env := OS.get_environment(SECONDS_ENV)
		if not sec_env.is_empty():
			seconds = float(sec_env)
		await _wait_in_arena(maxf(0.2, seconds))
		# After the wait, because the camera lerps its zoom every frame.
		_apply_zoom_override()
		await _open_draft_if_requested()
		print("QUICK_CAPTURE grove env=%.3f db=%.2f playing=%s" % [
			Audio.grove_env(), Audio.grove_db(), str(Audio.grove_is_playing())])

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
	# The cards now live inside bare Control wrappers (so the fly-in can animate
	# the Button without the VBoxContainer resetting it), so the card is asked for
	# by index instead of being assumed to be the box's direct child.
	var card := main.draft_overlay.card_at(0)
	if card != null:
		card.pressed.emit()
		print("QUICK_CAPTURE dismissed a mutation draft")


func _open_draft_if_requested() -> void:
	## Photographs the mutation draft itself. Without this the tool actively dodges
	## the one screen the draft work is about: `_wait_in_arena` dismisses any draft
	## it lands on, so every capture of the overlay would have to be taken by hand.
	## The draft is requested AFTER the arena wait so the dismiss guard cannot eat it.
	if OS.get_environment("QUICK_CAPTURE_DRAFT") != "1":
		return
	if main == null or main.arena == null:
		return
	# A matched pair: the same frame with and without the pane. Two separate runs
	# can land on different window sizes (the OS clamps the requested size), which
	# makes any pixel-by-pixel blur measurement between them meaningless.
	var pre_path := OS.get_environment("QUICK_CAPTURE_PRE_OUT")
	if not pre_path.is_empty():
		await RenderingServer.frame_post_draw
		var pre := get_viewport().get_texture().get_image()
		if pre != null and not pre.is_empty():
			pre.save_png(pre_path)
			print("QUICK_CAPTURE pre-draft %s %dx%d" % [pre_path, pre.get_width(), pre.get_height()])
	main.arena.request_mutation_draft()
	if App.state != App.State.MUTATION_DRAFT:
		push_error("QUICK_CAPTURE_DRAFT: the arena refused to open a draft")
		return
	var hold := 0.6
	var hold_env := OS.get_environment("QUICK_CAPTURE_DRAFT_T")
	if not hold_env.is_empty():
		hold = float(hold_env)
	# create_timer runs while paused, which the draft does to the tree.
	await get_tree().create_timer(maxf(0.0, hold)).timeout
	var cards: int = 0
	if main.draft_overlay != null:
		cards = main.draft_overlay.card_count()
	_apply_glass_overrides()
	print("QUICK_CAPTURE draft held %.2fs, %d cards, state=%d" % [hold, cards, App.state])
	if main.draft_overlay != null:
		# Print where each card actually is, so "the fly-in works" is a number
		# rather than an impression of a still frame.
		for i in range(cards):
			var c := main.draft_overlay.card_at(i)
			if c != null:
				print("QUICK_CAPTURE card%d y=%.1f alpha=%.3f scale=%.3f" % [
					i, c.position.y, c.modulate.a, c.scale.x])


func _apply_glass_overrides() -> void:
	## Tuning hook for the frosted pane, same idea as QUICK_CAPTURE_FLOOR: sweep a
	## uniform without editing the shader, so "transmission 0.42 vs 0.30" is an
	## A/B on one frame instead of two builds.
	var spec := OS.get_environment("QUICK_CAPTURE_GLASS")
	if spec.is_empty() or main == null or main.draft_overlay == null:
		return
	var rect := main.draft_overlay.glass_rect()
	if rect == null or rect.material == null:
		return
	var mat := rect.material as ShaderMaterial
	for pair in spec.split(","):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		var key := kv[0].strip_edges()
		var raw := kv[1].strip_edges()
		if key.begins_with("glass_tint") or key.begins_with("tint"):
			var parts := raw.split(" ")
			if parts.size() == 3:
				mat.set_shader_parameter("glass_tint",
					Color(float(parts[0]), float(parts[1]), float(parts[2]), 1.0))
			continue
		mat.set_shader_parameter(key, float(raw))
		print("QUICK_CAPTURE glass %s=%s" % [key, raw])


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


func _apply_biome_override() -> void:
	## `QUICK_CAPTURE_BIOME=0` photographs the floor as it was before the macro-biomes
	## existed, on the same seed and the same position as `QUICK_CAPTURE_BIOME=1`.
	## Without this an A/B of the block compares two different forests and reads as
	## "the palette changed a bit, maybe", which is not a measurement.
	var spec := OS.get_environment("QUICK_CAPTURE_BIOME")
	if spec.is_empty() or main.arena == null or main.arena.canopy_mat == null:
		return
	var v := float(spec)
	main.arena.canopy_mat.set_shader_parameter("biome_strength", v)
	print("QUICK_CAPTURE biome_strength=%s" % spec)


func _walk_to_wonder() -> void:
	## Teleports the slime next to the nearest Wonder and prints where it is. Asking
	## the world for the position instead of hard-coding one means the capture cannot
	## silently photograph empty forest because a constant drifted.
	var spec := OS.get_environment("QUICK_CAPTURE_WONDER")
	if spec.is_empty() or main.arena == null or main.arena.world == null:
		return
	var world: WorldGenerator = main.arena.world
	var best: Dictionary = {}
	var best_d := INF
	for cy in range(-6, 7):
		for cx in range(-6, 7):
			var w := world._wonder_in_cell(cx, cy)
			if w.is_empty():
				continue
			var d := (w["pos"] as Vector2).length()
			if d < best_d:
				best_d = d
				best = w
	if best.is_empty():
		push_error("QUICK_CAPTURE_WONDER: no wonder found near the origin")
		return
	# 220 px away for a dormant landmark (its halo is visible from a screen away, the
	# sprite is not), 90 px to stand inside the trigger radius and wake it.
	var offset := Vector2(0.0, 90.0) if spec == "awake" else Vector2(0.0, 220.0)
	main.arena.player.global_position = (best["pos"] as Vector2) + offset
	world.stream_around(main.arena.player.global_position, true)
	print("QUICK_CAPTURE wonder kind=%s pos=%s seen=%s" % [
		best["kind"], str(best["pos"]), str(world.wonder_is_seen(best["cell"]))])


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
