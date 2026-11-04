class_name LakeLegends
extends Node2D
## Legends of the lake (owner request 04.11.2026): very rare, very elusive spirits; catching one wraps the slime in a
## spectacular aura for a while and loads a ONE-USE area ability, the Lunar Nova, that wipes out the small hostile
## creatures around and badly wounds even a boss. Lab-only: the
## ability strikes the REAL EnemyEntity and AncientGuardianBoss hosted by LakeCombat. Nothing here touches the arena, the save
## or the shipped formulas.
##
## Keys in the lab: R call a spirit now, F start a skirmish (real enemies + the real boss), N cast the Nova when it is ready.
## Args: -- --lake-fight (skirmish at start), -- --lake-spirit=<0..5> (spirit already next to the slime),
##       -- --lake-aura=<0..5> (aura + Nova already granted), -- --lake-nova=<sec> (cast the Nova after that many seconds).

const DIR := "res://resources/art/2_5d/water/legend/"
const KINDS: Array[Dictionary] = [
	{"id": "lantern_moth", "name": "Лунный мотылёк", "spirit": "lg_spirit_moth", "aura": "lg_aura_moon", "tint": Color(0.85, 0.95, 1.0), "glow": Color(0.8, 0.92, 1.0)},
	{"id": "sun_bloom", "name": "Солнечный цветок", "spirit": "lg_spirit_sun", "aura": "lg_aura_flame", "tint": Color(1.0, 0.85, 0.5), "glow": Color(1.0, 0.7, 0.3)},
	{"id": "glass_wisp", "name": "Стеклянный огонёк", "spirit": "lg_spirit_glass", "aura": "lg_aura_prism", "tint": Color(1.0, 1.0, 1.0), "glow": Color(0.9, 0.8, 1.0)},
	{"id": "star_loom", "name": "Звёздный ткач", "spirit": "lg_spirit_loom", "aura": "lg_aura_star", "tint": Color(0.85, 0.75, 1.0), "glow": Color(0.7, 0.55, 1.0)},
	{"id": "aurora_ribbon", "name": "Лента авроры", "spirit": "lg_spirit_ribbon", "aura": "lg_aura_aurora", "tint": Color(0.7, 1.0, 1.0), "glow": Color(0.4, 0.95, 1.0)},
	{"id": "pearl_bloom", "name": "Жемчужный бутон", "spirit": "lg_spirit_pearl", "aura": "lg_aura_pearl", "tint": Color(1.0, 0.85, 0.95), "glow": Color(1.0, 0.6, 0.85)},
]
## How rare and how hard (every number is tunable in the lab; the balance pass belongs to integration).
const APPEAR_MIN_SEC := 70.0         ## earliest a spirit may show up after the last one
const APPEAR_CHANCE_PER_SEC := 0.006  ## then a small chance each second: about one visit per 3-4 minutes
const LINGER_SEC := 28.0              ## it fades away if nobody catches it
const FLEE_RADIUS := 300.0
const SPIRIT_SPEED := 1.18            ## x the slime's top speed while fleeing: you cannot outswim it
const BLINK_EVERY := 1.7              ## it blinks away from a pursuer
const BLINK_DIST := 190.0
const TIRE_AFTER := 5.0               ## s of fleeing before it is out of breath ...
const TIRED_SEC := 1.6                ## ... and, for a moment, catchable
const CATCH_PAD := 12.0
const AURA_SEC := 75.0
const NOVA_RADIUS := 560.0
const NOVA_BOSS_FRACTION := 0.6       ## of a boss's maximum hit points
const NOVA_CRITTER_DAMAGE := 9999.0

var lab: Node2D                        ## the LakeProto25D
var spirit: Dictionary = {}            ## active rare spirit: {node, kind, born, vel, tired, flee_time, blink}
var _timer_since := 0.0
var aura_kind := -1
var aura_left := 0.0
var nova_ready := false
var nova_cast_count := 0
var catches := 0
var spirits_seen := 0
var kills := 0
var _aura_sprites: Array[Sprite2D] = []
var _orbit: Array[Sprite2D] = []
var _banner: Label
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _tex_cache: Dictionary = {}
var _add: CanvasItemMaterial
var _fight_t := 0.0
signal spirit_caught(kind_index: int)
signal nova_cast(kills: int, boss_damage: float)


func setup(p_lab: Node2D) -> void:
	lab = p_lab
	_rng.seed = 20261104
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	z_index = 4
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_banner = Label.new()
	_banner.modulate.a = 0.0
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.position = Vector2(20.0, 190.0)
	_banner.size = Vector2(680.0, 120.0)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 24)
	_banner.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.15, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_banner)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--lake-fight":
			call_deferred("start_skirmish")
		elif a.begins_with("--lake-spirit="):
			call_deferred("spawn_spirit", int(a.trim_prefix("--lake-spirit=")), true)
		elif a.begins_with("--lake-aura="):
			call_deferred("grant", int(a.trim_prefix("--lake-aura=")))
		elif a.begins_with("--lake-nova="):
			get_tree().create_timer(float(a.trim_prefix("--lake-nova="))).timeout.connect(cast_nova)


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _kind_tex(file_name: String) -> Texture2D:
	var t := _tex(DIR + file_name + ".png")
	return t if t != null else lab.SOFT_GLOW


## --- rare spirits -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if lab == null or lab.player == null:
		return
	_t += delta
	_timer_since += delta
	var pos: Vector2 = lab.player.global_position
	if spirit.is_empty() and _timer_since > APPEAR_MIN_SEC and aura_kind < 0 and _rng.randf() < APPEAR_CHANCE_PER_SEC * delta:
		spawn_spirit(_rng.randi() % KINDS.size(), false)
	_update_spirit(delta, pos)
	_update_aura(delta, pos)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.4)
		lab._camera.offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 14.0 * _shake
	elif lab._camera.offset != Vector2.ZERO:
		lab._camera.offset = Vector2.ZERO
	if _banner.modulate.a > 0.0:
		_banner.modulate.a = maxf(0.0, _banner.modulate.a - delta * 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				spawn_spirit(_rng.randi() % KINDS.size(), true)
			KEY_F:
				start_skirmish()
			KEY_N:
				cast_nova()


## Spawn a rare spirit near the slime (outside the screen unless `close`).
func spawn_spirit(kind_index: int, close: bool) -> void:
	if not spirit.is_empty():
		return
	var pos: Vector2 = lab.player.global_position
	var ang := _rng.randf() * TAU
	var dist := 150.0 if close else 420.0
	var at: Vector2 = lab.constrain_player_position(pos + Vector2(cos(ang), sin(ang)) * dist, 30.0, false)
	var kind: Dictionary = KINDS[kind_index]
	var node := Node2D.new()
	node.name = "Spirit_" + String(kind["id"])
	node.position = at
	node.z_index = 3
	var glow := Sprite2D.new()
	glow.texture = lab.SOFT_GLOW
	glow.material = _add
	glow.modulate = Color(kind["glow"].r, kind["glow"].g, kind["glow"].b, 0.55)
	glow.scale = Vector2.ONE * 1.5
	node.add_child(glow)
	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = _kind_tex(String(kind["spirit"]))
	body.material = _add
	body.modulate = Color(kind["tint"].r * 1.3, kind["tint"].g * 1.3, kind["tint"].b * 1.3, 1.0)
	var w := float(body.texture.get_width())
	body.scale = Vector2.ONE * (150.0 / maxf(w, 1.0))
	node.add_child(body)
	add_child(node)
	spirit = {"node": node, "kind": kind_index, "born": _t, "vel": Vector2.ZERO, "tired": 0.0, "flee_time": 0.0, "blink": 0.0}
	spirits_seen += 1
	_timer_since = 0.0
	lab.audio.play("water_plip_03", -10.0, 0.7, 0.0)
	lab.spawn_fx("bubbles", at, 0.5, 1.6, 0.9)


## Elusive: faster than the slime, blinks away when pressed, tires only now and then.
func _update_spirit(delta: float, pos: Vector2) -> void:
	if spirit.is_empty():
		return
	var node: Node2D = spirit["node"]
	if not is_instance_valid(node):
		spirit = {}
		return
	var age := _t - float(spirit["born"])
	var kind: Dictionary = KINDS[int(spirit["kind"])]
	var away := node.position - pos
	var d := away.length()
	var top_speed: float = lab.player.max_spd if "max_spd" in lab.player else 300.0
	var pressed := d < FLEE_RADIUS
	var body: Sprite2D = node.get_node("Body")
	if float(spirit["tired"]) > 0.0:
		spirit["tired"] = float(spirit["tired"]) - delta
		spirit["vel"] = (spirit["vel"] as Vector2).lerp(Vector2.ZERO, minf(1.0, delta * 4.0))
		body.modulate.a = 0.55 + 0.25 * sin(_t * 12.0)   # panting: it flickers and hovers
	else:
		body.modulate.a = 1.0
		if pressed:
			spirit["flee_time"] = float(spirit["flee_time"]) + delta
			var dir := away.normalized() if d > 0.01 else Vector2.RIGHT
			# bend along walls and solids so it does not simply run into a corner it cannot leave
			var side := Vector2(-dir.y, dir.x) * sin(_t * 1.3) * 0.5
			var target: Vector2 = (dir + side).normalized() * top_speed * SPIRIT_SPEED * clampf(1.4 - d / FLEE_RADIUS, 0.5, 1.0)
			spirit["vel"] = (spirit["vel"] as Vector2).lerp(target, minf(1.0, delta * 5.0))
			spirit["blink"] = float(spirit["blink"]) + delta
			if float(spirit["blink"]) > BLINK_EVERY and d < 140.0:
				spirit["blink"] = 0.0
				var jump: Vector2 = node.position + dir.rotated(_rng.randf_range(-0.6, 0.6)) * BLINK_DIST
				var safe: Vector2 = lab.constrain_player_position(jump, 26.0, false)
				lab.spawn_fx("splash_ring", node.position, 0.45, 0.8, 0.9)
				node.position = safe
				lab.spawn_fx("splash_ring", node.position, 0.45, 0.8, 0.9)
				lab.audio.play("water_plip_01", -10.0, 1.4, 0.1)
			if float(spirit["flee_time"]) > TIRE_AFTER:
				spirit["flee_time"] = 0.0
				spirit["tired"] = TIRED_SEC
		else:
			spirit["flee_time"] = maxf(0.0, float(spirit["flee_time"]) - delta)
			spirit["vel"] = (spirit["vel"] as Vector2).lerp(Vector2(cos(_t * 0.7 + 1.0), sin(_t * 0.9)) * 40.0, minf(1.0, delta * 2.0))
	var np: Vector2 = node.position + (spirit["vel"] as Vector2) * delta
	var cp: Vector2 = lab.constrain_player_position(np, 26.0, false)
	if cp.distance_to(np) > 0.5:
		spirit["vel"] = (spirit["vel"] as Vector2) * 0.4   # hit a wall or a boulder: it loses speed (this is how it gets cornered)
	node.position = cp
	body.rotation = sin(_t * 1.6) * 0.15
	body.scale = Vector2.ONE * (150.0 / maxf(float(body.texture.get_width()), 1.0)) * (1.0 + 0.05 * sin(_t * 3.0))
	if age > LINGER_SEC - 3.0:
		node.modulate.a = clampf((LINGER_SEC - age) / 3.0, 0.0, 1.0)
	if age > LINGER_SEC:
		node.queue_free()
		spirit = {}
		return
	if d < lab.player.get_radius() + CATCH_PAD + 20.0:
		_catch(int(spirit["kind"]), node)


func _catch(kind_index: int, node: Node2D) -> void:
	lab.spawn_fx("splash_ring", node.position, 0.9, 1.4, 1.0)
	lab.spawn_fx("splash_crown", node.position, 0.8, 1.2, 1.0)
	node.queue_free()
	spirit = {}
	catches += 1
	grant(kind_index)
	spirit_caught.emit(kind_index)


## Aura + the one-use Nova.
func grant(kind_index: int) -> void:
	aura_kind = kind_index
	aura_left = AURA_SEC
	nova_ready = true
	_build_aura()
	var kind: Dictionary = KINDS[kind_index]
	_banner.text = "%s\nЛунная вспышка готова (N)" % String(kind["name"])
	_banner.modulate = Color(kind["glow"].r, kind["glow"].g, kind["glow"].b, 1.0)
	lab.audio.play("water_splash_large", -8.0, 1.1, 0.0)
	var ga: Node = lab.get_node_or_null("/root/Audio")
	if ga != null and ga.has_method("play_wonder_chime") and lab.audio.enabled:
		ga.play_wonder_chime(kind_index % 3)
	_shake = 0.5


func _build_aura() -> void:
	for s in _aura_sprites + _orbit:
		if is_instance_valid(s):
			s.queue_free()
	_aura_sprites.clear()
	_orbit.clear()
	var kind: Dictionary = KINDS[aura_kind]
	var hero: Node2D = lab.hero if lab.hero != null else lab.player
	var ring := Sprite2D.new()
	ring.name = "AuraRing"
	ring.texture = _kind_tex(String(kind["aura"]))
	ring.material = _add
	ring.z_index = -1
	hero.add_child(ring)
	_aura_sprites.append(ring)
	var front := Sprite2D.new()   # the near half of the ring passes in front of the slime, the far half behind it
	front.name = "AuraFront"
	front.texture = ring.texture
	front.material = _add
	front.region_enabled = true
	front.region_rect = Rect2(0.0, float(ring.texture.get_height()) * 0.5, float(ring.texture.get_width()), float(ring.texture.get_height()) * 0.5)
	front.z_index = 2
	hero.add_child(front)
	_aura_sprites.append(front)
	var back := Sprite2D.new()
	back.name = "AuraGlow"
	back.texture = lab.SOFT_GLOW
	back.material = _add
	back.modulate = Color(kind["glow"].r, kind["glow"].g, kind["glow"].b, 0.5)
	back.z_index = -2
	hero.add_child(back)
	_aura_sprites.append(back)
	for i in range(10):
		var o := Sprite2D.new()
		o.texture = lab._fx_texture("glints")
		o.material = _add
		o.modulate = Color(kind["glow"].r, kind["glow"].g, kind["glow"].b, 0.9)
		o.scale = Vector2.ONE * _rng.randf_range(0.12, 0.22)
		o.z_index = 2
		o.set_meta("phase", _rng.randf() * TAU)
		o.set_meta("rad", _rng.randf_range(1.15, 1.9))
		o.set_meta("spd", _rng.randf_range(0.5, 1.4))
		hero.add_child(o)
		_orbit.append(o)


func _update_aura(delta: float, pos: Vector2) -> void:
	if aura_kind < 0:
		return
	aura_left -= delta
	var r: float = lab.player.get_radius()
	var kind: Dictionary = KINDS[aura_kind]
	var fade := clampf(aura_left / 6.0, 0.0, 1.0)
	if aura_left <= 0.0:
		for s in _aura_sprites + _orbit:
			if is_instance_valid(s):
				s.queue_free()
		_aura_sprites.clear()
		_orbit.clear()
		aura_kind = -1
		return
	var tint := Color(1, 1, 1, fade)
	if String(kind["id"]) == "glass_wisp":
		tint = Color.from_hsv(fposmod(_t * 0.15, 1.0), 0.45, 1.0, fade)   # the prismatic aura cycles through the rainbow
	for s in _aura_sprites:
		if not is_instance_valid(s):
			continue
		if s.name == "AuraRing" or s.name == "AuraFront":
			var w := float(s.texture.get_width())
			var k := (r * 7.4 / maxf(w, 1.0)) * (1.0 + 0.04 * sin(_t * 2.0))
			s.scale = Vector2.ONE * k
			s.modulate = Color(tint.r * 1.5, tint.g * 1.5, tint.b * 1.5, tint.a)
			# the ring is flattened already (an ellipse in the sprite), so it is only bobbed, never rotated
			s.position = Vector2(0.0, r * 0.3 + 2.0 * sin(_t * 1.7))
			if s.name == "AuraFront":
				s.position.y += float(s.texture.get_height()) * k * 0.25
		else:
			s.scale = Vector2.ONE * (r * 3.6 / 128.0) * (1.0 + 0.08 * sin(_t * 2.6))
			s.modulate.a = 0.45 * fade
			s.position = Vector2(0.0, r * 0.1)
	for o in _orbit:
		if is_instance_valid(o):
			var a := float(o.get_meta("phase")) + _t * float(o.get_meta("spd"))
			var rr := r * float(o.get_meta("rad"))
			o.position = Vector2(cos(a) * rr * 1.25, sin(a) * rr * 0.7 + r * 0.2 - 8.0 * sin(_t * 2.0 + a))
			o.modulate.a = (0.55 + 0.45 * sin(_t * 3.0 + a * 2.0)) * fade
			o.z_index = 3 if sin(a) > 0.0 else -1


## --- the Lunar Nova -----------------------------------------------------------------------------------

## One use: everything small within NOVA_RADIUS dies, a boss loses NOVA_BOSS_FRACTION of its maximum hit points.
func cast_nova() -> bool:
	if not nova_ready:
		return false
	nova_ready = false
	nova_cast_count += 1
	var pos: Vector2 = lab.player.global_position
	var result: Dictionary = lab.combat.nova_strike(pos, NOVA_RADIUS, NOVA_BOSS_FRACTION) if lab.combat != null else {"dead": 0, "boss_damage": 0.0}
	var dead: int = int(result["dead"])
	kills += dead
	var boss_dmg: float = float(result["boss_damage"])
	_nova_fx(pos)
	_banner.text = "ЛУННАЯ ВСПЫШКА!  Повержено: %d" % dead + ("\nБосс ранен на %d%%" % int(NOVA_BOSS_FRACTION * 100.0) if boss_dmg > 0.0 else "")
	_banner.modulate = Color(1.0, 0.95, 0.7, 1.0)
	nova_cast.emit(dead, boss_dmg)
	return true


func _nova_fx(pos: Vector2) -> void:
	_shake = 1.0
	var add := _add
	var names := ["lg_nova_ring", "lg_nova_burst", "lg_nova_vortex", "lg_nova_cracks"]
	for i in range(names.size()):
		var sp := Sprite2D.new()
		sp.texture = _kind_tex(String(names[i]))
		sp.material = add
		sp.position = pos + Vector2(0.0, 12.0)
		sp.z_index = 6
		sp.set_meta("i", i)
		add_child(sp)
		var tw := create_tween()
		var w := maxf(float(sp.texture.get_width()), 1.0)
		var final_scale := NOVA_RADIUS * (1.9 - 0.25 * float(i)) / w
		sp.scale = Vector2.ONE * final_scale * 0.1
		sp.modulate = Color(1, 1, 1, 0.0)
		tw.set_parallel(true)
		tw.tween_property(sp, "scale", Vector2.ONE * final_scale, 0.7 + 0.15 * float(i)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(sp, "modulate:a", 0.5 - 0.08 * float(i), 0.12)
		tw.chain().tween_property(sp, "modulate:a", 0.0, 0.9)
		tw.chain().tween_callback(sp.queue_free)
		sp.rotation = 0.5 * float(i)
	lab.audio.play("water_splash_large", -4.0, 0.7, 0.0)
	lab.audio.play("water_dive", -6.0, 1.3, 0.0)
	var ga: Node = lab.get_node_or_null("/root/Audio")
	if ga != null and ga.has_method("play_wonder_chime") and lab.audio.enabled:
		ga.play_wonder_chime(2)
	for k in range(2):
		lab.spawn_fx("ripple_large", pos, 0.6 + 0.6 * float(k), 1.6 + 0.3 * float(k), 0.55)
	lab.spawn_fx("splash_crown", pos, 0.8, 1.4, 0.7)


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate = Color(1.0, 0.7, 0.75, 1.0)


## --- the skirmish is the real thing now: see LakeCombat (real EnemyEntity, AncientGuardianBoss, HazardZone) ----------

func start_skirmish() -> void:
	if lab.combat != null:
		lab.combat.start_skirmish()
