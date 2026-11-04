class_name LakeMutations
extends Node2D
## Mutations on the painted hero (plan section 13). The shipped mutation LOGIC (PlayerSlime timers, MutationManager levels and
## parameters from mutations.json) runs untouched; what the lab adds is
##  - the arena hooks PlayerSlime calls on its arena reference (the lab forwards them here): electro pulse, cryo pulse,
##    shield burst, magnet field, poison pools, tendril stub;
##  - 2.5D visuals, because the painted hero hides the 2D body where the game normally draws them: a shield bubble, lightning
##    bolts, an ice ring, a spiky crystal collar, the dash streak, the magnet swirl.
## Levels are written straight into `player.mutations.levels`: MutationManager.apply_mutation also writes SaveData statistics and
## analytics, which the lab must not do. Synergies are therefore not evaluated yet. Evolution XP and the draft are not hosted.
##
## Supported: shield, electro_discharge, freeze, spikes, poison_trail, dash, magnet, regeneration, speed_boost.
## Not hosted yet (needs more arena): split (clones), ranged_absorb (tendrils), mimicry (ambush). They can be granted, they do nothing.
## Keys: M grants the next mutation (cycles; again = next level), Space dashes. Args: -- --lake-mut=shield,electro_discharge

const SUPPORTED := ["shield", "electro_discharge", "freeze", "spikes", "poison_trail", "dash", "magnet", "regeneration", "speed_boost"]
const ICE := Color(0.7, 0.95, 1.0)
const BOLT := Color(1.0, 0.94, 0.45)
const POISON := Color(0.55, 1.0, 0.4)

var lab: Node2D
var player: PlayerSlime
var _cycle := 0
var _t := 0.0
var _shield: Sprite2D
var _shield_glow: Sprite2D
var _spikes: Node2D
var _magnet_ring: Sprite2D
var _bolts: Array[Dictionary] = []
var synergies_unlocked: Array[String] = []
var pulses := {"electro": 0, "freeze": 0, "shield_burst": 0, "magnet": 0}
var _add: CanvasItemMaterial
var _tex_cache: Dictionary = {}
var overlay: MutationDraftOverlay
var _stub: DraftArenaStub
var drafts_opened := 0
var _prev_state := -1


func setup(p_lab: Node2D) -> void:
	lab = p_lab
	player = lab.player
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	z_index = 5
	_build_draft_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lake-seed="):
			player.mutations._rng.seed = 777 + int(a.trim_prefix("--lake-seed="))   # repeatable card draws in autoplay runs
	for a in OS.get_cmdline_user_args():
		if a == "--lake-draft":
			call_deferred("request_draft")
		if a.begins_with("--lake-mut="):
			for id in a.trim_prefix("--lake-mut=").split(","):
				call_deferred("grant", id)


func _tex(file_name: String) -> Texture2D:
	if not _tex_cache.has(file_name):
		_tex_cache[file_name] = load(LakeLegends.DIR + file_name + ".png") as Texture2D
	return _tex_cache[file_name]


## Give a mutation (or its next level) without the statistics and analytics side effects of apply_mutation.
func grant(mutation_id: String) -> int:
	if ConfigDB.get_mutation(mutation_id).is_empty():
		return 0
	var cur: int = player.mutations.get_level(mutation_id)
	var max_lv: int = int(ConfigDB.get_mutation(mutation_id).get("max_level", 5))
	if cur >= max_lv:
		return cur
	player.mutations.levels[mutation_id] = cur + 1
	_check_synergies()
	_build_visuals()
	if mutation_id == "shield":
		player.shield_ready = true
	lab.audio.play("water_plip_03", -9.0, 1.5, 0.0)
	lab.spawn_fx("splash_ring", player.global_position, 0.5, 1.0, 0.9)
	return cur + 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				grant(String(SUPPORTED[_cycle % SUPPORTED.size()]))
				_cycle += 1
			KEY_SPACE:
				dash()


func dash() -> bool:
	if not player.trigger_dash():
		return false
	lab.spawn_fx("wake_curve", player.global_position, 0.7, 0.6, 0.9)
	lab.audio.play("water_dive", -12.0, 1.6, 0.2)
	return true


## --- visuals on the hero ----------------------------------------------------------------------------------

func _build_visuals() -> void:
	var hero: Node2D = lab.hero if lab.hero != null else player
	if player.mutations.has_mutation("shield") and _shield == null:
		_shield = Sprite2D.new()
		_shield.name = "ShieldBubble"
		_shield.texture = _tex("lg_aura_moon")
		_shield.material = _add
		_shield.modulate = Color(ICE.r, ICE.g, ICE.b, 0.0)
		_shield.z_index = 3
		hero.add_child(_shield)
		_shield_glow = Sprite2D.new()
		_shield_glow.texture = lab.SOFT_GLOW
		_shield_glow.material = _add
		_shield_glow.modulate = Color(ICE.r, ICE.g, ICE.b, 0.0)
		_shield_glow.z_index = -1
		hero.add_child(_shield_glow)
	if player.mutations.has_mutation("spikes") and _spikes == null:
		_spikes = SpikeCollar.new()
		_spikes.name = "SpikeCollar"
		_spikes.z_index = 2
		hero.add_child(_spikes)
	if player.mutations.has_mutation("magnet") and _magnet_ring == null:
		_magnet_ring = Sprite2D.new()
		_magnet_ring.name = "MagnetSwirl"
		_magnet_ring.texture = _tex("lg_aura_star")
		_magnet_ring.material = _add
		_magnet_ring.modulate = Color(1.0, 0.6, 0.9, 0.0)
		_magnet_ring.z_index = -1
		hero.add_child(_magnet_ring)


func _process(delta: float) -> void:
	if lab == null or player == null:
		return
	_t += delta
	var r := player.get_radius()
	if _shield != null:
		var up: bool = player.shield_ready
		var a := lerpf(_shield.modulate.a, 0.85 if up else 0.0, minf(1.0, delta * 6.0))
		var k := (r * 6.0 / maxf(float(_shield.texture.get_width()), 1.0)) * (1.0 + 0.03 * sin(_t * 2.4))
		_shield.scale = Vector2.ONE * k
		_shield.position = Vector2(0.0, r * 0.3)
		_shield.modulate = Color(ICE.r * 1.4, ICE.g * 1.4, ICE.b * 1.4, a)
		_shield_glow.scale = Vector2.ONE * (r * 3.4 / 128.0)
		_shield_glow.modulate.a = a * 0.42
	if _spikes != null:
		(_spikes as SpikeCollar).radius = r
		_spikes.queue_redraw()
		_spikes.position = Vector2(0.0, r * 0.3)
	if _magnet_ring != null:
		_magnet_ring.scale = Vector2.ONE * (r * 8.0 / maxf(float(_magnet_ring.texture.get_width()), 1.0))
		_magnet_ring.position = Vector2(0.0, r * 0.3)
		_magnet_ring.rotation = _t * 0.5
		_magnet_ring.modulate.a = 0.35 + 0.15 * sin(_t * 2.0)
	var i := _bolts.size() - 1
	while i >= 0:
		var b: Dictionary = _bolts[i]
		b["age"] = float(b["age"]) + delta
		var line: Line2D = b["line"]
		if float(b["age"]) > 0.35 or not is_instance_valid(line):
			if is_instance_valid(line):
				line.queue_free()
			_bolts.remove_at(i)
		else:
			line.modulate.a = 1.0 - float(b["age"]) / 0.35
			if int(float(b["age"]) * 40.0) != int(float(b["age"]) * 40.0 - delta * 40.0):
				line.points = _jagged(line.points[0], line.points[line.points.size() - 1])
		i -= 1


func _jagged(from: Vector2, to: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 9
	var dir := to - from
	var perp := Vector2(-dir.y, dir.x).normalized()
	for k in range(n + 1):
		var u := float(k) / float(n)
		var jitter := 0.0 if k == 0 or k == n else randf_range(-14.0, 14.0)
		pts.append(from + dir * u + perp * jitter)
	return pts


func _ring(file_name: String, at: Vector2, tint: Color, radius: float, life: float) -> void:
	var sp := Sprite2D.new()
	sp.texture = _tex(file_name)
	sp.material = _add
	sp.position = at + Vector2(0.0, 10.0)
	sp.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	sp.z_index = 4
	add_child(sp)
	var w := maxf(float(sp.texture.get_width()), 1.0)
	var final := radius * 2.2 / w
	sp.scale = Vector2.ONE * final * 0.25
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * final, life * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(sp, "modulate:a", 0.8, 0.1)
	tw.chain().tween_property(sp, "modulate:a", 0.0, life * 0.5)
	tw.chain().tween_callback(sp.queue_free)


## --- the arena hooks the lab forwards here -------------------------------------------------------------------

func trigger_electro_pulse(center: Vector2, radius: float, damage: float, max_targets: int, stun_sec: float) -> void:
	pulses["electro"] += 1
	_ring("lg_nova_cracks", center, BOLT, radius, 0.7)
	var hit := 0
	var combat: LakeCombat = lab.combat
	var targets: Array[Node2D] = []
	for en in combat.enemies:
		if is_instance_valid(en) and en.is_active_combatant() and en.global_position.distance_to(center) <= radius:
			targets.append(en)
	targets.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_to(center) < b.global_position.distance_to(center))
	for en: EnemyEntity in targets:
		if hit >= max_targets:
			break
		en.crack_shell()
		en.apply_stun(stun_sec)
		en.take_damage(damage, 0.5)
		_bolt(center, en.global_position)
		hit += 1
	if combat.boss != null and is_instance_valid(combat.boss) and hit < max_targets and combat.boss.global_position.distance_to(center) <= radius + combat.boss.get_body_radius():
		combat.boss.take_damage(damage * 1.15, 0.4)
		_bolt(center, combat.boss.global_position)
		hit += 1
	if hit > 0:
		lab.audio.play("water_splash_small", -9.0, 1.5, 0.1)


func _bolt(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = BOLT
	line.material = _add
	line.points = _jagged(from, to)
	line.z_index = 5
	add_child(line)
	_bolts.append({"line": line, "age": 0.0})


func trigger_freeze_pulse(center: Vector2, radius: float, slow_amt: float, dur: float) -> void:
	pulses["freeze"] += 1
	_ring("lg_nova_ring", center, ICE, radius, 0.9)
	var combat: LakeCombat = lab.combat
	for en in combat.enemies:
		if is_instance_valid(en) and en.is_active_combatant() and en.global_position.distance_to(center) <= radius:
			en.apply_freeze(slow_amt, dur)
	if combat.boss != null and is_instance_valid(combat.boss) and combat.boss.global_position.distance_to(center) <= radius + combat.boss.get_body_radius():
		combat.boss.apply_freeze(slow_amt, dur)


func on_player_shield_burst(center: Vector2, is_ice_armor: bool) -> void:
	pulses["shield_burst"] += 1
	var burst_r := 165.0 if is_ice_armor else 125.0
	_ring("lg_nova_ring", center, ICE, burst_r, 0.8)
	lab.spawn_fx("splash_crown", center, 0.8, 1.0, 1.0)
	var combat: LakeCombat = lab.combat
	for en in combat.enemies:
		if is_instance_valid(en) and en.is_active_combatant() and en.global_position.distance_to(center) <= burst_r:
			var push := (en.global_position - center).normalized() * 90.0
			en.global_position = combat.clamp_world_point(en.global_position + push, en.get_body_radius())
			if is_ice_armor:
				en.apply_freeze(0.68, 2.8)
				en.take_damage(30.0, 0.5)


func apply_magnet_field(center: Vector2, radius: float, force: float, delta: float, pull_enemies: bool) -> void:
	pulses["magnet"] += 1
	for f in lab.food:
		var pos: Vector2 = f["pos"]
		if pos.distance_to(center) <= radius:
			pos = pos.move_toward(center, force * delta)
			f["pos"] = pos
			(f["node"] as Node2D).position = pos
	if pull_enemies:
		for en in (lab.combat as LakeCombat).enemies:
			if is_instance_valid(en) and en.is_active_combatant() and en.global_position.distance_to(center) <= radius * 0.85:
				en.global_position = en.global_position.move_toward(center, 135.0 * delta)


func spawn_player_poison_pool(pos: Vector2, radius: float, dur: float, dps: float) -> void:
	(lab.combat as LakeCombat).spawn_player_pool(pos, radius, dur, dps)


## A ring of small crystal spikes around the hero's waterline (spikes mutation): drawn, not painted (placeholder).
class SpikeCollar extends Node2D:
	var radius := 25.0

	func _draw() -> void:
		var n := 14
		for i in range(n):
			var a := TAU * float(i) / float(n)
			var base := Vector2(cos(a) * radius * 1.15, sin(a) * radius * 0.55)
			var tip := Vector2(cos(a) * radius * 1.6, sin(a) * radius * 0.85)
			var side := Vector2(-sin(a), cos(a)) * radius * 0.12
			draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(0.82, 0.6, 1.0, 0.85))
			draw_polyline(PackedVector2Array([base - side, tip, base + side]), Color(1.0, 0.9, 1.0, 0.9), 1.5)


## --- evolution draft: the game's own card overlay, driven by a stub arena that writes nothing to the save -----------

## The real MutationDraftOverlay asks its (typed) arena to select / reroll. This stub is never added to the tree; it only
## answers those two calls.
class DraftArenaStub extends ArenaController:
	var mf: LakeMutations

	func select_draft_mutation(mutation_id: String) -> void:
		mf._on_card_chosen(mutation_id)

	func reroll_draft_choices() -> bool:
		return mf._reroll()


func _build_draft_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	overlay = MutationDraftOverlay.new()
	_stub = DraftArenaStub.new()
	_stub.mf = self
	_stub.free_rerolls_left = 1
	overlay.bind_arena(_stub)
	layer.add_child(overlay)


func is_draft_open() -> bool:
	return App.state == App.State.MUTATION_DRAFT


## Called by PlayerSlime.add_evolution_xp (through the lab) when an evolution is earned.
func request_draft() -> void:
	if is_draft_open():
		return
	var choices: Array[Dictionary] = player.mutations.roll_draft_choices(3)
	if choices.is_empty():
		player.heal(25.0)   # everything maxed: a heal instead (as in the arena)
		return
	_stub.current_draft_choices = choices
	_prev_state = App.state
	drafts_opened += 1
	App.change_state(App.State.MUTATION_DRAFT)
	Events.mutation_draft_requested.emit(choices)


func _on_card_chosen(mutation_id: String) -> void:
	if not is_draft_open():
		return
	var offered := false
	for c in _stub.current_draft_choices:
		if str(c.get("id", "")) == mutation_id:
			offered = true
			break
	if not offered or not player.mutations.can_upgrade_mutation(mutation_id):
		return
	Audio.play_sfx("mutation_pick", 1.0)
	grant(mutation_id)
	player._sync_mass_metrics()
	_stub.current_draft_choices.clear()
	App.change_state(App.State.PLAYING)
	Audio.stop_music(0.0)   # entering PLAYING starts the run theme; the lab has its own ambience
	player.add_evolution_xp(0.0)   # offer every earned evolution before returning to the water


func _reroll() -> bool:
	if not is_draft_open() or _stub.free_rerolls_left <= 0:
		return false
	_stub.free_rerolls_left -= 1
	_stub.current_draft_choices = player.mutations.roll_draft_choices(3)
	Events.mutation_draft_requested.emit(_stub.current_draft_choices)
	return true


## Leave the draft without choosing (tests, scene changes).
func close_draft() -> void:
	if is_draft_open():
		App.change_state(App.State.PLAYING)
		Audio.stop_music(0.0)


## Synergies: the same rule MutationManager._evaluate_synergies applies (all required mutations at least at the minimum level), but
## without its SaveData statistic and event. PlayerSlime already reads `has_synergy` (em_storm, ice_armor, piercing_strike, ...).
func _check_synergies() -> void:
	for syn: Dictionary in ConfigDB.synergy_list:
		var sid := str(syn.get("id", ""))
		if sid.is_empty() or player.mutations.has_synergy(sid):
			continue
		var reqs: Array = syn.get("required_mutations", [])
		if reqs.is_empty():
			continue
		var min_lv := int(syn.get("min_mutation_level", 1))
		var ok := true
		for r in reqs:
			if player.mutations.get_level(str(r)) < min_lv:
				ok = false
				break
		if ok:
			player.mutations.active_synergies[sid] = true
			synergies_unlocked.append(sid)
			if lab.legends != null:
				lab.legends.show_banner("Синергия: %s" % ConfigDB.get_synergy(sid).get("name", sid) if ConfigDB.has_method("get_synergy") else "Синергия: %s" % sid)
			lab.spawn_fx("splash_ring", player.global_position, 0.9, 1.4, 1.0)
			lab.spawn_fx("splash_crown", player.global_position, 0.7, 1.2, 1.0)
			lab.audio.play("water_splash_large", -9.0, 1.4, 0.0)
