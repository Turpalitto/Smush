class_name LakeCombat
extends Node2D
## Real enemies and the real boss on the lake (plan section 13: game systems on water). The shipped EnemyEntity,
## AncientGuardianBoss and HazardZone are hosted here through the small "arena contract" they call on their arena
## reference (player, clamp_world_point, on_enemy_killed, spawn_enemy_poison_pool, spawn_enemy_telegraph_blast,
## spawn_boss_telegraph_slam, spawn_boss_minions, spawn_boss_dew_spores, apply_enemy_aoe_burst, on_boss_defeated, ...).
## This adapter implements that contract WITHOUT touching ArenaController, SaveData, the pools or the economy; deaths only
## play effects. Contact and area damage reach the real PlayerSlime.take_damage. The lab never lets the slime die
## (it is healed back up when low) and shows a small HP bar for the slime and the boss.
##
## Not hosted yet (needs arena callbacks and the 2D visual that the painted hero hides): mutations, suction/absorbing
## enemies, drops. Keys/args are on LakeLegends (F skirmish, N Nova); `-- --lake-fight` starts the skirmish.

const BOSS_ID := "ancient_guardian"
## Waves (lab): calm prologue, then danger and reward grow the further the slime swims ("the further, the more extraordinary").
## Zone tables by world y: [enemy id, weight]. Prey (tiny_mushroom, firefly) are food that keeps the slime growing.
const WAVE_GLADE_Y := 780.0
const WAVE_GROVE_Y := 150.0
const WAVE_FAR_Y := -500.0
const WAVE_QUIET_SEC := 25.0          ## nothing hostile spawns during the first seconds
const WAVE_SPAWN_RING := Vector2(300.0, 470.0)
const WAVE_DESPAWN_DIST := 950.0
const WAVE_INTERVAL := Vector2(7.5, 3.0)   ## seconds between spawns at progress 0 / 1
const WAVE_MAX_ALIVE := Vector2(4.0, 12.0)
const BOSS_PROGRESS := 0.78
static var default_waves := true      ## tests switch this off before creating a lab
const SKIRMISH := ["forest_beetle", "forest_beetle", "firefly", "firefly", "stone_slug", "poison_toad", "poison_toad", "electric_beetle", "predator_flower", "shadow_slime"]

var lab: Node2D
var player: PlayerSlime               ## the arena contract reads `arena.player`
var enemies: Array[EnemyEntity] = []
var boss: AncientGuardianBoss = null
var kills := 0
var absorbed := 0
var mends := 0
var mass_gained := 0.0
var _boss_ram_cd := 0.0
var waves_enabled := default_waves
var _wave_timer := 3.0
var _wave_clock := 0.0
var waves_spawned := 0
var boss_gate_used := false
var progress := 0.0                    ## 0 at the start of the prologue .. 1 at the dive line
var boss_defeated_count := 0
var damage_dealt_to_player := 0.0
var _bar_player: ProgressBar
var _bar_boss: ProgressBar
var _boss_label: Label
var _rng := RandomNumberGenerator.new()


func setup(p_lab: Node2D) -> void:
	lab = p_lab
	player = lab.player
	if OS.get_cmdline_user_args().has("--lake-calm"):
		waves_enabled = false
	_rng.seed = 424242
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lake-seed="):
			_rng.seed = 424242 + int(a.trim_prefix("--lake-seed="))   # varies waves and spawn spots between autoplay runs
			seed(_rng.seed)   # and the global RNG used by the effects, so a run can be repeated
	z_index = 2
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_bar_player = _make_bar(layer, Vector2(20.0, 22.0), Vector2(250.0, 12.0), Color(0.35, 0.95, 0.7))
	_bar_boss = _make_bar(layer, Vector2(170.0, 60.0), Vector2(380.0, 14.0), Color(1.0, 0.4, 0.5))
	_boss_label = Label.new()
	_boss_label.position = Vector2(170.0, 36.0)
	_boss_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(_boss_label)
	_bar_boss.visible = false
	_boss_label.visible = false


func _make_bar(parent: Node, pos: Vector2, size: Vector2, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = size
	b.show_percentage = false
	b.max_value = 1.0
	b.value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.05, 0.12, 0.6)
	bg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	parent.add_child(b)
	return b


## --- the arena contract used by EnemyEntity / AncientGuardianBoss / HazardZone -------------------------

func clamp_world_point(pos: Vector2, radius: float) -> Vector2:
	var b: Rect2 = lab.play_bounds()
	return Vector2(clampf(pos.x, b.position.x + radius, b.end.x - radius), clampf(pos.y, b.position.y + radius, b.end.y - radius))


func find_nearest_clone_decoy(_from_pos: Vector2, _max_dist: float) -> Node2D:
	return null


func on_enemy_killed(en: EnemyEntity) -> void:
	if en == null:
		return
	kills += 1
	lab.spawn_fx("splash_crown", en.global_position, 0.45, 0.9, 0.9)
	lab.spawn_fx("bubbles", en.global_position, 0.4, 1.3, 0.8)
	enemies.erase(en)
	en.queue_free()


## Eaten, not killed: the slime grows through the same MassSystem formulas the game uses. The arena's version also
## writes SaveData statistics (total absorbed, creatures seen) and runs the tutorial and essence drops; the lab skips those
## on purpose, like Glade25D._absorb. Evolution XP is added (the evolution draft is hosted by LakeMutations).
func finalize_enemy_suction(en: EnemyEntity) -> void:
	if en == null:
		return
	absorbed += 1
	var pos := en.global_position
	var gain := MassSystem.effective_gain(player.mass, en.mass_gain)
	player.mass = MassSystem.clamp_mass(player.mass + gain)
	player._sync_mass_metrics()
	mass_gained += gain
	if lab.hero != null:
		lab.hero.gulp()
	lab.spawn_fx("bubbles", pos, 0.5, 1.4, 0.9)
	lab.spawn_fx("ripple_medium", pos, 0.6, 1.2, 0.8)
	lab.audio.absorb(lab._mass_strength())
	player.add_evolution_xp(en.xp_reward * (1.0 + SaveData.get_upgrade_bonus("evolution_rate")))
	enemies.erase(en)
	en.queue_free()


func spawn_enemy_poison_pool(pos: Vector2, radius: float, dur: float, dps: float) -> void:
	_hazard(pos, HazardZone.Kind.ENEMY_POISON, radius, dur, dps, 0.0)


func spawn_enemy_telegraph_blast(pos: Vector2, radius: float, delay: float, dmg: float) -> void:
	_hazard(pos, HazardZone.Kind.ENEMY_TELEGRAPH_BLAST, radius, delay + 0.30, dmg, delay)


func spawn_boss_telegraph_slam(pos: Vector2, radius: float, delay: float, dmg: float) -> void:
	_hazard(pos, HazardZone.Kind.BOSS_TELEGRAPH_SLAM, radius, delay + 0.30, dmg, delay)


func _hazard(pos: Vector2, kind: int, radius: float, dur: float, dmg: float, delay: float) -> void:
	var hz := HazardZone.new()
	hz.z_index = 1
	add_child(hz)
	hz.setup(pos, kind, radius, dur, dmg, self, delay)
	var tw := create_tween()
	tw.tween_interval(dur + 0.2)
	tw.tween_callback(hz.queue_free)


func apply_enemy_aoe_burst(pos: Vector2, radius: float, dmg: float, _is_boss: bool) -> void:
	lab.spawn_fx("splash_ring", pos, radius / 120.0, 0.9, 0.9)
	if player.global_position.distance_to(pos) <= radius + player.get_radius() * 0.5:
		_hurt_player(dmg, "enemy_blast", pos)


func apply_enemy_poison_tick(pos: Vector2, radius: float, dmg: float) -> void:
	if player.global_position.distance_to(pos) <= radius:
		_hurt_player(dmg, "poison_pool", pos)


func spawn_player_pool(pos: Vector2, radius: float, dur: float, dps: float) -> void:
	_hazard(pos, HazardZone.Kind.PLAYER_POISON, radius, dur, dps, 0.0)


## The slime's own poison trail wounds enemies standing in it (as in the arena).
func apply_player_poison_tick(pos: Vector2, radius: float, dmg: float) -> void:
	for en in enemies.duplicate():
		if is_instance_valid(en) and en.is_active_combatant() and en.global_position.distance_to(pos) <= radius + 18.0:
			en.apply_poison(1.4)
			en.take_damage(dmg, 0.2)
	if boss != null and is_instance_valid(boss) and boss.global_position.distance_to(pos) <= radius + boss.get_body_radius():
		boss.take_damage(dmg * 0.85, 0.15)


func spawn_boss_minions(boss_pos: Vector2, count: int) -> void:
	for i in range(count):
		var ang := TAU * float(i) / float(maxi(count, 1))
		spawn_enemy("forest_beetle", boss_pos + Vector2.from_angle(ang) * 70.0)


func spawn_boss_dew_spores(boss_pos: Vector2, _count: int) -> void:
	lab.spawn_fx("bubbles", boss_pos, 0.6, 1.4, 0.8)


func on_boss_defeated(_b: AncientGuardianBoss) -> void:
	boss_defeated_count += 1
	if boss != null:
		lab.spawn_fx("splash_ring", boss.global_position, 1.6, 1.6, 1.0)
		lab.spawn_fx("splash_crown", boss.global_position, 1.4, 1.6, 1.0)
		boss.queue_free()
	boss = null
	_bar_boss.visible = false
	_boss_label.visible = false


## --- hosting --------------------------------------------------------------------------------------------

func _hurt_player(dmg: float, source: String, from: Vector2) -> void:
	if player.take_damage(dmg, source, true, from):
		damage_dealt_to_player += dmg
		lab.audio.play("water_plip_02", -9.0, 0.7, 0.2)


func spawn_enemy(enemy_id: String, pos: Vector2, difficulty: float = 1.0) -> EnemyEntity:
	var cfg: Dictionary = ConfigDB.get_enemy(enemy_id)
	if cfg.is_empty():
		return null
	var en := EnemyEntity.new()
	en.z_index = 2
	add_child(en)
	en.setup_from_config(cfg, clamp_world_point(pos, 20.0), self, difficulty, 1.0)
	enemies.append(en)
	return en


func spawn_boss(pos: Vector2) -> AncientGuardianBoss:
	if boss != null:
		return boss
	var cfg: Dictionary = ConfigDB.get_enemy(BOSS_ID)
	if cfg.is_empty():
		return null
	var b := AncientGuardianBoss.new()
	b.z_index = 2
	add_child(b)
	b.setup_boss(cfg, clamp_world_point(pos, 40.0), self, 1.0, 1.0)
	boss = b
	_bar_boss.visible = true
	_boss_label.visible = true
	_boss_label.text = "Древний страж"
	return b


func start_skirmish() -> void:
	if not enemies.is_empty() or boss != null:
		return
	var pos: Vector2 = player.global_position
	for i in range(SKIRMISH.size()):
		var ang := _rng.randf() * TAU
		spawn_enemy(String(SKIRMISH[i]), pos + Vector2.from_angle(ang) * _rng.randf_range(260.0, 520.0))
	spawn_boss(pos + Vector2(0.0, -460.0))


func _physics_process(_delta: float) -> void:
	if lab == null or player == null:
		return
	var pr := player.get_radius()
	_boss_ram_cd = maxf(0.0, _boss_ram_cd - _delta)
	_update_waves(_delta)
	var p_ctx := player.mutations.build_player_absorption_context(player.mass, player.is_dashing, player.mimicry_ambush_ready)
	for en in enemies.duplicate():
		if not is_instance_valid(en):
			enemies.erase(en)
			continue
		var dist := player.global_position.distance_to(en.global_position)
		if en.is_active_combatant() and dist <= pr + en.get_body_radius() + 2.0:
			var res := AbsorptionRules.evaluate(p_ctx, en.build_absorption_context())
			if bool(res.get("cracks_shell", false)):
				en.crack_shell()
			if bool(res.get("can_absorb", false)):
				en.begin_suction_into(player)
				continue
			# too big or armoured to eat: ramming only hurts a vulnerable target or a miniboss (as in the arena)
			var ram_dps := 14.0 + player.mass * 0.22
			var pierce := 0.0
			if player.mutations.has_mutation("spikes"):
				ram_dps += player.mutations.get_scaled_param("spikes", "contact_dps_base", "contact_dps_per_level", 18.0)
				pierce = float(player.mutations.get_level("spikes")) * 0.22
			if player.is_dashing:
				en.take_damage(ram_dps * 2.2 * _delta, maxf(0.35, pierce))
			elif player.mutations.has_mutation("spikes") or en.is_miniboss or en.is_vulnerable:
				en.take_damage(ram_dps * _delta, pierce)
		if not is_instance_valid(en) or not en.is_active_combatant():
			continue
		if en.can_deal_contact_hit() and not en.is_vulnerable and dist <= pr + en.get_body_radius():
			en.mark_contact_hit_dealt()
			_hurt_player(en.contact_damage, en.enemy_id, en.global_position)
	if boss != null and is_instance_valid(boss) and boss.action_state != AncientGuardianBoss.ActionState.DEFEATED:
		var bd := player.global_position.distance_to(boss.global_position)
		var br := boss.get_body_radius()
		if bd <= pr + br + 10.0 and _boss_ram_cd <= 0.0:
			var bres := AbsorptionRules.evaluate(p_ctx, boss.build_absorption_context())
			if bool(bres.get("can_absorb", false)):
				boss.take_damage(9999.0, 1.0)
			else:
				# an elastic strike: damage by size, a push away from the boss (so it cannot melt through 60 times a second)
				_boss_ram_cd = 0.48
				var was_vuln := boss.is_vulnerable()
				boss.take_damage(26.0 + player.mass * 0.22, 0.65 if player.is_dashing else 0.0)
				var away := (player.global_position - boss.global_position).normalized()
				if away.length_squared() < 0.01:
					away = Vector2.DOWN
				player.global_position = clamp_world_point(boss.global_position + away * (pr + br + 6.0), pr)
				player.velocity = away * 225.0
				lab.spawn_fx("splash_ring", boss.global_position + away * br * 0.8, 0.4, 0.8, 0.9)
				lab.audio.play("water_splash_small", -8.0, 1.2 if was_vuln else 0.9, 0.1)
		if boss != null and is_instance_valid(boss) and boss.can_deal_contact_hit() and not boss.is_vulnerable() and bd <= pr + boss.get_body_radius():
			boss.mark_contact_hit_dealt()
			_hurt_player(boss.get_active_contact_damage(), "boss_contact", boss.global_position)
	# the lab never kills the slime: it is mended when low, so a fight can be watched and the Nova tested
	if player.hp < player.max_hp * 0.25:
		mends += 1
		player.heal(player.max_hp * 0.6)
	_bar_player.value = clampf(player.hp / player.max_hp, 0.0, 1.0)
	if boss != null and is_instance_valid(boss):
		_bar_boss.value = clampf(boss.hp / boss.max_hp, 0.0, 1.0)


## The Lunar Nova's reach: every small enemy in range is struck dead, the boss loses a fraction of its maximum
## health ignoring armour (armor_pierce 1.0), exactly through the real take_damage of each.
func nova_strike(origin: Vector2, radius: float, boss_fraction: float) -> Dictionary:
	var dead := 0
	for en in enemies.duplicate():
		if is_instance_valid(en) and en.global_position.distance_to(origin) <= radius:
			var was_alive: bool = en.hp > 0.0
			en.take_damage(en.max_hp * 100.0, 1.0)
			if was_alive:
				dead += 1
	var boss_damage := 0.0
	if boss != null and is_instance_valid(boss) and boss.global_position.distance_to(origin) <= radius * 1.25:
		var before := boss.hp
		boss.take_damage(boss.max_hp * boss_fraction, 1.0)
		boss_damage = before - boss.hp
	return {"dead": dead, "boss_damage": boss_damage}


## --- waves ------------------------------------------------------------------------------------------------

## 0 on the dewy glade, 1 at the dive line: how far into the world the slime is.
func progress_at(pos: Vector2) -> float:
	return clampf((LakeProto25D.START_POS.y - pos.y) / (LakeProto25D.START_POS.y - LakeProto25D.DIVE_Y), 0.0, 1.0)


## Difficulty scale handed to the real EnemyEntity setup (hit points, damage): 1.0 at the start up to about 1.9 at the dive.
func difficulty_at(pos: Vector2) -> float:
	return 1.0 + 0.9 * progress_at(pos)


func wave_interval(prog: float) -> float:
	return lerpf(WAVE_INTERVAL.x, WAVE_INTERVAL.y, prog)


func wave_max_alive(prog: float) -> int:
	return int(round(lerpf(WAVE_MAX_ALIVE.x, WAVE_MAX_ALIVE.y, prog)))


## Weighted table for a zone: the glade only has food, the grove adds small pests, the lake the armoured and the electric,
## the far lake the hunters.
func wave_table(y: float) -> Array:
	if y > WAVE_GLADE_Y:
		return [["tiny_mushroom", 5], ["firefly", 3]]
	if y > WAVE_GROVE_Y:
		return [["tiny_mushroom", 3], ["firefly", 3], ["forest_beetle", 4], ["poison_toad", 2]]
	if y > WAVE_FAR_Y:
		return [["firefly", 2], ["forest_beetle", 3], ["poison_toad", 3], ["stone_slug", 3], ["electric_beetle", 2], ["predator_flower", 2]]
	return [["forest_beetle", 2], ["stone_slug", 3], ["electric_beetle", 3], ["predator_flower", 3], ["shadow_slime", 3]]


func _pick(table: Array) -> String:
	var total := 0.0
	for e in table:
		total += float(e[1])
	var r := _rng.randf() * total
	for e in table:
		r -= float(e[1])
		if r <= 0.0:
			return String(e[0])
	return String(table[0][0])


func _update_waves(delta: float) -> void:
	_wave_clock += delta
	var pos: Vector2 = player.global_position
	progress = progress_at(pos)
	# far-away enemies are released silently (they belong to a part of the world the slime has left)
	for en in enemies.duplicate():
		if is_instance_valid(en) and en.global_position.distance_to(pos) > WAVE_DESPAWN_DIST:
			enemies.erase(en)
			en.queue_free()
	if not waves_enabled or lab.dive > 0.3:
		return
	if progress >= BOSS_PROGRESS and not boss_gate_used and boss == null:
		boss_gate_used = true
		spawn_boss(pos + Vector2(0.0, -520.0))
		lab.legends.show_banner("Пробуждается Древний страж!")
	_wave_timer -= delta
	if _wave_timer > 0.0:
		return
	_wave_timer = wave_interval(progress) * _rng.randf_range(0.8, 1.25)
	var table := wave_table(pos.y)
	var id := _pick(table)
	var prey := id == "tiny_mushroom" or id == "firefly"
	if enemies.size() >= wave_max_alive(progress) or (not prey and _wave_clock < WAVE_QUIET_SEC):
		return
	var ang := _rng.randf() * TAU
	var at := pos + Vector2.from_angle(ang) * _rng.randf_range(WAVE_SPAWN_RING.x, WAVE_SPAWN_RING.y)
	var en := spawn_enemy(id, at, difficulty_at(pos))
	if en != null:
		waves_spawned += 1
		lab.spawn_fx("bubbles", en.global_position, 0.35, 1.2, 0.7)
