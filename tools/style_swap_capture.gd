extends Node
## STYLE-SWAP ACCEPTANCE CAPTURE — renders the REAL game arena with the
## experimental organic slime, without touching any game code.
##
## Boots Main.tscn exactly like the player would, enters a seeded run, then
## replaces the player's SlimeVisual with SlimeVisualOrganic (or reverts to the
## original for A/B), wires the organic-only reactions to the real game events,
## and drives a scripted episode. Everything visual-only: gameplay, balance and
## saves run as shipped (absorption stats still count, same as the QA suites).
##
## Environment hooks (all optional):
##   SWAP_OUT      output prefix. With SWAP_AB=1 writes "<prefix>_organic.png"
##                 and "<prefix>_original.png"; otherwise a single PNG path.
##   SWAP_AB       1 = capture BOTH styles from the SAME frozen simulation state
##                 (see "Why AB" below). This is the only honest A/B mode.
##   SWAP_FREEZE   1 = pause the tree before an AB pair (default 1). A paused
##                 frame is frozen mid-animation, so a 0.22 s effect can be
##                 photographed at its peak instead of after it ended.
##   SWAP_STYLE    organic | original   (default organic)
##   SWAP_SEED     run seed              (default 424242 — identical forests for A/B)
##   SWAP_MASS     set player mass       (default: leave the run's start mass)
##   SWAP_STAGE    1..15 = mass at that stage threshold (+0.05), exact ladder pose
##   SWAP_MUT      csv mutation ids to enable at SWAP_MLEVEL (set directly on
##                 MutationManager.levels — no save writes, no draft spam)
##   SWAP_MLEVEL   mutation level 1..5   (default 3)
##   SWAP_WAIT     seconds to let the episode play before the frame  (default 1.2)
##   SWAP_AT       event-armed capture instead of a blind wait:
##                   impact  — the shield blocked a real contact hit
##                   swallow — an absorption completed (ghost + ripple alive)
##                   reel    — the pseudopod has been extended for SWAP_AFTER s
##                   electro — the mutation's pulse timer just reset
##                   dash    — a dash just started
##                   boss    — the boss is within SWAP_RING px
##                   boss_telegraph — the Guardian entered a TELEGRAPH_* state
##                                    (the lane is drawn, nothing landed yet)
##                 If the event never happens the run FAILS (exit 6) instead of
##                 saving a frame of the wrong moment.
##   SWAP_AFTER    seconds after the armed event to freeze (default 0.12)
##   SWAP_EYES     open = hold the eyes open for the pair (a 0.11 s blink is
##                 random and reads as damage in a still; nothing else changes)
##   SWAP_TIMEOUT  give up on an armed event after N s (default 10)
##   SWAP_MOVE     1 = drive the joystick in a slow circle (real input path)
##   SWAP_DASH     1 = dash every ~2.2 s (needs dash in SWAP_MUT)
##   SWAP_BOSS     1 = spawn the Ancient Guardian into view immediately
##   SWAP_ENEMIES  n = spawn a ring of n assorted enemies around the player
##   SWAP_RING     ring radius for enemies / boss-near test (default 260)
##   SWAP_ABSORB   small|large|both — spawn edible prey near the player:
##                 small = tiny mushrooms, large = an umbral_alpha weakened to 15% HP
##   SWAP_EVOLVE   "from,to,seconds" — animate mass smoothly for the evolution clip
##   SWAP_HP       override player max HP (survivability for long boss clips)
##   SWAP_QUALITY  0|1|2 organic quality (default 2)
##   SWAP_SIZE     WxH window size
##   SWAP_PERF_ONE original | organic | organic:0..2 — stress the arena (32 enemies
##                 + boss + 45 orbs), vsync off, print avg/p50/p95/max frame ms.
##                 ONE STYLE PER PROCESS: measuring several configurations inside a
##                 single run mixes shader-compile cost into the first one and lets
##                 each configuration inherit a world the previous one already ate.
##   SWAP_PERF_BODY n — synthetic body-only micro-benchmark: no enemies, body scaled
##                 n times so the shader fills the screen. Isolates fragment cost;
##                 it is not a gameplay scenario.
##   SWAP_TOGGLE   1 = verify the SHIPPED switch in the live arena (VisualStyle →
##                 Events → PlayerSlime.apply_visual_style): default is original,
##                 on/off both work mid-run, mass/HP/absorbed unchanged. Exit 8 on
##                 any mismatch. Writes "<prefix>_toggle_on/off.png" when SWAP_OUT is
##                 set.
##
## Why AB: two separate runs with the same seed still diverge — enemy spawns,
## mushrooms and drifting props use unseeded RNG and the run clock, so the two
## frames differ across the whole world and no visual verdict can be drawn from
## them. SWAP_AB swaps the player's visual class only, inside ONE run, and
## freezes the tree between the two shots: the world is pixel-identical, the
## only variable is the style under test.
##
## The process marks itself as unattended (QUICK_CAPTURE_OUT) so GameManager does
## not pause the run when the window loses focus mid-episode. Without it a long
## armed wait can be frozen by any focus change and then time out on an event that
## never got the chance to happen.
##
## Movie capture is external, repo-standard: run this scene with
##   godot --path . res://tools/StyleSwapCapture.tscn \
##     --write-movie out.avi --fixed-fps 30  (plus the env hooks above)

const SEED_DEFAULT := 424242
const DRAFT_SUPPRESS_LEVEL := 60 # evolution threshold ~12.8k xp: no drafts mid-episode
const STAGE_MASS: Array[float] = [
	10.0, 15.0, 20.5, 26.0, 32.0, 38.5, 45.0, 52.0,
	59.0, 66.0, 73.0, 79.5, 85.5, 91.0, 96.0,
]

var main: MainRoot
var organic: bool = true
var quality: int = 2
var _move_phase: float = 0.0
var _dash_cd: float = 0.25
var _prev_electro_timer: float = -1.0
var _evolve: Dictionary = {}
var _evolve_t: float = 0.0
var _quit_at: float = -1.0
var _out_path: String = ""
var _captured: bool = false
var _move: bool = false
var _dash: bool = false

# --- acceptance capture state -------------------------------------------------
var _ab: bool = false
var _freeze: bool = true
var _at: String = ""
var _after: float = 0.12
var _timeout: float = 10.0
var _elapsed: float = 0.0
var _arm_t: float = -1.0          # -1 = not armed, >= 0 = counting after the event
var _armed_once: bool = false
var _reel_run: float = 0.0
var _dash_prev: bool = false
var _tag: String = ""
var _eyes_open: bool = false
## nucleus_y, nucleus_r, nucleus_mix override for the face comparison (-1 = keep the
## shader default). Lets the variants be shot from the same scene without editing the
## shader between runs.
var _nucleus_override: Vector3 = Vector3(-1.0, -1.0, -1.0)
## Last frame grabbed by _save_png, kept so _ab_pair can compare the two shots
## without reading the viewport a third time.
var _last_img: Image = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# GameManager auto-pauses a run when the window loses focus (mobile background
	# safety). It skips that for tools, but only recognises PLAYTHROUGH_SUMMARY_PATH
	# and QUICK_CAPTURE_OUT. Without this, any focus change during a long armed wait
	# freezes the world while this node keeps counting (PROCESS_MODE_ALWAYS), and the
	# capture times out on an event that never got the chance to happen — measured
	# exactly that on a 14 s boss wait. Marking the process as unattended is the
	# existing contract, not a new switch.
	if not OS.has_environment("QUICK_CAPTURE_OUT"):
		OS.set_environment("QUICK_CAPTURE_OUT", OS.get_environment("SWAP_OUT"))
	_boot.call_deferred()


func _boot() -> void:
	var size_env := OS.get_environment("SWAP_SIZE")
	if not size_env.is_empty():
		var parts := size_env.split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

	organic = OS.get_environment("SWAP_STYLE") != "original"
	quality = clampi(_env_int("SWAP_QUALITY", 2), 0, 2)
	_move = OS.get_environment("SWAP_MOVE") == "1"
	_dash = OS.get_environment("SWAP_DASH") == "1"
	_out_path = OS.get_environment("SWAP_OUT")
	var perf_one := OS.get_environment("SWAP_PERF_ONE").strip_edges()
	_ab = OS.get_environment("SWAP_AB") == "1"
	_freeze = OS.get_environment("SWAP_FREEZE") != "0"
	_at = OS.get_environment("SWAP_AT").strip_edges()
	_after = _env_float("SWAP_AFTER", 0.12)
	_timeout = _env_float("SWAP_TIMEOUT", 10.0)
	_tag = _out_path.get_file()
	_eyes_open = OS.get_environment("SWAP_EYES") == "open"
	var nuc_env := OS.get_environment("SWAP_NUCLEUS").strip_edges()
	if not nuc_env.is_empty():
		var nuc_bits := nuc_env.split(",")
		if nuc_bits.size() == 3:
			_nucleus_override = Vector3(float(nuc_bits[0]), float(nuc_bits[1]), float(nuc_bits[2]))

	var packed := load("res://scenes/Main.tscn") as PackedScene
	main = packed.instantiate() as MainRoot
	get_tree().root.add_child(main)
	for _i in range(6):
		await get_tree().process_frame

	var run_seed := _env_int("SWAP_SEED", SEED_DEFAULT)
	main._start_run("standard", run_seed)
	# The arena turns PLAYING a frame or two after _start_run, but a focus-out
	# notification at boot can pause it before that (GameManager's mobile
	# background safety). Twelve frames was too tight under load — one run in
	# twenty-six died here. Wait against a real deadline and undo a boot-time
	# pause: this process is unattended, so a pause at boot is never a decision.
	var boot_deadline := Time.get_ticks_msec() + 2500
	while App.state != App.State.PLAYING and Time.get_ticks_msec() < boot_deadline:
		if App.state == App.State.PAUSED:
			App.change_state(App.State.PLAYING)
		await get_tree().process_frame
	if App.state != App.State.PLAYING:
		push_error("SWAP: arena did not start (state=%d after 2.5s)" % int(App.state))
		get_tree().quit(5)
		return

	var player := main.arena.player
	# Suppress mutation drafts: the episode must not pause on a card overlay, and
	# a random draft pick would make A/B runs diverge. Raising the level inflates
	# the XP threshold without touching any visual or balance path (growth is
	# mass-driven, the HUD bar is cosmetic).
	player.evolution_level = DRAFT_SUPPRESS_LEVEL

	var mass_env := OS.get_environment("SWAP_MASS")
	if not mass_env.is_empty():
		player.mass = float(mass_env)
	var stage_env := _env_int("SWAP_STAGE", 0)
	if stage_env >= 1:
		player.mass = STAGE_MASS[clampi(stage_env, 1, 15) - 1] + 0.05
	var hp_env := OS.get_environment("SWAP_HP")
	if not hp_env.is_empty():
		player.max_hp = float(hp_env)
		player.hp = player.max_hp
	var mut_env := OS.get_environment("SWAP_MUT")
	var mlevel := clampi(_env_int("SWAP_MLEVEL", 3), 1, 5)
	if not mut_env.is_empty():
		for mid in mut_env.split(","):
			player.mutations.levels[mid.strip_edges()] = mlevel
	player._sync_mass_metrics()

	_swap_visual()
	_wire_organic_hooks()
	# Setting the mass at boot jumps the ladder (1 -> 8), which fires the real
	# evolution flash. That flash is a capture artefact, not an event of the
	# episode: clear it so an armed frame 0.2 s later is not a white screen.
	if player.visual != null:
		player.visual.evolution_flash = 0.0
		player.visual.gulp_bulge = 0.0

	# Scripted episode content.
	var ring := _env_float("SWAP_RING", 260.0)
	var enemies_env := OS.get_environment("SWAP_ENEMIES")
	if not enemies_env.is_empty():
		var n := clampi(int(enemies_env), 0, 40)
		for i in range(n):
			var ang := (TAU / float(n)) * float(i)
			main.arena.spawn_enemy_by_id(ConfigDB.enemy_order[i % ConfigDB.enemy_order.size()],
				player.global_position + Vector2.from_angle(ang) * ring)
	var absorb_env := OS.get_environment("SWAP_ABSORB")
	if absorb_env == "small" or absorb_env == "both":
		for i in range(4):
			main.arena.spawn_enemy_by_id("tiny_mushroom",
				player.global_position + Vector2.from_angle(TAU * float(i) / 4.0 + 0.4) * 150.0)
	if absorb_env == "large" or absorb_env == "both":
		# 130 px default: inside the move-circle so the reel fires for sure. A
		# farther prey (SWAP_PREY_DIST) buys the slow reel time to be photographed
		# mid-flight instead of after the swallow already resolved.
		var prey_d := _env_float("SWAP_PREY_DIST", 130.0)
		var alpha := main.arena.spawn_enemy_by_id("umbral_alpha",
			player.global_position + Vector2(prey_d, -20.0))
		# Weakened to the absorbable window (<=22% HP) so the reel + teardrop
		# sequence actually plays; the rules engine is untouched.
		alpha.hp = alpha.max_hp * 0.15
	if OS.get_environment("SWAP_BOSS") == "1":
		var boss := main.arena.spawn_ancient_guardian_boss()
		boss.global_position = player.global_position + Vector2(330.0, -40.0)
	# A single named enemy parked on the player's shoulder: the only reliable way
	# to get a REAL contact hit (and therefore a real shield block) without
	# waiting for a random spawn to walk over.
	var hitter := OS.get_environment("SWAP_HITTER").strip_edges()
	if not hitter.is_empty():
		var h := main.arena.spawn_enemy_by_id(hitter, player.global_position + Vector2(46.0, 0.0))
		if h != null:
			print("SWAP hitter=%s at %.0fpx" % [hitter, h.global_position.distance_to(player.global_position)])
	var evolve_env := OS.get_environment("SWAP_EVOLVE")
	if not evolve_env.is_empty():
		var parts := evolve_env.split(",")
		if parts.size() == 3:
			_evolve = {"from": float(parts[0]), "to": float(parts[1]), "secs": maxf(1.0, float(parts[2]))}
			player.mass = _evolve["from"]
			player._sync_mass_metrics()

	DisplayServer.window_move_to_foreground()
	if App.state == App.State.PAUSED:
		App.change_state(App.State.PLAYING)

	var wait_env := OS.get_environment("SWAP_WAIT")
	var wait := 1.2 if wait_env.is_empty() else float(wait_env)
	_quit_at = wait
	if OS.get_environment("SWAP_TOGGLE") == "1":
		await _run_toggle_check()
		return
	if not perf_one.is_empty():
		# "original" or "organic" / "organic:2" — style and quality in one token.
		var bits := perf_one.split(":")
		organic = bits[0] != "original"
		if bits.size() > 1:
			quality = clampi(int(bits[1]), 0, 2)
		_swap_visual()
		_run_perf_one()
		return
	if not _at.is_empty():
		# Armed mode: _process watches for the real event; a timeout fails loudly.
		print("SWAP_ARMED at=%s after=%.2fs timeout=%.1fs" % [_at, _after, _timeout])
		return
	await get_tree().create_timer(maxf(0.2, wait)).timeout
	await _finish_capture()


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return fallback if v.is_empty() else int(v)


## SWAP_NUCLEUS="y,r,mix" — compare core placement without editing the shader between
## runs. Applied after every swap, because a swap builds a fresh node with the shader
## defaults.
func _apply_nucleus_override() -> void:
	if _nucleus_override.x < 0.0:
		return
	var vis := main.arena.player.visual
	if vis is SlimeVisualOrganic and vis._shader_mat != null:
		vis._shader_mat.set_shader_parameter("nucleus_y", _nucleus_override.x)
		vis._shader_mat.set_shader_parameter("nucleus_r", _nucleus_override.y)
		vis._shader_mat.set_shader_parameter("nucleus_mix", _nucleus_override.z)


func _env_float(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return fallback if v.is_empty() else float(v)


func _swap_visual() -> void:
	var player := main.arena.player
	var old: SlimeVisual = player.visual
	var next: SlimeVisual
	if organic:
		next = SlimeVisualOrganic.new()
	else:
		next = SlimeVisual.new()
	next.name = "SlimeVisual"
	# Carry the live presentation state so the swap is seamless mid-episode.
	old.copy_presentation_to(next)
	player.remove_child(old)
	old.queue_free()
	player.visual = next
	player.add_child(next)
	if organic:
		(next as SlimeVisualOrganic).set_quality(quality)
	player._sync_mass_metrics()
	_apply_nucleus_override()
	print("SWAP visual=%s mutations=%s mass=%.1f" % [
		"organic" if organic else "original", str(player.mutations.levels), player.mass])


## Field-by-field handover lives on SlimeVisual.copy_presentation_to(): the same
## routine the in-game switch uses, so the two styles are handed the exact same
## state — no re-derivation, no drift, and no second copy of the field list.
func _wire_organic_hooks() -> void:
	# The organic visual's own reactions hook onto REAL game events here — the
	# same three one-line integration points documented for the real game.
	Events.entity_absorbed.connect(_on_entity_absorbed)
	Events.player_shield_triggered.connect(_on_shield_triggered)
	set_process(true)


func _on_entity_absorbed(_entity_id: String, _mass_gained: float, _xp: float, world_pos: Vector2) -> void:
	if not organic or main == null or main.arena == null:
		return
	var vis := main.arena.player.visual
	if vis is SlimeVisualOrganic:
		var entry := world_pos - main.arena.player.global_position
		(vis as SlimeVisualOrganic).trigger_swallow(entry, Color(0.72, 0.92, 0.80), 9.0)
	if _at == "swallow":
		_arm()


func _on_shield_triggered() -> void:
	if not organic or main == null or main.arena == null:
		return
	var vis := main.arena.player.visual
	if vis is SlimeVisualOrganic:
		var dir := Vector2.RIGHT
		var near: Node2D = main.arena.enemy_grid.query_nearest(main.arena.player.global_position, 320.0)
		if near != null:
			dir = (near.global_position - main.arena.player.global_position).normalized()
		(vis as SlimeVisualOrganic).trigger_shield_impact(dir)
	if _at == "impact":
		_arm()


func _arm() -> void:
	if _armed_once:
		return
	_armed_once = true
	_arm_t = 0.0


func _process(delta: float) -> void:
	if main == null or main.arena == null or main.arena.player == null:
		return
	var player := main.arena.player
	_elapsed += delta

	# Unattended capture: a pause here is always an accident (the window lost focus
	# and GameManager applied its mobile background safety) and it would freeze the
	# very event being waited for while this node keeps counting. Drafts are already
	# suppressed, so there is no legitimate pause to preserve mid-episode.
	if not _captured and App.state == App.State.PAUSED:
		App.change_state(App.State.PLAYING)

	if _move:
		# Real input path: the joystick writes move_input in GameHUD._process; we
		# write both the way quick_capture does so the frame shows player-driven motion.
		_move_phase += delta * 1.25
		var dir := Vector2(cos(_move_phase), sin(_move_phase * 1.6)).normalized()
		player.move_input = dir
		if main.hud != null and main.hud.joystick != null:
			main.hud.joystick.output_vector = dir

	if _dash:
		_dash_cd -= delta
		if _dash_cd <= 0.0:
			_dash_cd = 2.2
			player.trigger_dash()

	# Electro: charge builds in the body shader; when the REAL pulse timer resets
	# (the discharge just fired), sync the visual flash + arcs to the same beat.
	if organic and player.mutations.has_mutation("electro_discharge"):
		var t := player._electro_timer
		if _prev_electro_timer >= 0.0 and t > _prev_electro_timer + 0.5:
			var vis := player.visual
			if vis is SlimeVisualOrganic:
				(vis as SlimeVisualOrganic).trigger_electro_flash()
				var node := vis.get_node_or_null("OrganicElectro")
				if node is OrganicElectro:
					var targets: Array[Vector2] = []
					for node2 in main.arena.enemy_grid.query_radius(player.global_position, 300.0):
						var en := node2 as EnemyEntity
						if en != null and en.is_active_combatant():
							targets.append(en.global_position - player.global_position)
						if targets.size() >= 2:
							break
					if not targets.is_empty():
						(node as OrganicElectro).fire_discharge(targets)
			if _at == "electro":
				_arm()
		_prev_electro_timer = t

	# Armed-event watchers that have no signal to hook.
	if not _at.is_empty() and not _armed_once:
		match _at:
			"reel":
				var vis2 := player.visual
				if vis2 != null and not vis2.active_tendril_targets.is_empty():
					_reel_run += delta
					if _reel_run >= _after:
						_armed_once = true
						_arm_t = 0.0
						_after = 0.0
				else:
					_reel_run = 0.0
			"dash":
				if player.is_dashing and not _dash_prev:
					_arm()
				_dash_prev = player.is_dashing
			"boss":
				if main.arena.active_boss != null and is_instance_valid(main.arena.active_boss):
					if main.arena.active_boss.global_position.distance_to(player.global_position) <= _env_float("SWAP_RING", 260.0):
						_arm()
			"boss_telegraph":
				# The frame that matters in boss combat is the telegraph: the
				# danger lane is drawn, nothing has landed yet. Waiting a fixed
				# number of seconds mostly catches PURSUIT.
				if main.arena.active_boss != null and is_instance_valid(main.arena.active_boss):
					var st: int = main.arena.active_boss.action_state
					if st == AncientGuardianBoss.ActionState.TELEGRAPH_SLAM \
							or st == AncientGuardianBoss.ActionState.TELEGRAPH_CROSS \
							or st == AncientGuardianBoss.ActionState.TELEGRAPH_CHARGE:
						_arm()

	if not _evolve.is_empty():
		_evolve_t += delta
		var w := clampf(_evolve_t / float(_evolve["secs"]), 0.0, 1.0)
		player.mass = lerpf(float(_evolve["from"]), float(_evolve["to"]), smoothstep(0.0, 1.0, w))
		player._sync_mass_metrics()
		if w >= 1.0:
			_evolve = {}

	if not _at.is_empty():
		if _arm_t >= 0.0:
			_arm_t += delta
			if _arm_t >= _after:
				_arm_t = -1.0
				_fire_armed()
		elif _elapsed > _timeout and not _captured:
			_captured = true
			push_error("SWAP: event '%s' not observed in %.1fs — refusing to save a frame of the wrong moment" % [_at, _timeout])
			print("SWAP_ARMED_TIMEOUT at=%s" % _at)
			get_tree().quit(6)
		return

	if _quit_at > 0.0:
		_quit_at -= delta
		if _quit_at <= 0.0 and not _out_path.is_empty():
			_capture_or_ab()


## One place that decides single frame vs frozen AB pair.
func _capture_or_ab() -> void:
	if _ab:
		await _ab_pair()
	else:
		await _capture_now()


func _fire_armed() -> void:
	if _captured:
		return
	if _ab:
		await _ab_pair()
	else:
		await _capture_now()


## --- AB: one frozen simulation state, two styles ------------------------------

func _ab_pair() -> void:
	if _captured:
		return
	# The pause overlay is not the arena. GameManager pauses the run when the window
	# loses focus, so a capture that starts while paused saves a menu instead of the
	# slime, and a pause landing BETWEEN the two saves makes the pair differ across
	# the whole frame. Both happened in a 26-pair verification run and read as
	# "huge style differences" until the frames were opened. Refuse instead.
	if App.state == App.State.PAUSED:
		push_error("SWAP: refusing to save the pause overlay (the run was paused before the frame)")
		print("SWAP_PAUSED_AT_CAPTURE tag=%s" % _tag)
		get_tree().quit(7)
		return
	_captured = true
	var dir := _out_path.get_base_dir()
	var base := _out_path.get_file()
	if dir.is_empty():
		dir = "."
	var p_organic := dir.path_join(base + "_organic.png")
	var p_original := dir.path_join(base + "_original.png")
	# Freeze: the tree stops advancing, the renderer keeps drawing. A 0.22 s
	# shield dent or a 0.59 s swallow ghost stays exactly where it was caught.
	if _eyes_open:
		# Presentation-only: a blink is a 0.11 s random event every 2.4-4.8 s and
		# it happens in both styles, but a still caught mid-blink reads as damage
		# to a reviewer. Hold the eyes open for the pair; nothing else changes.
		var v := main.arena.player.visual
		if v != null:
			v._blink_open = 1.0
			v._blink_timer = 3.0
			v.queue_redraw()
			if v._fg_overlay != null:
				v._fg_overlay.queue_redraw()
	if _freeze:
		get_tree().paused = true
	await _wait_frames(3)
	var e1 := _save_png(p_organic)
	var shot_a := _last_img
	_swap_preserving(not organic)
	await _wait_frames(3)
	var e2 := _save_png(p_original)
	var shot_b := _last_img
	var delta := _max_frame_delta(shot_a, shot_b)
	if _freeze:
		get_tree().paused = false
	if delta < 24:
		# Stale viewport or a swap that never reached the screen: two copies of one
		# picture are not an A/B, and publishing them would fake a comparison.
		push_error("SWAP: A/B frames are indistinguishable (max delta %d) — the swap never reached the screen" % delta)
		print("SWAP_AB_STALE tag=%s delta=%d" % [_tag, delta])
		get_tree().quit(7)
		return
	print("SWAP_AB tag=%s organic=%s original=%s err=%d/%d delta=%d paused=%s" % [
		_tag, p_organic, p_original, e1, e2, delta, str(_freeze)])
	get_tree().quit(0 if e1 == OK and e2 == OK else 4)


## Largest per-channel difference between two frames, sampled every second pixel.
## A real A/B pair differs by >100 on the body contour; a stale viewport or a swap
## that never reached the screen gives single-digit noise.
func _max_frame_delta(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 255
	var da := a.get_data()
	var db := b.get_data()
	if da.is_empty() or da.size() != db.size():
		return 255
	var worst := 0
	for i in range(0, da.size() - 3, 8):
		for c in range(3):
			var d: int = absi(int(da[i + c]) - int(db[i + c]))
			if d > worst:
				worst = d
				if worst >= 255:
					return worst
	return worst


## Swap the visual class in place while the tree is frozen, priming the new node
## by hand (a paused node never gets its first _process, and an unprimed
## ColorRect would render as nothing).
func _swap_preserving(want_organic: bool) -> void:
	var player := main.arena.player
	var old: SlimeVisual = player.visual
	var next: SlimeVisual = SlimeVisualOrganic.new() if want_organic else SlimeVisual.new()
	next.name = "SlimeVisual"
	# One shared copy routine with the in-game switch (PlayerSlime.apply_visual_style):
	# the acceptance frames must carry exactly the state the game carries.
	old.copy_presentation_to(next)
	player.remove_child(old)
	old.queue_free()
	player.visual = next
	player.add_child(next)
	if want_organic:
		(next as SlimeVisualOrganic).set_quality(quality)
	# One zero-delta tick: sizes the shader rect, flushes palette/quality uniforms
	# and pushes the aura state, without advancing a single animation.
	next._process(0.0)
	_apply_nucleus_override()
	next.queue_redraw()
	if next._fg_overlay != null:
		next._fg_overlay.queue_redraw()


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save_png(path: String) -> int:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("SWAP: no image")
		return FAILED
	_last_img = img
	var err := img.save_png(path)
	var vis := main.arena.player.visual
	print("SWAP_SHOT %s %dx%d style=%s stage=%d mass=%.1f err=%d" % [
		path, img.get_width(), img.get_height(),
		# The real class, not the tool's own flag: after a live switch they differ.
		"organic" if vis is SlimeVisualOrganic else "original",
		vis.stage if vis != null else -1, main.arena.player.mass, err])
	return err


func _capture_now() -> void:
	if _captured:
		return
	_captured = true
	await _wait_frames(3)
	var err := _save_png(_out_path)
	get_tree().quit(0 if err == OK else 4)


## --- real switch path ---------------------------------------------------------
##
## Proves the SHIPPED switch (VisualStyle → Events → PlayerSlime.apply_visual_style),
## not the tool's private AB swap. Requirements from the owner: the original style
## stays the default, switching changes nothing but the look, and switching back works
## without restarting the run. So this asserts, in the live arena:
##   * default state is the original visual;
##   * enabling turns the player's visual into SlimeVisualOrganic;
##   * disabling turns it back, mid-run, with the game still PLAYING;
##   * mass, HP and absorbed count are identical before/after — the switch is visual.
func _run_toggle_check() -> void:
	var player := main.arena.player
	var mass0 := player.mass
	var hp0 := player.hp
	var absorbed0 := player.absorbed_count
	var default_original := not (player.visual is SlimeVisualOrganic)

	VisualStyle.set_enabled(true)
	await _wait_frames(4)
	var on_ok := player.visual is SlimeVisualOrganic
	if on_ok and not _out_path.is_empty():
		await _save_png(_out_path + "_toggle_on.png")
	# Let the organic body run a few real frames: a swap that only looks right in the
	# first frame would not survive the animation.
	await get_tree().create_timer(0.6).timeout
	var mass_on := player.mass

	VisualStyle.set_enabled(false)
	await _wait_frames(4)
	var off_ok := not (player.visual is SlimeVisualOrganic)
	if off_ok and not _out_path.is_empty():
		await _save_png(_out_path + "_toggle_off.png")

	var stats_ok := is_equal_approx(mass0, mass_on) \
		and is_equal_approx(mass0, player.mass) \
		and is_equal_approx(hp0, player.hp) \
		and absorbed0 == player.absorbed_count
	var state_ok := App.state == App.State.PLAYING
	var ok := default_original and on_ok and off_ok and stats_ok and state_ok
	print("SWAP_TOGGLE default_original=%s on=%s off=%s stats_ok=%s state_ok=%s mass=%.3f/%.3f/%.3f hp=%.1f/%.1f absorbed=%d/%d" % [
		str(default_original), str(on_ok), str(off_ok), str(stats_ok), str(state_ok),
		mass0, mass_on, player.mass, hp0, player.hp, absorbed0, player.absorbed_count])
	get_tree().quit(0 if ok else 8)


func _finish_capture() -> void:
	if not _out_path.is_empty():
		await _capture_or_ab()
	else:
		print("SWAP episode done (%.1fs, style=%s)" % [OS.get_environment("SWAP_WAIT").to_float(), "organic" if organic else "original"])
		get_tree().quit(0)


## --- perf: stress the REAL arena -------------------------------------------
##
## One style per PROCESS (SWAP_PERF_ONE). The first version looped the four
## configurations inside a single run and produced nonsense: the first config paid
## the shader compile, and every config inherited a world the previous one had
## already eaten (draw calls fell from 2014 to 972 between configs). A fresh
## process per configuration starts from the same seeded stress layout, so the
## only variable is the body under test.

func _run_perf_one() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var arena := main.arena
	var player := arena.player
	player.max_hp = 5000.0
	player.hp = player.max_hp
	player.mass = 92.0
	player._sync_mass_metrics()
	# SWAP_PERF_BODY=<n> is a SYNTHETIC body-only micro-benchmark: no enemies, the
	# body scaled n times so it covers most of the screen, which makes the
	# fragment cost of the body shader measurable instead of lost in the arena's
	# CPU-bound draw-call load. It is not a gameplay scenario.
	var body_scale := _env_float("SWAP_PERF_BODY", 0.0)
	if body_scale > 0.0:
		player.visual.scale = Vector2(body_scale, body_scale)
	# Visual mutations only: shield/electro/ranged_absorb keep their effects on
	# screen without the damage mutations deleting the stress population.
	for mid in ["shield", "electro_discharge", "ranged_absorb", "dash"]:
		player.mutations.levels[mid] = 3
	player._sync_mass_metrics()
	player.visual.evolution_flash = 0.0
	if body_scale <= 0.0:
		var boss := arena.spawn_ancient_guardian_boss()
		boss.global_position = player.global_position + Vector2(300.0, 0.0)
		for i in range(32):
			var ang := (TAU / 32.0) * float(i)
			arena.spawn_enemy_by_id(ConfigDB.enemy_order[i % ConfigDB.enemy_order.size()],
				player.global_position + Vector2.from_angle(ang) * 420.0)
		for i in range(45):
			arena._spawn_orb(player.global_position + Vector2.from_angle(float(i) * 0.4) * 300.0, "spore", 0.4, 5.0, 0)
		_move = true
		_dash = true

	for _w in range(120):
		await get_tree().process_frame

	var live := _count_population()
	var samples: Array[float] = []
	for _f in range(300):
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var sum := 0.0
	for s in samples:
		sum += s
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("SWAP_PERF_ONE style=%s quality=%d size=%s frames=%d avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f draw_calls=%d pop_start=%s pop_end=%s" % [
		"organic" if organic else "original", quality if organic else -1,
		OS.get_environment("SWAP_SIZE"), samples.size(), sum / float(samples.size()),
		samples[int(samples.size() * 0.50)], samples[int(samples.size() * 0.95)],
		samples[samples.size() - 1], draws, live, _count_population()])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	get_tree().quit(0)


func _count_population() -> String:
	var enemies := 0
	for node in main.arena.enemy_grid.query_radius(main.arena.player.global_position, 900.0):
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			enemies += 1
	return "enemies=%d orbs=%d" % [enemies, main.arena._orbs_layer.get_child_count()]
