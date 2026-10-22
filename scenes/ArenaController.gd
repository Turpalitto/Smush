class_name ArenaController
extends Node2D
## Orchestrates an active run inside the Enchanted Forest biome:
## Camera, WorldGenerator, PlayerSlime, SpatialHashGrid, ObjectPools, Enemy waves,
## Elite Mini-Boss, 3-Phase Ancient Guardian Boss, Mutation Drafts, Revive, and Rewards.

const MAX_ACTIVE_ENEMIES: int = 44
const MAX_ACTIVE_ORBS: int = 85
const MAX_ACTIVE_HAZARDS: int = 48

var world: WorldGenerator
var player: PlayerSlime
var camera: Camera2D
var tutorial: TutorialManager
var canopy_bg: CanvasLayer
var canopy_rect: ColorRect
var canopy_mat: ShaderMaterial

var enemy_grid: SpatialHashGrid = SpatialHashGrid.new(180.0)
var orb_grid: SpatialHashGrid = SpatialHashGrid.new(160.0)

var enemy_pool: ObjectPool
var orb_pool: ObjectPool
var hazard_pool: ObjectPool
var fx_pool: ObjectPool

var active_clones: Array[SlimeClone] = []
var active_boss: AncientGuardianBoss = null

var mode_id: String = "standard"
var run_elapsed: float = 0.0
var boss_spawn_time: float = 270.0 # 4:30 boss awakening -> ~5-7 min total run
var miniboss_spawn_time: float = 165.0
var miniboss_spawned: bool = false
var boss_spawned: bool = false
var run_ended: bool = false

var run_essence_earned: int = 0
var reward_doubled: bool = false
var free_rerolls_left: int = 0
var current_draft_choices: Array[Dictionary] = []

var _enemy_spawn_timer: float = 0.5
var _orb_spawn_timer: float = 0.3
var _narrow_toast_cd: float = 0.0

var _entities_layer: Node2D
var _hazards_layer: Node2D
var _orbs_layer: Node2D
var _fx_layer: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_canopy_background()

	world = WorldGenerator.new()
	world.name = "EnchantedForest"
	add_child(world)

	_hazards_layer = Node2D.new()
	_hazards_layer.name = "Hazards"
	add_child(_hazards_layer)

	_orbs_layer = Node2D.new()
	_orbs_layer.name = "Orbs"
	add_child(_orbs_layer)

	_entities_layer = Node2D.new()
	_entities_layer.name = "Entities"
	add_child(_entities_layer)

	_fx_layer = Node2D.new()
	_fx_layer.name = "FX"
	add_child(_fx_layer)

	player = PlayerSlime.new()
	player.name = "PlayerSlime"
	_entities_layer.add_child(player)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	camera.limit_left = int(-WorldGenerator.ARENA_HALF_SIZE - 90.0)
	camera.limit_right = int(WorldGenerator.ARENA_HALF_SIZE + 90.0)
	camera.limit_top = int(-WorldGenerator.ARENA_HALF_SIZE - 90.0)
	camera.limit_bottom = int(WorldGenerator.ARENA_HALF_SIZE + 90.0)
	player.add_child(camera)

	tutorial = TutorialManager.new()
	add_child(tutorial)

	enemy_pool = ObjectPool.new(_entities_layer, func() -> Node2D: return EnemyEntity.new(), MAX_ACTIVE_ENEMIES, 14)
	orb_pool = ObjectPool.new(_orbs_layer, func() -> Node2D: return CollectibleOrb.new(), MAX_ACTIVE_ORBS, 24)
	hazard_pool = ObjectPool.new(_hazards_layer, func() -> Node2D: return HazardZone.new(), MAX_ACTIVE_HAZARDS, 10)
	fx_pool = ObjectPool.new(_fx_layer, func() -> Node2D: return BurstFX.new(), 40, 8)


func _setup_canopy_background() -> void:
	canopy_bg = CanvasLayer.new()
	canopy_bg.layer = -10
	add_child(canopy_bg)
	canopy_rect = ColorRect.new()
	canopy_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canopy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := load("res://shaders/forest_canopy.gdshader") as Shader
	if sh != null:
		canopy_mat = ShaderMaterial.new()
		canopy_mat.shader = sh
		canopy_rect.material = canopy_mat
	else:
		canopy_rect.color = Color(0.07, 0.16, 0.18)
	canopy_bg.add_child(canopy_rect)


func start_new_run(p_mode: String = "standard", world_seed: int = 0) -> void:
	mode_id = p_mode
	run_elapsed = 0.0
	_enemy_spawn_timer = 0.5
	_orb_spawn_timer = 0.3
	_narrow_toast_cd = 0.0
	current_draft_choices.clear()
	run_ended = false
	miniboss_spawned = false
	boss_spawned = false
	run_essence_earned = 0
	reward_doubled = false
	free_rerolls_left = 1 if SaveData.has_no_ads() else 0

	if mode_id == "quick":
		miniboss_spawn_time = 80.0
		boss_spawn_time = 145.0
	else:
		miniboss_spawn_time = 165.0
		boss_spawn_time = 270.0

	Ads.reset_run_limits()
	enemy_pool.release_all()
	orb_pool.release_all()
	hazard_pool.release_all()
	fx_pool.release_all()
	enemy_grid.clear()
	orb_grid.clear()

	for cl in active_clones:
		if is_instance_valid(cl):
			cl.queue_free()
	active_clones.clear()

	if active_boss != null and is_instance_valid(active_boss):
		active_boss.queue_free()
		active_boss = null

	world.generate_world(world_seed)
	player.global_position = Vector2.ZERO
	player.initialize_for_run(self)

	# Populate initial welcoming spores & passive creatures around central clearing
	for _i in range(26):
		var opos := world.pick_valid_spawn_point(Vector2.ZERO, 95.0, 620.0)
		_spawn_orb(opos, "spore", 0.9, 6.0, 0)
	for _i in range(7):
		var mpos := world.pick_valid_spawn_point(Vector2.ZERO, 175.0, 480.0)
		spawn_enemy_by_id("tiny_mushroom", mpos)
	for _i in range(3):
		var bpos := world.pick_valid_spawn_point(Vector2.ZERO, 240.0, 560.0)
		spawn_enemy_by_id("forest_beetle", bpos)

	SaveData.increment_stat("total_runs", 1.0)
	SaveData.save_to_disk()
	Analytics.track("run_started", {"mode": mode_id})
	Events.run_started.emit(mode_id)
	tutorial.begin_if_needed()
	App.change_state(App.State.PLAYING)


func _physics_process(delta: float) -> void:
	if run_ended or App.state != App.State.PLAYING:
		return

	run_elapsed += delta
	if _narrow_toast_cd > 0.0:
		_narrow_toast_cd -= delta

	Events.run_timer_updated.emit(run_elapsed, boss_spawn_time)

	if canopy_mat != null:
		canopy_mat.set_shader_parameter("world_offset", player.global_position)

	# Subtle camera zoom-out as slime grows so battlefield stays readable on phone screens
	if camera != null:
		var target_zoom_f := lerpf(1.04, 0.80, clampf((player.mass - 10.0) / 110.0, 0.0, 1.0))
		camera.zoom = camera.zoom.lerp(Vector2(target_zoom_f, target_zoom_f), 1.0 - exp(-3.0 * delta))

	if player.velocity.length() > 45.0:
		tutorial.notify_player_moved()

	_rebuild_spatial_grids()
	_process_spawning_and_waves(delta)
	_process_orb_interactions(delta)
	if App.state != App.State.PLAYING:
		return
	_process_enemy_interactions(delta)
	if App.state != App.State.PLAYING:
		return
	_process_boss_interactions(delta)
	_cleanup_pools()


func _rebuild_spatial_grids() -> void:
	enemy_grid.clear()
	for node in enemy_pool.get_active_items():
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			enemy_grid.insert(en, en.global_position)

	orb_grid.clear()
	for node in orb_pool.get_active_items():
		if is_instance_valid(node) and node.visible:
			orb_grid.insert(node, node.global_position)


func _process_spawning_and_waves(delta: float) -> void:
	if not miniboss_spawned and run_elapsed >= miniboss_spawn_time:
		miniboss_spawned = true
		var mb_cfg: Dictionary = ConfigDB.special_encounters.get("umbral_alpha", {})
		if not mb_cfg.is_empty():
			var pos := world.pick_valid_spawn_point(player.global_position, 340.0, 520.0)
			var en := enemy_pool.acquire() as EnemyEntity
			if en != null:
				en.setup_from_config(mb_cfg, pos, self, 1.0)
				Events.miniboss_spawned.emit("umbral_alpha")
				Events.toast_requested.emit(Loc.t("hud.miniboss_incoming"), Color(0.86, 0.55, 1.0))

	if not boss_spawned and run_elapsed >= boss_spawn_time:
		spawn_ancient_guardian_boss()

	_orb_spawn_timer -= delta
	if _orb_spawn_timer <= 0.0:
		_orb_spawn_timer = 0.65
		if orb_pool.active_count() < MAX_ACTIVE_ORBS - 6:
			var opos := world.pick_valid_spawn_point(player.global_position, 150.0, 680.0)
			var is_ess := randf() < (0.10 + SaveData.get_upgrade_bonus("essence_chance") * 0.25)
			_spawn_orb(opos, "essence" if is_ess else "spore", 0.95, 6.5, 1 if is_ess else 0)

	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0.0:
		var pace := 1.55 if not boss_spawned else 2.8
		_enemy_spawn_timer = pace
		if enemy_pool.active_count() < MAX_ACTIVE_ENEMIES - 4:
			var chosen_id := _pick_weighted_enemy_for_time(run_elapsed)
			var epos := world.pick_valid_spawn_point(player.global_position, 340.0, 680.0)
			spawn_enemy_by_id(chosen_id, epos)


func _pick_weighted_enemy_for_time(t_sec: float) -> String:
	var time_equiv := t_sec * (1.85 if mode_id == "quick" else 1.0)
	var eligible: Array[Dictionary] = []
	var total_w: int = 0
	for eid in ConfigDB.enemy_order:
		var cfg: Dictionary = ConfigDB.enemies[eid]
		if time_equiv >= float(cfg.get("min_run_time", 0.0)):
			eligible.append(cfg)
			total_w += int(cfg.get("spawn_weight", 10))
	if eligible.is_empty():
		return "tiny_mushroom"
	var roll := randi() % maxi(1, total_w)
	var acc: int = 0
	for cfg in eligible:
		acc += int(cfg.get("spawn_weight", 10))
		if roll < acc:
			return str(cfg["id"])
	return str(eligible[0]["id"])


func spawn_enemy_by_id(enemy_id: String, pos: Vector2) -> EnemyEntity:
	var cfg := ConfigDB.get_enemy(enemy_id)
	if cfg.is_empty():
		return null
	var en := enemy_pool.acquire() as EnemyEntity
	if en == null:
		return null
	var diff_scale := 1.0 + clampf(run_elapsed / 320.0, 0.0, 0.65)
	en.setup_from_config(cfg, pos, self, diff_scale)
	return en


func spawn_ancient_guardian_boss() -> AncientGuardianBoss:
	if boss_spawned and active_boss != null and is_instance_valid(active_boss):
		return active_boss
	boss_spawned = true
	var bcfg: Dictionary = ConfigDB.special_encounters.get("ancient_guardian", {})
	var bpos := world.pick_valid_spawn_point(player.global_position, 320.0, 480.0)
	active_boss = AncientGuardianBoss.new()
	_entities_layer.add_child(active_boss)
	active_boss.setup_boss(bcfg, bpos, self)
	Analytics.track("boss_encountered", {"boss": "ancient_guardian", "elapsed_sec": int(run_elapsed)})
	Events.toast_requested.emit(Loc.t("hud.boss_incoming"), Color(1.0, 0.78, 0.35))
	return active_boss


func spawn_boss_minions(boss_pos: Vector2, count: int) -> void:
	for i in range(count):
		var ang := (TAU / float(maxi(1, count))) * float(i)
		var mpos := clamp_world_point(boss_pos + Vector2.from_angle(ang) * 115.0, 24.0)
		var mid := "tiny_mushroom" if (i % 2 == 0) else "electric_beetle"
		spawn_enemy_by_id(mid, mpos)


func _spawn_orb(pos: Vector2, otype: String, mass_val: float, xp_val: float, ess_val: int) -> CollectibleOrb:
	var orb := orb_pool.acquire() as CollectibleOrb
	if orb != null:
		orb.setup(pos, otype, mass_val, xp_val, ess_val)
	return orb


func _spawn_burst(pos: Vector2, col: Color, count: int = 8, ring_r: float = 0.0) -> void:
	var budget := App.get_fx_particle_budget()
	if fx_pool.active_count() >= budget:
		return
	var fx := fx_pool.acquire() as BurstFX
	if fx != null:
		var scaled_cnt := maxi(3, int(round(float(count) * (float(budget) / 80.0))))
		fx.setup(pos, col, scaled_cnt, ring_r)


# --- Player & World Interactions ---

func clamp_world_point(pos: Vector2, radius: float) -> Vector2:
	var lim := WorldGenerator.ARENA_HALF_SIZE - radius
	return Vector2(clampf(pos.x, -lim, lim), clampf(pos.y, -lim, lim))


func constrain_player_position(pos: Vector2, p_radius: float, is_dashing: bool) -> Vector2:
	var out := clamp_world_point(pos, p_radius)
	# Narrow passage tactical check: giant slimes cannot squeeze through narrow root gates unless dashing/smaller
	for gate: Dictionary in world.narrow_gates:
		var gc: Vector2 = gate["center"]
		var half_gap: float = float(gate["half_gap"])
		var d := out.distance_to(gc)
		if d < 42.0 and not MassSystem.can_fit_narrow_passage(player.mass, half_gap, is_dashing):
			var push_dir := (out - gc).normalized()
			if push_dir.length_squared() < 0.01:
				push_dir = Vector2.DOWN
			out = gc + push_dir * 42.0
			if _narrow_toast_cd <= 0.0:
				_narrow_toast_cd = 3.5
				Events.narrow_passage_blocked.emit()
				Events.toast_requested.emit(Loc.t("hud.narrow_hint"), Color(1.0, 0.82, 0.45))
	return out


func _process_orb_interactions(_delta: float) -> void:
	var pr := player.get_radius()
	var auto_suck: bool = bool(SaveData.get_setting("auto_absorb", true))
	var scan_r := pr + (36.0 if auto_suck else 10.0)
	var nearby := orb_grid.query_radius(player.global_position, scan_r)
	for node in nearby:
		if App.state != App.State.PLAYING:
			break
		var orb := node as CollectibleOrb
		if orb == null or not orb.visible:
			continue
		var d := orb.global_position.distance_to(player.global_position)
		if auto_suck and d <= scan_r:
			orb.start_suction(player)
		if d <= pr + 12.0:
			var pos := orb.global_position
			var mv := orb.mass_value
			var xv := orb.xp_value
			var ev := orb.essence_value
			var ocol := orb.orb_color
			orb_pool.release(orb)
			_spawn_burst(pos, ocol, 6, 0.0)
			player.complete_absorption("spore_orb", mv, xv, ev, pos)
			tutorial.notify_entity_absorbed()


func _process_enemy_interactions(delta: float) -> void:
	var pr := player.get_radius()
	var auto_absorb: bool = bool(SaveData.get_setting("auto_absorb", true))
	var query_r := pr + 62.0
	var candidates := enemy_grid.query_radius(player.global_position, query_r)
	var p_ctx := player.mutations.build_player_absorption_context(player.mass, player.is_dashing, player.mimicry_ambush_ready)

	for node in candidates:
		if App.state != App.State.PLAYING:
			break
		var en := node as EnemyEntity
		if en == null or not en.is_active_combatant():
			continue
		var touch_dist := pr + en.get_body_radius() + (14.0 if auto_absorb else 2.0)
		var dist := en.global_position.distance_to(player.global_position)
		if dist > touch_dist:
			continue

		var eval_res := AbsorptionRules.evaluate(p_ctx, en.build_absorption_context())
		if bool(eval_res.get("cracks_shell", false)):
			en.crack_shell()

		if bool(eval_res.get("can_absorb", false)):
			en.begin_suction_into(player)
			continue

		# Not yet absorbable: apply Spikes / Piercing Strike contact damage!
		if player.mutations.has_mutation("spikes"):
			var spike_dps := player.mutations.get_scaled_param("spikes", "contact_dps_base", "contact_dps_per_level", 18.0)
			var pierce := float(player.mutations.get_level("spikes")) * 0.20
			if player.is_dashing and player.mutations.has_synergy("piercing_strike"):
				en.crack_shell()
				en.take_damage(48.0 * delta * 6.0, 1.0)
			else:
				en.take_damage(spike_dps * delta, pierce)

		# Enemy deals contact damage to player if able
		if en.can_deal_contact_hit() and dist <= pr + en.get_body_radius():
			en.mark_contact_hit_dealt()
			player.take_damage(en.contact_damage, en.enemy_id, false, en.global_position)


func _process_boss_interactions(delta: float) -> void:
	if active_boss == null or not is_instance_valid(active_boss) or active_boss.action_state == AncientGuardianBoss.ActionState.DEFEATED:
		return
	var pr := player.get_radius()
	var br := active_boss.get_body_radius()
	var dist := active_boss.global_position.distance_to(player.global_position)
	if dist > pr + br + 10.0:
		return

	var p_ctx := player.mutations.build_player_absorption_context(player.mass, player.is_dashing, player.mimicry_ambush_ready)
	var eval_res := AbsorptionRules.evaluate(p_ctx, active_boss.build_absorption_context())
	if bool(eval_res.get("can_absorb", false)):
		active_boss.take_damage(9999.0, 1.0)
		return

	# Player contact / dash / spikes / collision damage against boss (especially strong when boss is vulnerable!)
	var base_ram_dps := 22.0 + player.mass * 0.45
	if player.mutations.has_mutation("spikes"):
		base_ram_dps += player.mutations.get_scaled_param("spikes", "contact_dps_base", "contact_dps_per_level", 18.0)
	if player.is_dashing:
		base_ram_dps *= (2.4 if player.mutations.has_synergy("piercing_strike") else 1.5)
	if player.mimicry_ambush_ready:
		base_ram_dps *= 1.45
	active_boss.take_damage(base_ram_dps * delta, float(player.mutations.get_level("spikes")) * 0.15)

	if active_boss.can_deal_contact_hit() and not active_boss.is_vulnerable():
		active_boss.mark_contact_hit_dealt()
		player.take_damage(active_boss.contact_damage, active_boss.boss_id, false, active_boss.global_position)


func finalize_enemy_suction(en: EnemyEntity) -> void:
	if en == null:
		return
	var pos := en.global_position
	var ess_drop := _roll_essence_drop(en.essence_chance, en.essence_amount)
	if en.enemy_id == "stone_slug":
		SaveData.increment_stat("armored_defeated", 1.0)
	_spawn_burst(pos, en.color_primary, 10, en.get_body_radius() * 1.4)
	player.complete_absorption(en.enemy_id, en.mass_gain, en.xp_reward, ess_drop, pos)
	tutorial.notify_entity_absorbed()
	enemy_pool.release(en)


func on_enemy_killed(en: EnemyEntity) -> void:
	if en == null:
		return
	var pos := en.global_position
	var ess_drop := _roll_essence_drop(en.essence_chance, en.essence_amount)
	if en.enemy_id == "stone_slug":
		SaveData.increment_stat("armored_defeated", 1.0)
	_spawn_burst(pos, en.color_primary, 12, en.get_body_radius() * 1.6)
	# Drop edible essence/biomass orb on combat kill
	_spawn_orb(pos, "essence" if ess_drop > 0 else "spore", en.mass_gain * 0.85, en.xp_reward, ess_drop)
	SaveData.record_creature_seen(en.enemy_id, 1)
	enemy_pool.release(en)


func _roll_essence_drop(base_chance: float, base_amt: int) -> int:
	if base_chance >= 1.0:
		return base_amt
	var bonus := SaveData.get_upgrade_bonus("essence_chance")
	if randf() <= clampf(base_chance + bonus, 0.0, 0.98):
		var extra: int = 1 if (bonus >= 0.24 and randf() < 0.35) else 0
		return base_amt + extra
	return 0


func add_run_essence(amount: int) -> void:
	if amount <= 0:
		return
	run_essence_earned += amount
	Events.essence_collected.emit(amount, run_essence_earned)


# --- Mutation & Hazard Callbacks ---

func apply_magnet_field(center: Vector2, radius: float, force: float, delta: float, pull_enemies: bool) -> void:
	for node in orb_grid.query_radius(center, radius):
		var orb := node as CollectibleOrb
		if orb != null:
			orb.global_position = orb.global_position.move_toward(center, force * delta)
	if pull_enemies:
		for node in enemy_grid.query_radius(center, radius * 0.85):
			var en := node as EnemyEntity
			if en != null and en.is_active_combatant():
				en.global_position = en.global_position.move_toward(center, 135.0 * delta)


func trigger_electro_pulse(center: Vector2, radius: float, damage: float, max_targets: int, stun_sec: float) -> void:
	var hit: int = 0
	for node in enemy_grid.query_radius(center, radius):
		if hit >= max_targets:
			break
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			en.crack_shell()
			en.apply_stun(stun_sec)
			en.take_damage(damage, 0.5)
			_spawn_burst(en.global_position, Color(1.0, 0.94, 0.40), 6, 26.0)
			hit += 1
	if active_boss != null and is_instance_valid(active_boss) and hit < max_targets:
		if active_boss.global_position.distance_to(center) <= radius + active_boss.get_body_radius():
			active_boss.take_damage(damage * 1.15, 0.4)
			_spawn_burst(active_boss.global_position, Color(1.0, 0.94, 0.40), 7, 36.0)
			hit += 1
	if hit > 0:
		Audio.play_sfx("attack", 1.32)


func trigger_freeze_pulse(center: Vector2, radius: float, slow_amt: float, dur: float) -> void:
	var any_hit := false
	for node in enemy_grid.query_radius(center, radius):
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			en.apply_freeze(slow_amt, dur)
			any_hit = true
	if active_boss != null and is_instance_valid(active_boss):
		if active_boss.global_position.distance_to(center) <= radius + active_boss.get_body_radius():
			active_boss.apply_freeze(slow_amt, dur)
			any_hit = true
	if any_hit:
		_spawn_burst(center, Color(0.65, 0.94, 1.0), 8, radius)


func process_ranged_tendrils(p_slime: PlayerSlime, center: Vector2, rng: float, reel_spd: float, dt: float, has_vampirism: bool) -> Array[Vector2]:
	var endpoints: Array[Vector2] = []
	var p_ctx := p_slime.mutations.build_player_absorption_context(p_slime.mass, p_slime.is_dashing, p_slime.mimicry_ambush_ready)
	for node in enemy_grid.query_radius(center, rng):
		if endpoints.size() >= 2:
			break
		var en := node as EnemyEntity
		if en == null or not en.is_active_combatant():
			continue
		var ev := AbsorptionRules.evaluate(p_ctx, en.build_absorption_context())
		if bool(ev.get("can_absorb", false)):
			en.global_position = en.global_position.move_toward(center, reel_spd * dt)
			endpoints.append(en.global_position)
		elif has_vampirism:
			en.take_damage(18.0 * dt, 0.35)
			p_slime.heal(8.0 * dt)
			endpoints.append(en.global_position)

	if has_vampirism and endpoints.size() < 2 and active_boss != null and is_instance_valid(active_boss):
		if active_boss.global_position.distance_to(center) <= rng + active_boss.get_body_radius():
			active_boss.take_damage(22.0 * dt, 0.35)
			p_slime.heal(9.0 * dt)
			endpoints.append(active_boss.global_position)
	return endpoints


func on_player_shield_burst(center: Vector2, is_ice_armor: bool) -> void:
	var burst_r := 165.0 if is_ice_armor else 125.0
	_spawn_burst(center, Color(0.68, 0.95, 1.0), 12, burst_r)
	for node in enemy_grid.query_radius(center, burst_r):
		var en := node as EnemyEntity
		if en == null or not en.is_active_combatant():
			continue
		var push := (en.global_position - center).normalized() * 90.0
		en.global_position = clamp_world_point(en.global_position + push, en.get_body_radius())
		if is_ice_armor:
			en.apply_freeze(0.68, 2.8)
			en.take_damage(30.0, 0.5)


func spawn_slime_clones(owner_slime: PlayerSlime, count: int, dur: float, dps: float, is_toxic: bool, loaned_each: float) -> void:
	for i in range(count):
		var cl := SlimeClone.new()
		_entities_layer.add_child(cl)
		var off := Vector2.from_angle(float(i) * PI + 0.5) * 36.0
		cl.setup(owner_slime, self, owner_slime.global_position + off, dur, dps, is_toxic, loaned_each)
		active_clones.append(cl)


func find_clone_target(from_pos: Vector2) -> Variant:
	var near_orb := orb_grid.query_nearest(from_pos, 260.0)
	if near_orb != null:
		return near_orb.global_position
	var near_en := enemy_grid.query_nearest(from_pos, 280.0)
	if near_en != null:
		return near_en.global_position
	return null


func process_clone_contacts(_clone: SlimeClone, pos: Vector2, radius: float, dmg: float) -> void:
	for node in orb_grid.query_radius(pos, radius + 16.0):
		var orb := node as CollectibleOrb
		if orb != null and orb.visible:
			var mv := orb.mass_value
			var xv := orb.xp_value
			var ev := orb.essence_value
			var opos := orb.global_position
			orb_pool.release(orb)
			player.complete_absorption("spore_orb", mv, xv, ev, opos)
	for node in enemy_grid.query_radius(pos, radius + 22.0):
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			en.take_damage(dmg, 0.25)


func spawn_player_poison_pool(pos: Vector2, radius: float, dur: float, dps: float) -> void:
	var hz := hazard_pool.acquire() as HazardZone
	if hz != null:
		hz.setup(pos, HazardZone.Kind.PLAYER_POISON, radius, dur, dps, self)


func spawn_enemy_poison_pool(pos: Vector2, radius: float, dur: float, dps: float) -> void:
	var hz := hazard_pool.acquire() as HazardZone
	if hz != null:
		hz.setup(pos, HazardZone.Kind.ENEMY_POISON, radius, dur, dps, self)


func spawn_enemy_telegraph_blast(pos: Vector2, radius: float, delay: float, dmg: float) -> void:
	var hz := hazard_pool.acquire() as HazardZone
	if hz != null:
		hz.setup(pos, HazardZone.Kind.ENEMY_TELEGRAPH_BLAST, radius, delay + 0.30, dmg, self, delay)


func spawn_boss_telegraph_slam(pos: Vector2, radius: float, delay: float, dmg: float) -> void:
	var hz := hazard_pool.acquire() as HazardZone
	if hz != null:
		hz.setup(pos, HazardZone.Kind.BOSS_TELEGRAPH_SLAM, radius, delay + 0.32, dmg, self, delay)


func apply_player_poison_tick(center: Vector2, radius: float, dmg: float) -> void:
	for node in enemy_grid.query_radius(center, radius + 18.0):
		var en := node as EnemyEntity
		if en != null and en.is_active_combatant():
			en.apply_poison(1.4)
			en.take_damage(dmg, 0.20)
	if active_boss != null and is_instance_valid(active_boss):
		if active_boss.global_position.distance_to(center) <= radius + active_boss.get_body_radius():
			active_boss.take_damage(dmg * 0.85, 0.15)


func apply_enemy_poison_tick(center: Vector2, radius: float, dmg: float) -> void:
	if player.global_position.distance_to(center) <= radius + player.get_radius() * 0.8:
		player.take_damage(dmg, "poison_pool", true)


func apply_enemy_aoe_burst(center: Vector2, radius: float, dmg: float, is_boss_slam: bool) -> void:
	if player.global_position.distance_to(center) <= radius + player.get_radius() * 0.75:
		player.take_damage(dmg, "boss_slam" if is_boss_slam else "electric_burst", true, center)


func _cleanup_pools() -> void:
	var hz_items := hazard_pool.get_active_items().duplicate()
	for node in hz_items:
		var hz := node as HazardZone
		if hz != null and hz.is_expired():
			hazard_pool.release(hz)

	var fx_items := fx_pool.get_active_items().duplicate()
	for node in fx_items:
		var fx := node as BurstFX
		if fx != null and fx.is_expired():
			fx_pool.release(fx)

	for i in range(active_clones.size() - 1, -1, -1):
		var cl := active_clones[i]
		if not is_instance_valid(cl):
			active_clones.remove_at(i)
		elif cl.is_expired():
			if cl.leaves_toxic_trail:
				apply_player_poison_tick(cl.global_position, 115.0, 38.0)
				_spawn_burst(cl.global_position, Color(0.62, 1.0, 0.35), 10, 115.0)
			player.refund_clone_mass(cl.loaned_mass)
			cl.queue_free()
			active_clones.remove_at(i)


# --- Draft, Victory, Defeat & Revive Flows ---

func request_mutation_draft() -> void:
	if App.state == App.State.MUTATION_DRAFT:
		return
	current_draft_choices = player.mutations.roll_draft_choices(3)
	if current_draft_choices.is_empty():
		# All unlocked mutations maxed out: bonus heal + essence!
		player.heal(25.0)
		add_run_essence(5)
		return
	Ads.notify_offered(Ads.PLACEMENT_EXTRA_MUTATION)
	App.change_state(App.State.MUTATION_DRAFT)
	Events.mutation_draft_requested.emit(current_draft_choices)


func select_draft_mutation(mutation_id: String) -> void:
	if App.state != App.State.MUTATION_DRAFT:
		return
	var offered := false
	for choice in current_draft_choices:
		if str(choice.get("id", "")) == mutation_id:
			offered = true
			break
	if not offered or not player.mutations.can_upgrade_mutation(mutation_id):
		return
	Audio.play_sfx("mutation_pick", 1.0)
	player.mutations.apply_mutation(mutation_id)
	player._sync_mass_metrics()
	tutorial.notify_mutation_picked()
	current_draft_choices.clear()
	App.change_state(App.State.PLAYING)
	# Offer every earned evolution before returning to combat.
	player.add_evolution_xp(0.0)


func reroll_draft_choices() -> bool:
	if App.state != App.State.MUTATION_DRAFT:
		return false
	if free_rerolls_left > 0:
		free_rerolls_left -= 1
		current_draft_choices = player.mutations.roll_draft_choices(3)
		Events.mutation_draft_requested.emit(current_draft_choices)
		return true
	return false


func reroll_draft_with_ad(done_cb: Callable = Callable()) -> void:
	Ads.request_rewarded_ad(Ads.PLACEMENT_EXTRA_MUTATION, func(granted: bool, reason: String) -> void:
		if granted and App.state == App.State.MUTATION_DRAFT:
			current_draft_choices = player.mutations.roll_draft_choices(3)
			Events.mutation_draft_requested.emit(current_draft_choices)
		if done_cb.is_valid():
			done_cb.call(granted, reason)
	)


func on_boss_defeated(_boss: AncientGuardianBoss) -> void:
	if run_ended:
		return
	SaveData.record_creature_seen("ancient_guardian", 1)
	SaveData.increment_stat("bosses_defeated", 1.0)
	SaveData.increment_stat("victories", 1.0)
	add_run_essence(45)
	Analytics.track("boss_defeated", {"boss": "ancient_guardian", "elapsed_sec": int(run_elapsed)})
	Audio.play_sfx("victory", 1.0)
	_finish_run(true)


func on_player_died() -> void:
	if run_ended:
		return
	Audio.play_sfx("defeat", 1.0)
	# Offer voluntary revive if not yet used this run; player may accept or finish run
	Ads.notify_offered(Ads.PLACEMENT_REVIVE)
	_finish_run(false)


func _finish_run(victory: bool) -> void:
	run_ended = not (not victory and not player.revive_used)
	# Base participation reward guarantees meaningful early progression even on defeat!
	var time_bonus: int = maxi(8, int(run_elapsed * 0.14))
	var mass_bonus: int = int(maxf(0.0, player.peak_mass - 10.0) * 0.45)
	var victory_bonus: int = 30 if victory else 0
	var total_essence := run_essence_earned + time_bonus + mass_bonus + victory_bonus

	App.last_run_summary = {
		"victory": victory,
		"mode": mode_id,
		"duration_sec": run_elapsed,
		"peak_mass": snappedf(player.peak_mass, 0.1),
		"absorbed": player.absorbed_count,
		"mutations_count": player.mutations.get_total_picks(),
		"synergies": player.mutations.active_synergies.keys(),
		"base_essence": total_essence,
		"final_essence": total_essence,
		"can_revive": (not victory) and (not player.revive_used),
		"essence_committed": false
	}

	if victory:
		commit_run_rewards()
		Ads.notify_offered(Ads.PLACEMENT_DOUBLE_REWARD)
		App.change_state(App.State.VICTORY)
	else:
		Ads.notify_offered(Ads.PLACEMENT_DOUBLE_REWARD)
		App.change_state(App.State.DEFEAT)

	Events.run_finished.emit(victory, App.last_run_summary)


func commit_run_rewards() -> void:
	if App.last_run_summary.is_empty():
		return
	if bool(App.last_run_summary.get("essence_committed", false)):
		return
	App.last_run_summary["essence_committed"] = true
	App.last_run_summary["can_revive"] = false
	var amt: int = int(App.last_run_summary.get("final_essence", 0))
	SaveData.add_essence(amt)
	var dur: float = float(App.last_run_summary.get("duration_sec", 0.0))
	SaveData.increment_stat("total_playtime_sec", dur)
	SaveData.save_to_disk()
	Analytics.track("run_finished", {
		"victory": bool(App.last_run_summary.get("victory", false)),
		"essence": amt,
		"peak_mass": float(App.last_run_summary.get("peak_mass", 10.0))
	})
	Analytics.track("run_duration", {"seconds": int(dur)})


func try_revive_with_ad(done_cb: Callable = Callable()) -> void:
	if App.state != App.State.DEFEAT or player.revive_used or bool(App.last_run_summary.get("essence_committed", false)):
		if done_cb.is_valid():
			done_cb.call(false, "revive_not_allowed")
		return
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, func(granted: bool, reason: String) -> void:
		if granted:
			run_ended = false
			player.revive_player()
			# Clear immediate hostile puddles around revived player
			for node in hazard_pool.get_active_items().duplicate():
				var hz := node as HazardZone
				if hz != null and hz.global_position.distance_to(player.global_position) < 160.0:
					hazard_pool.release(hz)
			App.last_run_summary.clear()
			App.change_state(App.State.PLAYING)
		if done_cb.is_valid():
			done_cb.call(granted, reason)
	)


func try_double_run_reward_with_ad(done_cb: Callable = Callable()) -> void:
	if reward_doubled or App.last_run_summary.is_empty():
		if done_cb.is_valid():
			done_cb.call(false, "already_doubled")
		return
	# Ensure base reward is committed once first
	commit_run_rewards()
	Ads.request_rewarded_ad(Ads.PLACEMENT_DOUBLE_REWARD, func(granted: bool, reason: String) -> void:
		if granted and not reward_doubled:
			reward_doubled = true
			var bonus: int = int(App.last_run_summary.get("base_essence", 0))
			SaveData.add_essence(bonus)
			App.last_run_summary["final_essence"] = bonus * 2
		if done_cb.is_valid():
			done_cb.call(granted, reason)
	)
