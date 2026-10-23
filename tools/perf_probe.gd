extends Node
## Frame-time probe for the endless world.
##
## The border removal took the world from ~120 sprites to ~600, and every claim
## about performance so far was a guess. This boots the REAL game, walks the real
## player with real touch events, and records what a frame actually costs.
##
## Two traps this probe exists to avoid, both found the hard way:
##   1. The wall clock is not trustworthy here: with vsync reported off the game
##      still reads exactly 16.67 ms per frame, and an EMPTY world reads 6.90 ms
##      (144.9 fps), i.e. the loop is paced. A resolution-scaling experiment was
##      tried to get around it and produced non-monotonic nonsense (145 -> 171 ->
##      114 fps as pixels grew), so it was removed rather than published. The
##      numbers that ARE trustworthy are the game's own timers and the draw-call
##      A/B, and those are what this probe reports.
##   2. Headless has a 6.9 ms frame floor on this machine (an EMPTY scene reads the
##      same 6.9 ms — see tools/frame_floor.gd), so headless numbers measure the
##      loop, not the game. There is no headless mode here.
##
## Phases, in this order, because the difference between them is the attribution:
##   idle       everything on, player standing still  -> steady state
##   no_detail  the art layers of the floor shader off -> cost of relief/AO/dapple
##   mood_ab    screen grade on vs off, alternating    -> cost of the fullscreen pass
##   draw_ab    forest hidden vs shown, alternating    -> draw calls of the forest
##   res_scale  window scaled 1x..3x                   -> fill-rate ceiling
##   walk       player walks a 700 px circle           -> cost of streaming
##
## Environment:
##   PERF_OUT        JSON output path (required)
##   PERF_JSON_ONLY  "1" to suppress the human table
##
## Honest limitation: an Apple M5 on Metal running a DEBUG build (so the numbers
## are pessimistic against the exported game), and no phone GPU was involved.

const OUT_ENV := "PERF_OUT"
const JSON_ONLY_ENV := "PERF_JSON_ONLY"

const SETTLE_SEC := 4.0
const IDLE_SEC := 10.0
const DETAIL_SEC := 6.0
const WALK_SEC := 24.0

# Same joystick geometry the playthrough driver uses, so movement goes through
# the real input path rather than teleporting the player.
const JOY_ORIGIN := Vector2(260.0, 980.0)
const JOY_DRAG := 62.0

var main: MainRoot

var _frames: PackedFloat64Array = PackedFloat64Array()
var _world_us: PackedFloat64Array = PackedFloat64Array()
var _stream_us: PackedFloat64Array = PackedFloat64Array()
var _draws: PackedInt32Array = PackedInt32Array()
var _results: Dictionary = {}
var _walk_dir := 0.0
var _walk_center := Vector2.ZERO
var _drafts_seen := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot.call_deferred()


func _boot() -> void:
	var out_path := OS.get_environment(OUT_ENV)
	if out_path.is_empty():
		push_error("PERF_OUT is not set")
		get_tree().quit(2)
		return

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("PERF display=%s window=%dx%d vsync_reported=%d max_fps=%d" % [
		DisplayServer.get_name(), DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		DisplayServer.window_get_vsync_mode(), Engine.max_fps])

	var packed := load("res://scenes/Main.tscn") as PackedScene
	main = packed.instantiate() as MainRoot
	get_tree().root.add_child(main)
	for _i in range(6):
		await get_tree().process_frame

	await _enter_arena()
	DisplayServer.window_move_to_foreground()
	_force_playing()

	# Let the first frames absorb shader compilation, texture upload and the
	# initial 7x7 chunk build; measuring through that would just measure startup.
	await _wait(SETTLE_SEC)
	_force_playing()

	var world := main.arena.world
	world.profile_enabled = true
	# Counters from here on, so the summary covers the measured phases only and not
	# the 49 chunks of startup.
	world.perf_chunks_built = 0
	world.perf_build_us_total = 0
	world.perf_build_us_max = 0
	print("PERF streamed=%d props=%d decor=%d spores=%d" % [
		world.streamed_chunk_count(), world.obstacles.size(),
		world.decor_flora.size(), world.ambient_spores.size()])

	# --- idle -------------------------------------------------------------
	await _measure("idle", IDLE_SEC, false)
	_store_counts("idle")

	# --- floor art layers off --------------------------------------------
	var mat := main.arena.canopy_mat
	var saved := {
		"floor_relief": mat.get_shader_parameter("floor_relief"),
		"floor_occlusion": mat.get_shader_parameter("floor_occlusion"),
		"floor_dapple": mat.get_shader_parameter("floor_dapple"),
		"floor_mist": mat.get_shader_parameter("floor_mist"),
	}
	mat.set_shader_parameter("floor_relief", 0.0)
	mat.set_shader_parameter("floor_occlusion", 0.0)
	mat.set_shader_parameter("floor_dapple", 0.0)
	mat.set_shader_parameter("floor_mist", 0.0)
	await _wait(0.6)
	await _measure("no_detail", DETAIL_SEC, false)
	_store_counts("no_detail")
	for k: String in saved.keys():
		mat.set_shader_parameter(k, saved[k])
	await _wait(0.6)

	# --- screen grade, alternating ---------------------------------------
	await _ab_mood()

	# --- draw calls, forest visible vs hidden ----------------------------
	await _ab_draw_calls()

	# --- walking ---------------------------------------------------------
	_walk_center = main.arena.player.global_position
	await _measure("walk", WALK_SEC, true)

	var summary := _build_summary()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out_path)
		get_tree().quit(3)
		return
	f.store_string(JSON.stringify(summary, "  ", false))
	f.close()

	if OS.get_environment(JSON_ONLY_ENV) != "1":
		_print_table(summary)
	print("PERF wrote %s" % out_path)
	get_tree().quit(0)


# --- measurement ---------------------------------------------------------

func _measure(phase: String, seconds: float, walking: bool) -> void:
	_frames.clear()
	_world_us.clear()
	_stream_us.clear()
	_draws.clear()

	var world := main.arena.world
	var prev_world := int(world.perf_us["process"])
	var prev_stream := int(world.perf_us["stream"])
	var prev_built := world.perf_chunks_built
	world.perf_build_us_max = 0

	var t0 := Time.get_ticks_usec()
	var last := t0
	var n := 0
	while (Time.get_ticks_usec() - t0) < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frames.append(float(now - last) / 1000.0)
		last = now
		n += 1
		var w := int(world.perf_us["process"])
		var st := int(world.perf_us["stream"])
		_world_us.append(float(w - prev_world) / 1000.0)
		_stream_us.append(float(st - prev_stream) / 1000.0)
		prev_world = w
		prev_stream = st
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if walking:
			# The game pauses itself on focus loss, and a level-up draft blocks
			# input until a card is picked. Both would silently turn this phase into
			# a measurement of standing still.
			if App.state == App.State.MUTATION_DRAFT:
				_drafts_seen += 1
				_handle_draft()
			elif App.state == App.State.PAUSED:
				App.handle_back_navigation()
			else:
				_drive_walk()

	_results[phase] = {
		"frames": n,
		"wall_ms": _stat(_frames),
		"world_ms": _stat(_world_us),
		"stream_ms": _stat(_stream_us),
		"draw_calls": _stat_i(_draws),
		"chunks_built": world.perf_chunks_built - prev_built,
		"build_us_max": world.perf_build_us_max,
	}


func _stat(a: PackedFloat64Array) -> Dictionary:
	if a.is_empty():
		return {}
	var sorted := Array(a)
	sorted.sort()
	var total := 0.0
	for v in a:
		total += v
	var avg := total / float(a.size())
	var over16 := 0
	for v in a:
		if v > 16.6:
			over16 += 1
	return {
		"avg": snappedf(avg, 0.0001),
		"p50": snappedf(_pct(sorted, 50.0), 0.0001),
		"p95": snappedf(_pct(sorted, 95.0), 0.0001),
		"max": snappedf(float(sorted[sorted.size() - 1]), 0.0001),
		"fps": snappedf(1000.0 / maxf(0.001, avg), 0.1),
		"over_16_6": over16,
	}


func _stat_i(a: PackedInt32Array) -> Dictionary:
	if a.is_empty():
		return {}
	var sorted := Array(a)
	sorted.sort()
	var total := 0
	for v in a:
		total += v
	return {
		"avg": snappedf(float(total) / float(a.size()), 0.1),
		"max": sorted[sorted.size() - 1],
	}


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := int(round((p / 100.0) * float(sorted.size() - 1)))
	return float(sorted[clampi(idx, 0, sorted.size() - 1)])


func _ab_mood() -> void:
	## Does the fullscreen grade cost anything measurable?
	##
	## The first attempt measured `idle` with the grade and then `no_mood` without it
	## and got 4.87 ms against 5.57 ms — i.e. the grade appeared to make the game
	## FASTER, which is the ordering and the streaming noise talking, not the grade.
	## So this alternates on/off eight times and takes medians, the same method that
	## makes the draw-call A/B usable, and reports the difference with its spread.
	## If the clock is pinned at 16.67 ms the answer is reported as "pinned" rather
	## than as a number.
	var mood := main.arena.mood
	if mood == null:
		return
	var on: Array[float] = []
	var off: Array[float] = []
	for _i in range(8):
		mood.visible = true
		await _wait(0.30)
		on.append(await _sample_frame_ms(0.45))
		mood.visible = false
		await _wait(0.30)
		off.append(await _sample_frame_ms(0.45))
	mood.visible = true
	await _wait(0.30)
	var om := _median(on)
	var fm := _median(off)
	_results["mood_ab"] = {
		"on_median_ms": snappedf(om, 0.01),
		"off_median_ms": snappedf(fm, 0.01),
		"delta_ms": snappedf(om - fm, 0.01),
		"pinned": om > 16.0 and fm > 16.0,
		"samples_on": on,
		"samples_off": off,
	}


func _sample_frame_ms(seconds: float) -> float:
	## Median frame-to-frame wall time over a short window.
	var t0 := Time.get_ticks_usec()
	var last := t0
	var deltas: Array[float] = []
	while (Time.get_ticks_usec() - t0) < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
	if deltas.is_empty():
		return 0.0
	deltas.sort()
	return deltas[deltas.size() / 2]


func _ab_draw_calls() -> void:
	## The undergrowth sprites are children of the chunk roots, so one switch hides
	## the whole forest. Alternating visible/hidden six times and taking medians
	## keeps the answer from depending on how many enemies happened to be alive.
	var chunks := main.arena.world.get_node_or_null("Chunks")
	if chunks == null:
		return
	var vis: Array[float] = []
	var hid: Array[float] = []
	for _i in range(6):
		chunks.visible = true
		await _wait(0.5)
		vis.append(await _sample_draws(1.0))
		chunks.visible = false
		await _wait(0.5)
		hid.append(await _sample_draws(1.0))
	chunks.visible = true
	await _wait(0.3)
	var vm := _median(vis)
	var hm := _median(hid)
	_results["draw_ab"] = {
		"visible_median": snappedf(vm, 0.1),
		"hidden_median": snappedf(hm, 0.1),
		"forest_draw_calls": snappedf(vm - hm, 0.1),
		"samples_visible": vis,
		"samples_hidden": hid,
	}


func _sample_draws(seconds: float) -> float:
	var t0 := Time.get_ticks_usec()
	var total := 0.0
	var n := 0
	while (Time.get_ticks_usec() - t0) < int(seconds * 1000000.0):
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	return total / float(maxi(1, n))


func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _handle_draft() -> void:
	## A level-up draft blocks input until a card is taken. Picking the first card
	## is what a player would do; leaving it open would freeze the walk phase.
	var card := main.draft_overlay.card_at(0)
	if card != null:
		card.pressed.emit()


func _store_counts(phase: String) -> void:
	var world := main.arena.world
	var chunks := world.get_node_or_null("Chunks")
	var sprites := 0
	var bodies := 0
	if chunks != null:
		for c in chunks.get_children():
			for n in c.get_children():
				if n is Sprite2D:
					sprites += 1
				elif n is StaticBody2D:
					bodies += 1
	var entry: Dictionary = _results.get(phase, {})
	entry["chunks"] = world.streamed_chunk_count()
	entry["props"] = world.obstacles.size()
	entry["decor"] = world.decor_flora.size()
	entry["chunk_sprites"] = sprites
	entry["static_bodies"] = bodies
	entry["nodes_total"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	entry["objects_total"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	entry["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01)
	_results[phase] = entry


func _build_summary() -> Dictionary:
	var idle: Dictionary = _results.get("idle", {})
	var walk: Dictionary = _results.get("walk", {})
	var world := main.arena.world
	return {
		"generated_at": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().get("string", "?"),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		"gpu": RenderingServer.get_video_adapter_name(),
		"os": OS.get_name() + " " + OS.get_version(),
		"build": "debug (pessimistic against the export)" if OS.is_debug_build() else "release",
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"vsync_reported": DisplayServer.window_get_vsync_mode(),
		"phases": _results,
		"draw_ab": _results.get("draw_ab", {}),
		"mood_ab": _results.get("mood_ab", {}),
		"chunks_built_total": world.perf_chunks_built,
		"build_us_avg": snappedf(float(world.perf_build_us_total) / float(maxi(1, world.perf_chunks_built)), 0.1),
		"drafts_seen": _drafts_seen,
		"idle_world_ms": idle.get("world_ms", {}).get("avg", 0.0),
		"walk_world_ms": walk.get("world_ms", {}).get("avg", 0.0),
	}


func _print_table(s: Dictionary) -> void:
	print("")
	print("wall_avg is only meaningful when it is NOT 16.67 (see PERF clock note); world/stream are the game's own timers")
	print("%-10s %6s %8s %8s %8s %8s %7s %6s" % [
		"phase", "frames", "wall_avg", "wall_p95", "world", "world_p95", "draws", "built"])
	for phase: String in ["idle", "no_detail", "walk"]:
		var e: Dictionary = s["phases"].get(phase, {})
		if e.is_empty() or not e.has("wall_ms"):
			continue
		print("%-10s %6d %8.2f %8.2f %8.3f %8.3f %7.1f %6d" % [
			phase, e["frames"],
			e["wall_ms"]["avg"], e["wall_ms"]["p95"], e["world_ms"]["avg"],
			e["world_ms"]["p95"], e["draw_calls"]["avg"], e["chunks_built"]])
	print("")
	var mab: Dictionary = s.get("mood_ab", {})
	if not mab.is_empty():
		if bool(mab.get("pinned", false)):
			print("screen grade: wall clock pinned at 60 Hz, cost not resolvable here (on %.2f ms / off %.2f ms)" % [
				mab["on_median_ms"], mab["off_median_ms"]])
		else:
			print("screen grade: on %.2f ms, off %.2f ms -> %.2f ms for the fullscreen pass (medians of 8)" % [
				mab["on_median_ms"], mab["off_median_ms"], mab["delta_ms"]])
	var ab: Dictionary = s.get("draw_ab", {})
	if not ab.is_empty():
		print("draw calls: forest visible %.1f, hidden %.1f -> forest costs %.1f draw calls" % [
			ab["visible_median"], ab["hidden_median"], ab["forest_draw_calls"]])
	print("chunk build: %d chunks built, avg %.0f us, worst %.0f us" % [
		s["chunks_built_total"], s["build_us_avg"],
		float(s["phases"].get("walk", {}).get("build_us_max", 0.0))])
	print("world._process: idle %.3f ms, walking %.3f ms (p95 %.3f) | drafts auto-picked: %d" % [
		s["phases"].get("idle", {}).get("world_ms", {}).get("avg", 0.0),
		s["phases"].get("walk", {}).get("world_ms", {}).get("avg", 0.0),
		s["phases"].get("walk", {}).get("world_ms", {}).get("p95", 0.0), _drafts_seen])
	var idle: Dictionary = s["phases"].get("idle", {})
	print("counts: chunks=%s sprites=%s bodies=%s nodes=%s mem=%s MB" % [
		idle.get("chunks", "?"), idle.get("chunk_sprites", "?"), idle.get("static_bodies", "?"),
		idle.get("nodes_total", "?"), idle.get("static_mem_mb", "?")])


# --- driving -------------------------------------------------------------

func _drive_walk() -> void:
	## Walk a 700 px circle. A straight line would cross a chunk boundary every
	## 512 px and then sit in the middle of one; a circle keeps streaming busy.
	var p := main.arena.player.global_position
	var rel := p - _walk_center
	_walk_dir += 0.9 * get_process_delta_time()
	var want := Vector2.RIGHT.rotated(_walk_dir)
	if rel.length() > 700.0:
		want = (-rel).normalized() * 0.6 + want * 0.4
	_drive_joystick(want.normalized())


func _drive_joystick(norm: Vector2) -> void:
	var xform := get_viewport().get_final_transform()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = xform * JOY_ORIGIN
	Input.parse_input_event(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = xform * (JOY_ORIGIN + norm * JOY_DRAG)
	Input.parse_input_event(drag)


func _force_playing() -> void:
	if App.state == App.State.PAUSED:
		App.change_state(App.State.PLAYING)


func _wait(seconds: float) -> void:
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) < int(seconds * 1000000.0):
		await get_tree().process_frame


func _enter_arena() -> void:
	## Verified and retried, not assumed. An earlier version tapped Play/Start after
	## a fixed three-frame wait and silently measured the MENU when the mode screen
	## was still animating in — the run reported chunks=0 and looked like a fast
	## empty world. A tap that lands mid-animation is simply swallowed, so each step
	## waits for its target to exist, settles, taps, and then checks the result.
	for _attempt in range(3):
		# By NODE NAME, not by text: _find_button matches button text, and there is
		# no button whose caption is "PlayButton". That mismatch cost a debugging
		# round where the probe kept measuring the menu.
		var play_btn := main.menus.find_child("PlayButton", true, false) as Button
		if play_btn != null:
			await _tap_settled(play_btn)
			print("PERF entered mode select: state=%d" % App.state)
		if not await _wait_until(func() -> bool:
				return _find_button(main.menus, Loc.t("mode.start_btn")) != null, 3.0):
			continue
		var start_btn := _find_button(main.menus, Loc.t("mode.start_btn"))
		if start_btn != null:
			await _tap_settled(start_btn)
		if await _wait_until(_arena_running, 3.0):
			return
	push_error("PERF: the arena never started after 3 attempts; refusing to measure the menu")
	get_tree().quit(4)


func _arena_running() -> bool:
	return main.arena != null and main.arena.visible and main.arena.world != null \
		and main.arena.world.streamed_chunk_count() > 0


func _wait_until(pred: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) < int(seconds * 1000000.0):
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _tap_settled(ctrl: Control, frames: int = 8) -> void:
	for _i in range(frames):
		await get_tree().process_frame
	await _tap(ctrl)


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
