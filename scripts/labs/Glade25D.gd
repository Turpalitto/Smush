class_name Glade25D
extends Node2D
## PHASE 3 (plan 1.2) 2.5D lab: the "Moonlit Mycelium" glade built from painted
## sprites (resources/art/2_5d) in plain 2D. Gameplay stays the real PlayerSlime
## with its normal 2D movement and mass code; this node is an isolated arena that
## only decides what the world looks like. The shipped arena, saves and gameplay
## formulas are untouched.
##
## Painted sprites are sorted by their base line (y-sort), the slime sorts with
## them, light is faked with additive glow sprites, a haze band and sky beams.
##
## Automation: -- --g25-shot=<png> --g25-at=<sec> --g25-mass=<m> --g25-move
##             --g25-zoom=<z> --g25-glow=0 --g25-haze=0 --g25-quit

const ART := "res://resources/art/2_5d/"
const GROUND_PATH := ART + "ground/ground.png"
const SOFT_GLOW: Texture2D = preload("res://resources/effects/soft_glow.tres")
const GROUND_SCALE := 1.0
const DETAIL_STRENGTH := 0.85
const DETAIL_TILE_WORLD := 260.0  ## world px per detail tile: ~4 phone px per texel
const PLAY_HALF := Vector2(270.0, 860.0)  ## player limits, world px
const DEFAULT_ZOOM := 1.7  ## 2.4 showed only the calm centre of every plate; 1.7 shows the painted edges
const FOOD_COUNT := 14
const FOOD_REACH := 10.0
const CYAN := Color(0.35, 0.95, 1.0)
const VIOLET := Color(0.62, 0.42, 1.0)
const AMBER := Color(1.0, 0.72, 0.3)

## name -> [file, height in world px]. Feet are the bottom centre of the sprite.
const PROPS := {
	"stump_hollow": ["props/stump_hollow.png", 175.0],
	"boulder_large": ["props/boulder_large.png", 92.0],
	"stone_medium": ["props/stone_medium.png", 56.0],
	"stone_small_clover": ["props/stone_small_clover.png", 36.0],
	"moss_cushion": ["props/moss_cushion.png", 40.0],
	"fern_clump": ["props/fern_clump.png", 72.0],
	"leaf_plant_violet": ["props/leaf_plant_violet.png", 104.0],
	"mushroom_violet_large": ["props/mushroom_violet_large.png", 84.0],
	"mushroom_cyan_medium": ["props/mushroom_cyan_medium.png", 60.0],
	"mushroom_violet_cluster": ["props/mushroom_violet_cluster.png", 44.0],
	"shelf_fungus_amber": ["props/shelf_fungus_amber.png", 44.0],
	"crystal_purple": ["props/crystal_purple.png", 34.0],
	# crystal grotto
	"crystal_cluster_violet": ["props/crystal_cluster_violet.png", 78.0],
	"crystal_cluster_cyan": ["props/crystal_cluster_cyan.png", 78.0],
	"crystal_spire": ["props/crystal_spire.png", 130.0],
	"glow_boulder": ["props/glow_boulder.png", 84.0],
	"cave_mushroom": ["props/cave_mushroom.png", 52.0],
	"stalagmite": ["props/stalagmite.png", 86.0],
	# glowing mushroom forest
	"giant_mushroom": ["props/giant_mushroom.png", 170.0],
	"giant_mushroom_cyan": ["props/giant_mushroom_cyan.png", 150.0],
	"hanging_mushroom_pink": ["props/hanging_mushroom_pink.png", 96.0],
	"tiny_mushroom_mound": ["props/tiny_mushroom_mound.png", 54.0],
	"mushroom_log": ["props/mushroom_log.png", 70.0],
	"spore_flower": ["props/spore_flower.png", 100.0],
	# moonlit pond
	"lily_pads": ["props/lily_pads.png", 56.0],
	"reed_clump": ["props/reed_clump.png", 96.0],
	"water_stone": ["props/water_stone.png", 56.0],
	"lantern_flower": ["props/lantern_flower.png", 84.0],
	"cattails": ["props/cattails.png", 100.0],
	"floating_lantern": ["props/floating_lantern.png", 40.0],
	# ancient ruins
	"rune_pillar": ["props/rune_pillar.png", 120.0],
	"ruin_arch": ["props/ruin_arch.png", 150.0],
	"rune_block": ["props/rune_block.png", 70.0],
	"cat_statue": ["props/cat_statue.png", 96.0],
	"stone_lantern": ["props/stone_lantern.png", 100.0],
	"brick_pile": ["props/brick_pile.png", 66.0],
	# frozen glade
	"ice_crystal_big": ["props/ice_crystal_big.png", 110.0],
	"snow_fir": ["props/snow_fir.png", 150.0],
	"frost_flower_mound": ["props/frost_flower_mound.png", 56.0],
	"ice_flower": ["props/ice_flower.png", 90.0],
	"snow_boulder": ["props/snow_boulder.png", 80.0],
	"snow_spirit": ["props/snow_spirit.png", 84.0],
	# moonlit dunes
	"crystal_cactus": ["props/crystal_cactus.png", 110.0],
	"spiral_shell": ["props/spiral_shell.png", 78.0],
	"sandstone_arch": ["props/sandstone_arch.png", 150.0],
	"glow_succulent": ["props/glow_succulent.png", 64.0],
	"dune_flower_mound": ["props/dune_flower_mound.png", 58.0],
	"sand_boulder": ["props/sand_boulder.png", 84.0],
	# mossy path glade
	"moss_boulder_big": ["props/moss_boulder_big.png", 140.0],
	"moss_boulder_wide": ["props/moss_boulder_wide.png", 100.0],
	"moss_boulder_tall": ["props/moss_boulder_tall.png", 130.0],
	"stone_trio": ["props/stone_trio.png", 70.0],
	"shroom_boulder": ["props/shroom_boulder.png", 100.0],
	"moss_slab": ["props/moss_slab.png", 54.0],
	"dew_leaf_burgundy": ["props/dew_leaf_burgundy.png", 64.0],
	"dew_leaves_green": ["props/dew_leaves_green.png", 84.0],
	"moss_mound_veins": ["props/moss_mound_veins.png", 56.0],
	"stepping_stones": ["props/stepping_stones.png", 52.0],
	"teal_grass_tuft": ["props/teal_grass_tuft.png", 70.0],
	"lily_pad_flower": ["props/lily_pad_flower.png", 50.0],
	# more boulders and translucent mushrooms
	"moss_boulder_huge": ["props/moss_boulder_huge.png", 150.0],
	"boulder_stack": ["props/boulder_stack.png", 120.0],
	"moss_ridge": ["props/moss_ridge.png", 60.0],
	"cracked_boulder": ["props/cracked_boulder.png", 110.0],
	"vine_boulder": ["props/vine_boulder.png", 110.0],
	"leaning_stones": ["props/leaning_stones.png", 120.0],
	"tall_lavender_mushroom": ["props/tall_lavender_mushroom.png", 120.0],
	"cyan_mushroom_trio": ["props/cyan_mushroom_trio.png", 80.0],
	"pink_big_mushroom": ["props/pink_big_mushroom.png", 90.0],
	"white_mushroom_pair": ["props/white_mushroom_pair.png", 44.0],
	"teal_bell_mushroom": ["props/teal_bell_mushroom.png", 110.0],
	"purple_mushroom_bump": ["props/purple_mushroom_bump.png", 56.0],
	# bioluminescent swamp
	"mangrove_roots": ["props/mangrove_roots.png", 110.0],
	"glow_lilies": ["props/glow_lilies.png", 56.0],
	"swamp_shrooms": ["props/swamp_shrooms.png", 76.0],
	"glow_reeds": ["props/glow_reeds.png", 96.0],
	"mossy_log_swamp": ["props/mossy_log_swamp.png", 62.0],
	"algae_mound": ["props/algae_mound.png", 54.0],
	# coral reef
	"coral_pink": ["props/coral_pink.png", 86.0],
	"coral_violet_fan": ["props/coral_violet_fan.png", 96.0],
	"coral_cyan_tubes": ["props/coral_cyan_tubes.png", 84.0],
	"reef_shell": ["props/reef_shell.png", 56.0],
	"sea_grass_glow": ["props/sea_grass_glow.png", 90.0],
	"starfish_rock": ["props/starfish_rock.png", 70.0],
	# ember canyon
	"ember_rock": ["props/ember_rock.png", 70.0],
	"fire_flower": ["props/fire_flower.png", 90.0],
	"obsidian_spire": ["props/obsidian_spire.png", 130.0],
	"ember_vent": ["props/ember_vent.png", 58.0],
	"amber_crystals": ["props/amber_crystals.png", 76.0],
	"glow_root": ["props/glow_root.png", 64.0],
	# starlit garden
	"star_flower": ["props/star_flower.png", 96.0],
	"crystal_sprouts": ["props/crystal_sprouts.png", 70.0],
	"nebula_mushroom": ["props/nebula_mushroom.png", 100.0],
	"constellation_stone": ["props/constellation_stone.png", 62.0],
	"star_bush": ["props/star_bush.png", 80.0],
	"orb_plant": ["props/orb_plant.png", 100.0],
	# cloud garden
	"cloud_puff": ["props/cloud_puff.png", 70.0],
	"floating_islet": ["props/floating_islet.png", 120.0],
	"sky_crystal": ["props/sky_crystal.png", 96.0],
	"cloud_flower": ["props/cloud_flower.png", 80.0],
	"star_chime": ["props/star_chime.png", 100.0],
	"rainbow_orb": ["props/rainbow_orb.png", 60.0],
	# world tree roots
	"root_arch": ["props/root_arch.png", 120.0],
	"gold_mushrooms": ["props/gold_mushrooms.png", 76.0],
	"golden_leaf_pile": ["props/golden_leaf_pile.png", 50.0],
	"root_sprout": ["props/root_sprout.png", 84.0],
	"hollow_root_stump": ["props/hollow_root_stump.png", 100.0],
	"amber_seed_pod": ["props/amber_seed_pod.png", 76.0],
	# bamboo grove
	"bamboo_cluster": ["props/bamboo_cluster.png", 150.0],
	"bamboo_lantern": ["props/bamboo_lantern.png", 96.0],
	"lotus_pond_small": ["props/lotus_pond_small.png", 70.0],
	"zen_stones": ["props/zen_stones.png", 70.0],
	"blossom_bush": ["props/blossom_bush.png", 90.0],
	"petal_ferns": ["props/petal_ferns.png", 70.0],
	# golden autumn
	"red_leaf_pile": ["props/red_leaf_pile.png", 54.0],
	"glow_pumpkin": ["props/glow_pumpkin.png", 66.0],
	"acorn_cluster": ["props/acorn_cluster.png", 50.0],
	"maple_sapling": ["props/maple_sapling.png", 120.0],
	"orange_mushrooms": ["props/orange_mushrooms.png", 76.0],
	"autumn_log": ["props/autumn_log.png", 62.0],
	# prism cavern, lantern lake, clockwork garden, glowing shore, mushroom village
	"prism_crystal_big": ["props/prism_crystal_big.png", 110.0],
	"rainbow_geode": ["props/rainbow_geode.png", 76.0],
	"crystal_bloom": ["props/crystal_bloom.png", 84.0],
	"prism_arch": ["props/prism_arch.png", 130.0],
	"light_orbs": ["props/light_orbs.png", 60.0],
	"crystal_shroom": ["props/crystal_shroom.png", 84.0],
	"lantern_raft": ["props/lantern_raft.png", 70.0],
	"lotus_lantern": ["props/lotus_lantern.png", 60.0],
	"dock_piece": ["props/dock_piece.png", 80.0],
	"paper_boat": ["props/paper_boat.png", 50.0],
	"lantern_post": ["props/lantern_post.png", 110.0],
	"reed_lights": ["props/reed_lights.png", 96.0],
	"brass_gear": ["props/brass_gear.png", 90.0],
	"gear_flower": ["props/gear_flower.png", 84.0],
	"clock_shroom": ["props/clock_shroom.png", 84.0],
	"copper_coil": ["props/copper_coil.png", 76.0],
	"cog_stones": ["props/cog_stones.png", 66.0],
	"brass_lamp": ["props/brass_lamp.png", 100.0],
	"shell_pile": ["props/shell_pile.png", 60.0],
	"tide_rock": ["props/tide_rock.png", 76.0],
	"glow_jelly": ["props/glow_jelly.png", 70.0],
	"driftwood_glow": ["props/driftwood_glow.png", 64.0],
	"urchin_crystal": ["props/urchin_crystal.png", 60.0],
	"kelp_tuft": ["props/kelp_tuft.png", 86.0],
	"mushroom_house": ["props/mushroom_house.png", 130.0],
	"tiny_cottage": ["props/tiny_cottage.png", 120.0],
	"flower_bed": ["props/flower_bed.png", 56.0],
	"fence_piece": ["props/fence_piece.png", 56.0],
	"village_lantern": ["props/village_lantern.png", 96.0],
	"toadstool_tower": ["props/toadstool_tower.png", 160.0],
	# painted water-surface sprites (lake direction, step 2)
	"wl_pad_xl": ["water/sprites/wl_pad_xl.png", 84.0],
	"wl_pads_trio": ["water/sprites/wl_pads_trio.png", 100.0],
	"wl_pad_dew": ["water/sprites/wl_pad_dew.png", 78.0],
	"wl_pads_five": ["water/sprites/wl_pads_five.png", 92.0],
	"wl_pad_curl": ["water/sprites/wl_pad_curl.png", 80.0],
	"wl_pads_bud": ["water/sprites/wl_pads_bud.png", 84.0],
	"wl_lotus_pink": ["water/sprites/wl_lotus_pink.png", 96.0],
	"wl_lotus_white": ["water/sprites/wl_lotus_white.png", 92.0],
	"wl_lotus_cyan": ["water/sprites/wl_lotus_cyan.png", 92.0],
	"wl_lotus_bud": ["water/sprites/wl_lotus_bud.png", 88.0],
	"wl_lotus_purple": ["water/sprites/wl_lotus_purple.png", 96.0],
	"wl_lotus_pod": ["water/sprites/wl_lotus_pod.png", 88.0],
	"wl_petals_pink": ["water/sprites/wl_petals_pink.png", 54.0],
	"wl_duck_a": ["water/sprites/wl_duck_a.png", 64.0],
	"wl_duck_b": ["water/sprites/wl_duck_b.png", 40.0],
	"wl_leaf_single": ["water/sprites/wl_leaf_single.png", 56.0],
	"wl_petals_white": ["water/sprites/wl_petals_white.png", 56.0],
	"wl_leaf_raft": ["water/sprites/wl_leaf_raft.png", 60.0],
	"wl_reeds": ["water/sprites/wl_reeds.png", 120.0],
	"wl_stone_ring": ["water/sprites/wl_stone_ring.png", 78.0],
	"wl_iris": ["water/sprites/wl_iris.png", 100.0],
	"wl_driftwood": ["water/sprites/wl_driftwood.png", 70.0],
	"wl_pebbles": ["water/sprites/wl_pebbles.png", 56.0],
	"wl_grass_teal": ["water/sprites/wl_grass_teal.png", 100.0],
	# flooded grove (lake direction, step 4)
	"gr_mush_violet": ["water/sprites/gr_mush_violet.png", 110.0],
	"gr_mush_cyan_trio": ["water/sprites/gr_mush_cyan_trio.png", 80.0],
	"gr_mush_pink": ["water/sprites/gr_mush_pink.png", 96.0],
	"gr_mush_white": ["water/sprites/gr_mush_white.png", 56.0],
	"gr_mush_bell": ["water/sprites/gr_mush_bell.png", 110.0],
	"gr_mush_giant": ["water/sprites/gr_mush_giant.png", 150.0],
	"gr_boulder": ["water/sprites/gr_boulder.png", 100.0],
	"gr_trunk": ["water/sprites/gr_trunk.png", 80.0],
	"gr_root_arch": ["water/sprites/gr_root_arch.png", 110.0],
	"gr_ferns": ["water/sprites/gr_ferns.png", 80.0],
	"gr_steps": ["water/sprites/gr_steps.png", 60.0],
	"gr_branch": ["water/sprites/gr_branch.png", 70.0],
	# underwater finale (lake direction, step 6)
	"fin_mush_giant": ["water/sprites/fin_mush_giant.png", 150.0],
	"fin_coral_violet": ["water/sprites/fin_coral_violet.png", 130.0],
	"fin_tubes_cyan": ["water/sprites/fin_tubes_cyan.png", 100.0],
	"fin_root_arch": ["water/sprites/fin_root_arch.png", 150.0],
	"fin_mush_pink": ["water/sprites/fin_mush_pink.png", 130.0],
	"fin_sea_fan": ["water/sprites/fin_sea_fan.png", 120.0],
	"fin_shell": ["water/sprites/fin_shell.png", 56.0],
	"fin_anemones": ["water/sprites/fin_anemones.png", 70.0],
	"fin_mush_small": ["water/sprites/fin_mush_small.png", 64.0],
	"fin_starfish": ["water/sprites/fin_starfish.png", 50.0],
	"fin_seaweed": ["water/sprites/fin_seaweed.png", 80.0],
	"fin_crystals": ["water/sprites/fin_crystals.png", 66.0],
	# dewy mycelium glade (lake direction, zone 1)
	"dw_mush_violet": ["water/sprites/dw_mush_violet.png", 100.0],
	"dw_mush_cyan": ["water/sprites/dw_mush_cyan.png", 80.0],
	"dw_fern": ["water/sprites/dw_fern.png", 90.0],
	"dw_clover": ["water/sprites/dw_clover.png", 56.0],
	"dw_stone": ["water/sprites/dw_stone.png", 80.0],
	"dw_bud": ["water/sprites/dw_bud.png", 84.0],
	# flower meadow
	"lotus_flower_cyan": ["props/lotus_flower_cyan.png", 84.0],
	"flower_cluster_pink": ["props/flower_cluster_pink.png", 64.0],
	"bellflowers_violet": ["props/bellflowers_violet.png", 96.0],
	"glow_grass": ["props/glow_grass.png", 78.0],
	"flower_bush": ["props/flower_bush.png", 88.0],
	"dandelion_glow": ["props/dandelion_glow.png", 104.0],
}

## [prop, x, y, flip, glow colour or null, glow radius]
const LAYOUT: Array = [
	["stump_hollow", 90.0, -690.0, false, CYAN, 100.0],
	["mushroom_cyan_medium", 10.0, -668.0, true, CYAN, 60.0],
	["mushroom_violet_cluster", 190.0, -652.0, false, VIOLET, 52.0],
	["shelf_fungus_amber", 250.0, -735.0, false, AMBER, 50.0],
	["leaf_plant_violet", -370.0, -800.0, false, null, 0.0],
	["leaf_plant_violet", -385.0, 890.0, true, null, 0.0],
	["leaf_plant_violet", 390.0, 905.0, false, null, 0.0],
	["boulder_large", -330.0, -470.0, false, null, 0.0],
	["mushroom_violet_large", 345.0, 690.0, true, VIOLET, 90.0],
]

## Edge-weighted scatter around the landmarks: [prop, count, centre bias 0..1].
## Big things hug the left and right edges so the middle stays an open floor.
const SCATTER: Array = [
	["moss_boulder_huge", 2, 0.0], ["boulder_stack", 3, 0.0], ["cracked_boulder", 3, 0.0], ["vine_boulder", 3, 0.0],
	["leaning_stones", 3, 0.0], ["moss_ridge", 3, 0.05],
	["tall_lavender_mushroom", 5, 0.0], ["cyan_mushroom_trio", 4, 0.05], ["pink_big_mushroom", 3, 0.0],
	["white_mushroom_pair", 5, 0.1], ["teal_bell_mushroom", 4, 0.0], ["purple_mushroom_bump", 4, 0.1],
	["moss_boulder_big", 3, 0.0], ["moss_boulder_wide", 3, 0.0], ["moss_boulder_tall", 2, 0.0],
	["shroom_boulder", 3, 0.0], ["stone_trio", 4, 0.05], ["moss_slab", 4, 0.1],
	["dew_leaf_burgundy", 6, 0.1], ["dew_leaves_green", 5, 0.0], ["moss_mound_veins", 8, 0.1],
	["teal_grass_tuft", 8, 0.1], ["stone_small_clover", 6, 0.25], ["boulder_large", 2, 0.0],
	["moss_cushion", 6, 0.15], ["fern_clump", 13, 0.0], ["leaf_plant_violet", 5, 0.0],
	["mushroom_violet_large", 2, 0.0], ["mushroom_cyan_medium", 3, 0.1],
	["mushroom_violet_cluster", 4, 0.2], ["crystal_purple", 5, 0.3], ["shelf_fungus_amber", 2, 0.0],
]
const SCATTER_GLOW := {
	"mushroom_violet_large": [VIOLET, 90.0], "mushroom_cyan_medium": [CYAN, 60.0],
	"mushroom_violet_cluster": [VIOLET, 52.0], "crystal_purple": [VIOLET, 46.0],
	"shelf_fungus_amber": [AMBER, 50.0], "moss_cushion": [CYAN, 44.0],
	"moss_boulder_big": [CYAN, 70.0], "moss_boulder_tall": [CYAN, 70.0], "moss_mound_veins": [CYAN, 50.0],
	"shroom_boulder": [VIOLET, 70.0], "moss_slab": [CYAN, 46.0],
	"moss_boulder_huge": [CYAN, 80.0], "boulder_stack": [CYAN, 70.0], "cracked_boulder": [CYAN, 90.0],
	"tall_lavender_mushroom": [VIOLET, 90.0], "cyan_mushroom_trio": [CYAN, 80.0], "pink_big_mushroom": [Color(1.0, 0.5, 0.85), 90.0],
	"white_mushroom_pair": [Color(0.85, 0.9, 1.0), 46.0], "teal_bell_mushroom": [CYAN, 90.0], "purple_mushroom_bump": [VIOLET, 56.0],
}
const SCATTER_MIN_GAP := 60.0

var player: PlayerSlime
var hero: Slime25D
var food: Array[Dictionary] = []
var auto_steer: bool = false
var zoom_level: float = DEFAULT_ZOOM
var glow_on: bool = true
var haze_on: bool = true

var _camera: Camera2D
var _props_root: Node2D
var _path_img: Image
var _no_sway := false  ## --g25-nosway: freeze foliage for A/B captures
var _active_zones: Array[int] = []
var _glows: Array[Sprite2D] = []
var _pulsing: Array[Sprite2D] = []
var _haze_layer: CanvasLayer
var _beams: Array[Sprite2D] = []
var _tint: CanvasModulate
var _tint_override: bool = false
var _rng := RandomNumberGenerator.new()
var _touching: bool = false
var _auto_angle: float = 0.0
var _clock: float = 0.0
var _tex_cache: Dictionary = {}


func _ready() -> void:
	_rng.seed = 20261103
	_no_sway = OS.get_cmdline_user_args().has("--g25-nosway")
	RenderingServer.set_default_clear_color(Color("#0a1218"))
	_build_ground()
	_build_decals()
	_props_root = Node2D.new()
	_props_root.name = "Props"
	_props_root.y_sort_enabled = true
	add_child(_props_root)
	_build_props()
	_build_player()
	_build_food()
	_build_camera()
	_build_atmosphere()
	_apply_capture_args()


## --- loading ------------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) as Texture2D
		if _tex_cache[path] == null:
			push_error("Glade25D: missing texture " + path)
	return _tex_cache[path]


## --- world --------------------------------------------------------------------

func _build_ground() -> void:
	var g := Sprite2D.new()
	g.name = "Ground"
	g.texture = _tex(GROUND_PATH)
	g.scale = Vector2.ONE * GROUND_SCALE
	g.z_index = -100
	g.modulate = Color(0.95, 0.93, 1.0)
	g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	g.material = _ground_material("glade", 0.0, 0.3)
	add_child(g)
	for k in range(ZONES.size()):
		var z: Dictionary = ZONES[k]
		if not ResourceLoader.exists(ART + z["ground"]):
			continue
		var zg := Sprite2D.new()
		zg.name = "Ground_" + String(z["id"])
		zg.texture = _tex(ART + z["ground"])
		zg.scale = Vector2.ONE * GROUND_SCALE
		zg.position = Vector2(0.0, _zone_y(k + 1))
		zg.z_index = -99 + k
		zg.modulate = z["mod"]
		zg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		zg.material = _ground_material(String(z["id"]), 0.18, float(z.get("detail", DETAIL_STRENGTH)))
		add_child(zg)
		_active_zones.append(k)


## Ground = painted plate (composition) + seamless world-space detail tile (crispness).
func _ground_material(zone_id: String, fade: float, strength: float = DETAIL_STRENGTH) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground_detail.gdshader") as Shader
	var path := ART + "ground/detail_%s.png" % zone_id
	if ResourceLoader.exists(path):
		m.set_shader_parameter("detail", load(path))
		m.set_shader_parameter("strength", strength)
		m.set_shader_parameter("tile_world", DETAIL_TILE_WORLD)
	else:
		m.set_shader_parameter("strength", 0.0)
		m.set_shader_parameter("detail", _tex(GROUND_PATH))  # unused at strength 0, keeps the sampler bound
	m.set_shader_parameter("fade", fade)
	return m


func ground_rect() -> Rect2:
	var size := (_tex(GROUND_PATH) as Texture2D).get_size() * GROUND_SCALE
	var r := Rect2(-size * 0.5, size)
	for k in _active_zones:
		r = r.merge(Rect2(-size * 0.5 + Vector2(0.0, _zone_y(k + 1)), size))
	return r


func _zone_y(zone_number: int) -> float:
	return -ZONE_SPACING * float(zone_number)


## Where the slime may go: the glade plus every built zone above it.
func play_bounds() -> Rect2:
	var top := -PLAY_HALF.y + (_zone_y(_active_zones.back() + 1) if not _active_zones.is_empty() else 0.0)
	return Rect2(-PLAY_HALF.x, top, PLAY_HALF.x * 2.0, PLAY_HALF.y - top)


## [x, y, radius, colour+alpha]: floor light, additive.
const LIGHT_POOLS: Array = [
	[90.0, -640.0, 190.0, Color(0.45, 0.55, 1.0, 0.16)],
	[-120.0, -330.0, 210.0, Color(0.55, 0.75, 1.0, 0.10)],
	[300.0, -450.0, 170.0, Color(0.35, 0.9, 1.0, 0.12)],
	[-250.0, -40.0, 150.0, Color(0.62, 0.42, 1.0, 0.13)],
	[0.0, 200.0, 240.0, Color(0.5, 0.7, 1.0, 0.09)],
	[260.0, 470.0, 170.0, Color(0.35, 0.9, 1.0, 0.10)],
	[-230.0, 700.0, 190.0, Color(0.62, 0.42, 1.0, 0.12)],
	[80.0, 520.0, 200.0, Color(0.55, 0.65, 1.0, 0.08)],
]

## Biomes beyond the starting glade. Zone k sits ZONE_SPACING px above the previous
## one; its plate melts into the one below. A zone is built only when its ground
## sprite exists, so an unfinished biome never breaks the lab.
## scatter: [prop, count, centre bias]; glow: prop -> [colour, radius];
## pools: zone-local floor light [x, y, radius, colour+alpha].
const ZONE_SPACING := 1500.0
const ZONES: Array = [
	{"id": "grotto", "ground": "ground/grotto.png", "tint": Color(0.82, 0.84, 1.0), "mod": Color(1.0, 0.98, 1.0),
		"scatter": [["crystal_cluster_violet", 8, 0.1], ["crystal_cluster_cyan", 7, 0.1], ["crystal_spire", 5, 0.0],
			["glow_boulder", 6, 0.0], ["cave_mushroom", 8, 0.15], ["crystal_purple", 8, 0.35],
			["stalagmite", 6, 0.05], ["stone_medium", 4, 0.1]],
		"glow": {"crystal_cluster_violet": [Color(0.62, 0.42, 1.0), 80.0], "crystal_cluster_cyan": [Color(0.35, 0.95, 1.0), 80.0],
			"crystal_spire": [Color(0.7, 0.5, 1.0), 100.0], "stalagmite": [Color(0.62, 0.42, 1.0), 60.0], "glow_boulder": [Color(0.4, 0.8, 1.0), 70.0],
			"cave_mushroom": [Color(0.4, 0.9, 1.0), 60.0], "crystal_purple": [Color(0.62, 0.42, 1.0), 46.0]},
		"pools": [[0.0, -500.0, 230.0, Color(0.55, 0.4, 1.0, 0.14)], [-220.0, 100.0, 200.0, Color(0.35, 0.9, 1.0, 0.12)],
			[240.0, 450.0, 220.0, Color(0.62, 0.42, 1.0, 0.14)], [0.0, 700.0, 240.0, Color(0.5, 0.6, 1.0, 0.10)]]},
	{"id": "fungal", "ground": "ground/fungal.png", "detail": 0.4, "tint": Color(0.92, 0.84, 1.0), "mod": Color(1.0, 0.96, 1.0),
		"scatter": [["giant_mushroom", 4, 0.0], ["giant_mushroom_cyan", 3, 0.0], ["hanging_mushroom_pink", 5, 0.05],
			["tiny_mushroom_mound", 10, 0.2], ["mushroom_log", 4, 0.0], ["spore_flower", 7, 0.1],
			["mushroom_violet_large", 5, 0.05], ["mushroom_cyan_medium", 6, 0.1],
			["mushroom_violet_cluster", 8, 0.2], ["shelf_fungus_amber", 4, 0.0], ["fern_clump", 6, 0.0],
			["moss_cushion", 6, 0.15]],
		"glow": {"giant_mushroom": [Color(0.7, 0.45, 1.0), 130.0], "giant_mushroom_cyan": [Color(0.35, 0.95, 1.0), 110.0],
			"hanging_mushroom_pink": [Color(1.0, 0.45, 0.8), 80.0], "tiny_mushroom_mound": [Color(0.5, 0.8, 1.0), 50.0],
			"spore_flower": [Color(0.35, 0.95, 1.0), 70.0], "mushroom_log": [Color(1.0, 0.72, 0.3), 60.0], "mushroom_violet_large": [Color(0.62, 0.42, 1.0), 90.0],
			"mushroom_cyan_medium": [Color(0.35, 0.95, 1.0), 60.0], "mushroom_violet_cluster": [Color(0.62, 0.42, 1.0), 52.0],
			"shelf_fungus_amber": [Color(1.0, 0.72, 0.3), 50.0], "moss_cushion": [Color(0.35, 0.95, 1.0), 44.0]},
		"pools": [[-100.0, -400.0, 240.0, Color(0.7, 0.4, 1.0, 0.15)], [200.0, 150.0, 220.0, Color(0.35, 0.9, 1.0, 0.11)],
			[-240.0, 520.0, 220.0, Color(1.0, 0.7, 0.4, 0.07)], [60.0, 700.0, 230.0, Color(0.62, 0.42, 1.0, 0.13)]]},
	{"id": "pond", "ground": "ground/pond.png", "tint": Color(0.84, 0.9, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["lily_pads", 8, 0.3], ["reed_clump", 8, 0.0], ["cattails", 7, 0.0], ["water_stone", 6, 0.05],
			["lantern_flower", 7, 0.1], ["floating_lantern", 8, 0.3], ["fern_clump", 4, 0.0], ["moss_cushion", 5, 0.15], ["stone_small_clover", 5, 0.2]],
		"glow": {"lantern_flower": [Color(1.0, 0.8, 0.45), 70.0], "floating_lantern": [Color(1.0, 0.8, 0.45), 56.0], "cattails": [Color(1.0, 0.8, 0.45), 40.0], "lily_pads": [Color(0.35, 0.95, 1.0), 50.0],
			"moss_cushion": [Color(0.35, 0.95, 1.0), 44.0]},
		"pools": [[0.0, -300.0, 260.0, Color(0.4, 0.8, 1.0, 0.13)], [-200.0, 300.0, 220.0, Color(1.0, 0.8, 0.5, 0.08)],
			[220.0, 600.0, 230.0, Color(0.35, 0.9, 1.0, 0.11)]]},
	{"id": "meadow", "ground": "ground/meadow.png", "detail": 0.3, "tint": Color(0.9, 0.88, 1.0), "mod": Color(1.0, 0.98, 1.0),
		"scatter": [["lotus_flower_cyan", 9, 0.1], ["flower_cluster_pink", 11, 0.1], ["bellflowers_violet", 8, 0.1],
			["glow_grass", 14, 0.2], ["flower_bush", 6, 0.0], ["dandelion_glow", 8, 0.1],
			["spore_flower", 4, 0.1], ["lantern_flower", 4, 0.1], ["fern_clump", 4, 0.0],
			["tiny_mushroom_mound", 4, 0.2], ["stone_small_clover", 3, 0.2]],
		"glow": {"lotus_flower_cyan": [Color(0.35, 0.95, 1.0), 80.0], "flower_cluster_pink": [Color(1.0, 0.45, 0.8), 70.0],
			"bellflowers_violet": [Color(0.7, 0.5, 1.0), 76.0], "glow_grass": [Color(0.4, 0.8, 1.0), 56.0],
			"flower_bush": [Color(0.8, 0.5, 1.0), 90.0], "dandelion_glow": [Color(0.8, 0.9, 1.0), 80.0],
			"spore_flower": [Color(0.35, 0.95, 1.0), 70.0], "lantern_flower": [Color(1.0, 0.8, 0.45), 70.0],
			"tiny_mushroom_mound": [Color(0.5, 0.8, 1.0), 50.0]},
		"pools": [[-120.0, -350.0, 250.0, Color(0.9, 0.5, 1.0, 0.13)], [220.0, 200.0, 220.0, Color(0.35, 0.9, 1.0, 0.11)],
			[-230.0, 560.0, 220.0, Color(0.62, 0.42, 1.0, 0.12)]]},
	{"id": "ruins", "ground": "ground/ruins.png", "detail": 0.3, "tint": Color(0.86, 0.88, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["rune_pillar", 6, 0.0], ["ruin_arch", 3, 0.0], ["rune_block", 6, 0.1], ["cat_statue", 3, 0.0],
			["stone_lantern", 6, 0.1], ["brick_pile", 7, 0.1], ["fern_clump", 6, 0.0], ["moss_cushion", 6, 0.15],
			["stone_small_clover", 5, 0.2], ["cave_mushroom", 5, 0.1]],
		"glow": {"rune_pillar": [Color(0.35, 0.95, 1.0), 80.0], "rune_block": [Color(0.7, 0.45, 1.0), 76.0],
			"cat_statue": [Color(0.35, 0.95, 1.0), 60.0], "stone_lantern": [Color(1.0, 0.8, 0.45), 90.0],
			"brick_pile": [Color(0.35, 0.95, 1.0), 56.0], "cave_mushroom": [Color(0.4, 0.9, 1.0), 60.0],
			"moss_cushion": [Color(0.35, 0.95, 1.0), 44.0]},
		"pools": [[-100.0, -380.0, 240.0, Color(0.35, 0.9, 1.0, 0.12)], [220.0, 180.0, 220.0, Color(0.62, 0.42, 1.0, 0.12)],
			[-220.0, 560.0, 220.0, Color(1.0, 0.8, 0.5, 0.08)]]},
	{"id": "frost", "ground": "ground/frost.png", "detail": 0.3, "tint": Color(0.84, 0.92, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["ice_crystal_big", 7, 0.0], ["snow_fir", 6, 0.0], ["frost_flower_mound", 9, 0.2],
			["ice_flower", 9, 0.1], ["snow_boulder", 6, 0.0], ["snow_spirit", 4, 0.1],
			["crystal_cluster_cyan", 4, 0.1], ["stone_small_clover", 3, 0.2]],
		"glow": {"ice_crystal_big": [Color(0.5, 0.9, 1.0), 100.0], "snow_fir": [Color(1.0, 0.85, 0.55), 70.0],
			"frost_flower_mound": [Color(0.5, 0.8, 1.0), 50.0], "ice_flower": [Color(0.6, 0.9, 1.0), 76.0],
			"snow_spirit": [Color(0.5, 0.95, 1.0), 70.0], "crystal_cluster_cyan": [Color(0.35, 0.95, 1.0), 80.0]},
		"pools": [[-100.0, -380.0, 250.0, Color(0.6, 0.85, 1.0, 0.14)], [220.0, 160.0, 220.0, Color(0.7, 0.6, 1.0, 0.11)],
			[-220.0, 560.0, 230.0, Color(0.5, 0.9, 1.0, 0.11)]]},
	{"id": "dunes", "ground": "ground/dunes.png", "detail": 0.0, "tint": Color(0.92, 0.86, 1.0), "mod": Color(1.0, 0.98, 1.0),
		"scatter": [["crystal_cactus", 7, 0.0], ["spiral_shell", 5, 0.1], ["sandstone_arch", 3, 0.0],
			["glow_succulent", 10, 0.2], ["dune_flower_mound", 8, 0.2], ["sand_boulder", 6, 0.0],
			["crystal_purple", 5, 0.3], ["stone_small_clover", 3, 0.2]],
		"glow": {"crystal_cactus": [Color(0.5, 0.9, 1.0), 90.0], "spiral_shell": [Color(1.0, 0.7, 0.9), 60.0],
			"glow_succulent": [Color(0.4, 0.95, 1.0), 56.0], "dune_flower_mound": [Color(1.0, 0.6, 0.9), 60.0],
			"crystal_purple": [Color(0.62, 0.42, 1.0), 46.0]},
		"pools": [[-100.0, -380.0, 250.0, Color(0.8, 0.6, 1.0, 0.13)], [220.0, 160.0, 220.0, Color(0.4, 0.9, 1.0, 0.11)],
			[-220.0, 560.0, 230.0, Color(1.0, 0.7, 0.9, 0.09)]]},
	{"id": "swamp", "ground": "ground/swamp.png", "detail": 0.0, "tint": Color(0.82, 0.95, 0.98), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["mangrove_roots", 6, 0.0], ["glow_lilies", 9, 0.2], ["swamp_shrooms", 8, 0.1], ["glow_reeds", 9, 0.0],
			["mossy_log_swamp", 4, 0.0], ["algae_mound", 7, 0.15], ["tiny_mushroom_mound", 4, 0.2], ["fern_clump", 4, 0.0]],
		"glow": {"glow_lilies": [Color(0.9, 0.5, 1.0), 60.0], "swamp_shrooms": [Color(0.4, 0.95, 0.9), 80.0],
			"glow_reeds": [Color(0.5, 1.0, 0.6), 70.0], "algae_mound": [Color(0.5, 1.0, 0.6), 60.0],
			"mangrove_roots": [Color(0.4, 0.95, 1.0), 80.0], "mossy_log_swamp": [Color(0.4, 0.95, 0.9), 50.0]},
		"pools": [[-100.0, -380.0, 250.0, Color(0.3, 0.95, 0.8, 0.13)], [220.0, 160.0, 220.0, Color(0.5, 1.0, 0.6, 0.10)],
			[-220.0, 560.0, 230.0, Color(0.4, 0.8, 1.0, 0.11)]]},
	{"id": "reef", "ground": "ground/reef.png", "detail": 0.0, "tint": Color(0.82, 0.92, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["coral_pink", 8, 0.0], ["coral_violet_fan", 6, 0.0], ["coral_cyan_tubes", 8, 0.05], ["reef_shell", 7, 0.2],
			["sea_grass_glow", 12, 0.1], ["starfish_rock", 5, 0.0], ["glow_succulent", 4, 0.2], ["spiral_shell", 4, 0.2]],
		"glow": {"coral_pink": [Color(1.0, 0.5, 0.8), 80.0], "coral_violet_fan": [Color(0.7, 0.5, 1.0), 90.0],
			"coral_cyan_tubes": [Color(0.4, 0.95, 1.0), 80.0], "reef_shell": [Color(1.0, 0.7, 0.9), 56.0],
			"sea_grass_glow": [Color(0.4, 0.95, 1.0), 60.0], "starfish_rock": [Color(1.0, 0.6, 0.7), 50.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(0.5, 0.9, 1.0, 0.15)], [220.0, 160.0, 230.0, Color(0.9, 0.6, 1.0, 0.11)],
			[-220.0, 560.0, 240.0, Color(0.4, 0.8, 1.0, 0.12)]]},
	{"id": "ember", "ground": "ground/ember.png", "detail": 0.0, "tint": Color(1.0, 0.9, 0.92), "mod": Color(1.0, 0.98, 1.0),
		"scatter": [["ember_rock", 7, 0.0], ["fire_flower", 10, 0.1], ["obsidian_spire", 5, 0.0], ["ember_vent", 6, 0.15],
			["amber_crystals", 7, 0.05], ["glow_root", 6, 0.1]],
		"glow": {"ember_rock": [Color(1.0, 0.6, 0.25), 70.0], "fire_flower": [Color(1.0, 0.6, 0.2), 90.0],
			"obsidian_spire": [Color(1.0, 0.6, 0.3), 80.0], "ember_vent": [Color(1.0, 0.7, 0.3), 80.0],
			"amber_crystals": [Color(1.0, 0.75, 0.3), 80.0], "glow_root": [Color(1.0, 0.55, 0.2), 70.0]},
		"pools": [[-100.0, -380.0, 250.0, Color(1.0, 0.6, 0.3, 0.14)], [220.0, 160.0, 220.0, Color(1.0, 0.5, 0.3, 0.12)],
			[-220.0, 560.0, 230.0, Color(0.8, 0.4, 1.0, 0.10)]]},
	{"id": "cosmos", "ground": "ground/cosmos.png", "detail": 0.0, "tint": Color(0.88, 0.84, 1.0), "mod": Color(1.0, 0.98, 1.0),
		"scatter": [["star_flower", 10, 0.1], ["crystal_sprouts", 8, 0.1], ["nebula_mushroom", 6, 0.05], ["constellation_stone", 6, 0.1],
			["star_bush", 7, 0.05], ["orb_plant", 6, 0.0]],
		"glow": {"star_flower": [Color(1.0, 0.7, 1.0), 90.0], "crystal_sprouts": [Color(0.5, 0.9, 1.0), 70.0],
			"nebula_mushroom": [Color(0.8, 0.6, 1.0), 90.0], "constellation_stone": [Color(0.6, 0.8, 1.0), 60.0],
			"star_bush": [Color(1.0, 0.7, 1.0), 90.0], "orb_plant": [Color(0.7, 0.9, 1.0), 100.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(0.8, 0.6, 1.0, 0.15)], [220.0, 160.0, 230.0, Color(0.5, 0.8, 1.0, 0.12)],
			[-220.0, 560.0, 240.0, Color(1.0, 0.6, 0.9, 0.11)]]},
	{"id": "clouds", "ground": "ground/clouds.png", "detail": 0.0, "tint": Color(0.95, 0.9, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["cloud_puff", 8, 0.1], ["floating_islet", 4, 0.0], ["sky_crystal", 7, 0.05], ["cloud_flower", 8, 0.1],
			["star_chime", 5, 0.0], ["rainbow_orb", 7, 0.2]],
		"glow": {"floating_islet": [Color(1.0, 0.7, 1.0), 90.0], "sky_crystal": [Color(0.6, 0.85, 1.0), 80.0],
			"cloud_flower": [Color(1.0, 0.8, 0.95), 70.0], "star_chime": [Color(1.0, 0.9, 0.5), 80.0],
			"rainbow_orb": [Color(0.9, 0.8, 1.0), 80.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.8, 1.0, 0.14)], [220.0, 160.0, 230.0, Color(1.0, 0.9, 0.6, 0.11)],
			[-220.0, 560.0, 240.0, Color(0.7, 0.8, 1.0, 0.12)]]},
	{"id": "roots", "ground": "ground/roots.png", "detail": 0.0, "tint": Color(0.95, 0.98, 0.9), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["root_arch", 4, 0.0], ["gold_mushrooms", 8, 0.1], ["golden_leaf_pile", 8, 0.2], ["root_sprout", 7, 0.1],
			["hollow_root_stump", 4, 0.0], ["amber_seed_pod", 6, 0.1]],
		"glow": {"root_arch": [Color(1.0, 0.8, 0.3), 90.0], "gold_mushrooms": [Color(1.0, 0.8, 0.3), 80.0],
			"golden_leaf_pile": [Color(1.0, 0.8, 0.3), 56.0], "root_sprout": [Color(1.0, 0.85, 0.4), 70.0],
			"hollow_root_stump": [Color(1.0, 0.8, 0.3), 80.0], "amber_seed_pod": [Color(1.0, 0.75, 0.3), 80.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.8, 0.3, 0.14)], [220.0, 160.0, 230.0, Color(0.5, 0.9, 0.7, 0.10)],
			[-220.0, 560.0, 240.0, Color(1.0, 0.75, 0.3, 0.12)]]},
	{"id": "bamboo", "ground": "ground/bamboo.png", "detail": 0.0, "tint": Color(0.9, 1.0, 0.98), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["bamboo_cluster", 7, 0.0], ["bamboo_lantern", 5, 0.05], ["lotus_pond_small", 3, 0.15], ["zen_stones", 5, 0.1],
			["blossom_bush", 5, 0.05], ["petal_ferns", 8, 0.0]],
		"glow": {"bamboo_cluster": [Color(0.6, 1.0, 0.7), 60.0], "bamboo_lantern": [Color(1.0, 0.8, 0.4), 90.0],
			"lotus_pond_small": [Color(1.0, 0.6, 0.9), 70.0], "blossom_bush": [Color(1.0, 0.7, 0.9), 70.0]},
		"pools": [[-100.0, -380.0, 250.0, Color(0.7, 1.0, 0.8, 0.12)], [220.0, 160.0, 220.0, Color(1.0, 0.8, 0.5, 0.11)],
			[-220.0, 560.0, 230.0, Color(1.0, 0.7, 0.9, 0.10)]]},
	{"id": "autumn", "ground": "ground/autumn.png", "detail": 0.0, "tint": Color(1.0, 0.94, 0.88), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["red_leaf_pile", 8, 0.15], ["glow_pumpkin", 7, 0.1], ["acorn_cluster", 8, 0.2], ["maple_sapling", 5, 0.0],
			["orange_mushrooms", 7, 0.1], ["autumn_log", 4, 0.0]],
		"glow": {"red_leaf_pile": [Color(1.0, 0.5, 0.2), 70.0], "glow_pumpkin": [Color(1.0, 0.65, 0.2), 90.0],
			"maple_sapling": [Color(1.0, 0.7, 0.2), 90.0], "orange_mushrooms": [Color(1.0, 0.65, 0.3), 80.0],
			"autumn_log": [Color(1.0, 0.7, 0.3), 56.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.6, 0.2, 0.14)], [220.0, 160.0, 230.0, Color(1.0, 0.5, 0.3, 0.12)],
			[-220.0, 560.0, 240.0, Color(0.8, 0.5, 1.0, 0.10)]]},
	{"id": "prism", "ground": "ground/prism.png", "detail": 0.0, "tint": Color(0.92, 0.88, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["prism_crystal_big", 7, 0.00], ["rainbow_geode", 7, 0.10], ["crystal_bloom", 8, 0.10], ["prism_arch", 3, 0.00], ["light_orbs", 8, 0.20], ["crystal_shroom", 6, 0.10]],
		"glow": {"prism_crystal_big": [Color(1.0, 0.7, 1.0), 100.0], "rainbow_geode": [Color(0.6, 0.9, 1.0), 80.0], "crystal_bloom": [Color(1.0, 0.8, 0.6), 70.0], "prism_arch": [Color(0.8, 0.7, 1.0), 110.0], "light_orbs": [Color(1.0, 1.0, 1.0), 70.0], "crystal_shroom": [Color(0.6, 1.0, 0.9), 80.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.6, 1.0, 0.14)], [220.0, 160.0, 230.0, Color(0.5, 0.9, 1.0, 0.11)], [-220.0, 560.0, 240.0, Color(1.0, 0.9, 0.5, 0.12)]]},
	{"id": "lanterns", "ground": "ground/lanterns.png", "detail": 0.0, "tint": Color(0.9, 0.92, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["lantern_raft", 8, 0.20], ["lotus_lantern", 9, 0.20], ["dock_piece", 4, 0.00], ["paper_boat", 6, 0.20], ["lantern_post", 6, 0.05], ["reed_lights", 8, 0.00]],
		"glow": {"lantern_raft": [Color(1.0, 0.8, 0.4), 90.0], "lotus_lantern": [Color(1.0, 0.7, 0.8), 80.0], "paper_boat": [Color(1.0, 0.85, 0.5), 60.0], "lantern_post": [Color(1.0, 0.8, 0.4), 110.0], "reed_lights": [Color(1.0, 0.85, 0.5), 70.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.8, 0.4, 0.14)], [220.0, 160.0, 230.0, Color(0.5, 0.6, 1.0, 0.11)], [-220.0, 560.0, 240.0, Color(1.0, 0.7, 0.8, 0.12)]]},
	{"id": "clockwork", "ground": "ground/clockwork.png", "detail": 0.0, "tint": Color(1.0, 0.96, 0.9), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["brass_gear", 6, 0.00], ["gear_flower", 8, 0.10], ["clock_shroom", 6, 0.10], ["copper_coil", 5, 0.00], ["cog_stones", 6, 0.10], ["brass_lamp", 5, 0.05]],
		"glow": {"brass_gear": [Color(1.0, 0.75, 0.4), 70.0], "gear_flower": [Color(0.5, 0.95, 1.0), 80.0], "clock_shroom": [Color(1.0, 0.7, 0.3), 80.0], "copper_coil": [Color(1.0, 0.7, 0.4), 70.0], "brass_lamp": [Color(1.0, 0.8, 0.4), 110.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.75, 0.4, 0.14)], [220.0, 160.0, 230.0, Color(0.4, 0.9, 1.0, 0.11)], [-220.0, 560.0, 240.0, Color(1.0, 0.6, 0.3, 0.12)]]},
	{"id": "shore", "ground": "ground/shore.png", "detail": 0.0, "tint": Color(0.88, 0.94, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["shell_pile", 8, 0.20], ["tide_rock", 6, 0.00], ["glow_jelly", 6, 0.15], ["driftwood_glow", 5, 0.05], ["urchin_crystal", 7, 0.10], ["kelp_tuft", 9, 0.00]],
		"glow": {"shell_pile": [Color(1.0, 0.7, 0.9), 60.0], "tide_rock": [Color(0.4, 0.95, 1.0), 70.0], "glow_jelly": [Color(0.5, 1.0, 1.0), 90.0], "driftwood_glow": [Color(0.4, 0.95, 1.0), 60.0], "urchin_crystal": [Color(0.8, 0.6, 1.0), 70.0], "kelp_tuft": [Color(0.4, 1.0, 0.8), 60.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(0.4, 0.95, 1.0, 0.14)], [220.0, 160.0, 230.0, Color(1.0, 0.6, 0.9, 0.11)], [-220.0, 560.0, 240.0, Color(0.5, 0.8, 1.0, 0.12)]]},
	{"id": "village", "ground": "ground/village.png", "detail": 0.0, "tint": Color(0.95, 0.92, 1.0), "mod": Color(1.0, 1.0, 1.0),
		"scatter": [["mushroom_house", 5, 0.00], ["tiny_cottage", 4, 0.00], ["flower_bed", 8, 0.15], ["fence_piece", 6, 0.10], ["village_lantern", 7, 0.05], ["toadstool_tower", 3, 0.00]],
		"glow": {"mushroom_house": [Color(1.0, 0.8, 0.4), 100.0], "tiny_cottage": [Color(1.0, 0.8, 0.4), 100.0], "flower_bed": [Color(1.0, 0.7, 0.9), 60.0], "village_lantern": [Color(1.0, 0.8, 0.4), 100.0], "toadstool_tower": [Color(1.0, 0.8, 0.5), 110.0]},
		"pools": [[-100.0, -380.0, 260.0, Color(1.0, 0.8, 0.4, 0.14)], [220.0, 160.0, 230.0, Color(0.7, 0.6, 1.0, 0.11)], [-220.0, 560.0, 240.0, Color(1.0, 0.7, 0.5, 0.12)]]},
]

## Flat ground decals (no y-sort): the pond and glowing mycelium threads.
const DECALS: Array = [
	## [file, centre x, centre y, width px, additive, alpha, flip]
	["decals/mycelium_a.png", 20.0, -600.0, 240.0, true, 0.53, false],
	["decals/mycelium_b.png", 210.0, -560.0, 150.0, true, 0.50, true],
	["decals/mycelium_a.png", -250.0, -80.0, 200.0, true, 0.43, true],
	["decals/mycelium_b.png", 230.0, 60.0, 140.0, true, 0.43, false],
	["decals/mycelium_a.png", -200.0, 420.0, 220.0, true, 0.46, false],
	["decals/mycelium_b.png", 200.0, 640.0, 160.0, true, 0.43, true],
	["decals/lily_pond.png", -335.0, -300.0, 130.0, false, 1.0, false],
	["decals/puddle_ripples.png", 345.0, 330.0, 110.0, false, 1.0, true],
	["decals/moss_pool.png", -330.0, 520.0, 110.0, false, 1.0, false],
	["decals/spore_dots.png", -330.0, -20.0, 110.0, true, 0.9, false],
	["decals/spore_dots.png", 250.0, 700.0, 110.0, true, 0.9, true],
	["decals/spore_dots.png", 60.0, -700.0, 130.0, true, 0.9, false],
]


func _build_decals() -> void:
	for i in range(DECALS.size()):
		var d: Array = DECALS[i]
		var tex := _tex(ART + d[0])
		var s := Sprite2D.new()
		s.name = "Decal%d" % i
		s.texture = tex
		var k: float = float(d[3]) / float(tex.get_width())
		s.scale = Vector2(-k if d[6] else k, k)
		s.position = Vector2(d[1], d[2])
		s.z_index = -50 if not d[4] else -40
		s.modulate = Color(0.45, 1.0, 1.0, d[5]) if d[4] else Color(1, 1, 1, d[5])  # cyan-only: kills the magenta key fringe
		if d[4]:
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			s.material = mat
			s.set_meta("phase", _rng.randf() * TAU)
			s.set_meta("base", d[5])
			_pulsing.append(s)
		add_child(s)
	var gl := Sprite2D.new()
	gl.name = "PondGlow"
	gl.texture = SOFT_GLOW
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	gl.material = m
	gl.modulate = Color(CYAN.r, CYAN.g, CYAN.b, 0.16)
	gl.scale = Vector2(2.6, 1.6)
	gl.position = Vector2(300.0, -455.0)
	gl.z_index = -39
	add_child(gl)


func _build_props() -> void:
	for i in range(LAYOUT.size()):
		var e: Array = LAYOUT[i]
		var node := _make_prop(e[0], Vector2(e[1], e[2]), e[3])
		node.name = "%s_%d" % [e[0], i]
		if e[4] != null:
			_add_glow(node, e[4], e[5])
	_scatter_props()


func _scatter_props() -> void:
	var placed: Array[Vector2] = []
	for e in LAYOUT:
		placed.append(Vector2(e[1], e[2]))
	_scatter(SCATTER, SCATTER_GLOW, 0.0, placed, "s")
	for k in _active_zones:
		var z: Dictionary = ZONES[k]
		var glow := {}
		for key in z["glow"]:
			glow[key] = z["glow"][key]
		_scatter(z["scatter"], glow, _zone_y(k + 1), [] as Array[Vector2], "z%d" % k, z)


## True where the glade plate shows the lilac dirt path (plus a margin), so nothing blocks it.
func _on_path(pos: Vector2, margin: float = 26.0) -> bool:
	if _path_img == null:
		_path_img = (_tex(GROUND_PATH) as Texture2D).get_image()
	var half := Vector2(_path_img.get_width(), _path_img.get_height()) * 0.5 / GROUND_SCALE
	for off in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin),
			Vector2(margin, margin) * 0.7, Vector2(-margin, margin) * 0.7, Vector2(margin, -margin) * 0.7, Vector2(-margin, -margin) * 0.7]:
		var px := Vector2i(((pos + off + half) * GROUND_SCALE).round())
		if px.x < 0 or px.y < 0 or px.x >= _path_img.get_width() or px.y >= _path_img.get_height():
			continue
		var c := _path_img.get_pixelv(px)
		if c.r > 0.38 and c.b > c.g + 0.15 and c.b > c.r:
			return true
	return false


## Hand-traced path of each zone plate: [[y, x, half-width], ...] as fractions of the plate (0..1).
## Props never stand on it. Traced from the painted plates; stands for the "open centre" of each.
const PATH_MARGIN := 0.03
const ZONE_PATHS := {
	"grotto": [[0.0, 0.5, 0.28], [1.0, 0.5, 0.28]],
	"fungal": [[0.05, 0.62, 0.12], [0.2, 0.6, 0.12], [0.35, 0.55, 0.12], [0.5, 0.58, 0.12], [0.65, 0.62, 0.12], [0.8, 0.6, 0.12], [1.0, 0.55, 0.12]],
	"pond": [[0.3, 0.7, 0.17], [0.45, 0.64, 0.17], [0.6, 0.6, 0.17], [0.75, 0.5, 0.17], [0.9, 0.4, 0.17], [1.0, 0.35, 0.17]],
	"meadow": [[0.0, 0.48, 0.3], [1.0, 0.48, 0.3]],
	"ruins": [[0.0, 0.5, 0.32], [1.0, 0.5, 0.32]],
	"frost": [[0.0, 0.55, 0.25], [0.5, 0.45, 0.25], [1.0, 0.5, 0.25]],
	"dunes": [[0.0, 0.45, 0.35], [1.0, 0.45, 0.35]],
	"swamp": [[0.0, 0.65, 0.14], [0.2, 0.6, 0.14], [0.4, 0.52, 0.14], [0.6, 0.5, 0.14], [0.8, 0.48, 0.14], [1.0, 0.55, 0.14]],
	"reef": [[0.0, 0.5, 0.25], [0.5, 0.55, 0.25], [1.0, 0.45, 0.25]],
	"ember": [[0.0, 0.5, 0.3], [1.0, 0.5, 0.3]],
	"cosmos": [[0.0, 0.5, 0.25], [1.0, 0.5, 0.25]],
	"clouds": [[0.05, 0.62, 0.13], [0.3, 0.68, 0.13], [0.5, 0.72, 0.13], [0.62, 0.62, 0.13], [0.75, 0.5, 0.13], [0.88, 0.4, 0.13], [1.0, 0.3, 0.13]],
	"roots": [[0.0, 0.4, 0.14], [0.3, 0.4, 0.14], [0.5, 0.45, 0.14], [0.7, 0.5, 0.14], [0.9, 0.5, 0.14]],
	"bamboo": [[0.05, 0.8, 0.12], [0.2, 0.78, 0.12], [0.35, 0.6, 0.12], [0.5, 0.3, 0.12], [0.6, 0.35, 0.12], [0.75, 0.5, 0.12], [0.9, 0.6, 0.12], [1.0, 0.62, 0.12]],
	"prism": [[0.0, 0.5, 0.25], [1.0, 0.5, 0.25]],
	"lanterns": [[0.0, 0.58, 0.11], [0.15, 0.52, 0.11], [0.3, 0.55, 0.11], [0.45, 0.47, 0.11], [0.6, 0.43, 0.11], [0.75, 0.38, 0.11], [0.9, 0.38, 0.11], [1.0, 0.4, 0.11]],
	"clockwork": [[0.05, 0.62, 0.12], [0.3, 0.58, 0.12], [0.5, 0.52, 0.12], [0.7, 0.46, 0.12], [0.9, 0.43, 0.12], [1.0, 0.43, 0.12]],
	"shore": [[0.0, 0.6, 0.2], [0.5, 0.58, 0.2], [1.0, 0.55, 0.2]],
	"village": [[0.0, 0.62, 0.11], [0.15, 0.42, 0.11], [0.3, 0.3, 0.11], [0.45, 0.32, 0.11], [0.6, 0.45, 0.11], [0.75, 0.55, 0.11], [0.9, 0.6, 0.11], [1.0, 0.6, 0.11]],
	"autumn": [[0.05, 0.78, 0.14], [0.2, 0.8, 0.14], [0.35, 0.68, 0.14], [0.5, 0.45, 0.14], [0.65, 0.3, 0.14], [0.8, 0.3, 0.14], [0.95, 0.25, 0.14]],
}


func _path_at(zone_id: String, fy: float) -> Vector2:
	var pts: Array = ZONE_PATHS.get(zone_id, [])
	if pts.is_empty():
		return Vector2(0.5, 0.2)
	if fy <= float(pts[0][0]):
		return Vector2(pts[0][1], pts[0][2])
	for i in range(1, pts.size()):
		if fy <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			var t := inverse_lerp(float(a[0]), float(b[0]), fy)
			return Vector2(lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t))
	var l: Array = pts[pts.size() - 1]
	return Vector2(l[1], l[2])


func _on_zone_path(zone: Dictionary, local: Vector2) -> bool:
	var tex := _tex(ART + String(zone["ground"])) as Texture2D
	var fx := (local.x / GROUND_SCALE + float(tex.get_width()) * 0.5) / float(tex.get_width())
	var fy := (local.y / GROUND_SCALE + float(tex.get_height()) * 0.5) / float(tex.get_height())
	var p := _path_at(String(zone["id"]), fy)
	return absf(fx - p.x) < p.y + PATH_MARGIN


## Debug: each zone plate with its traced path tinted red.
func _dump_masks(dir: String) -> void:
	for k in _active_zones:
		var z: Dictionary = ZONES[k]
		var img: Image = (_tex(ART + String(z["ground"])) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		for y in range(img.get_height()):
			var p := _path_at(String(z["id"]), float(y) / float(img.get_height()))
			for x in range(img.get_width()):
				if absf(float(x) / float(img.get_width()) - p.x) < p.y + PATH_MARGIN:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(1, 0, 0), 0.45))
		img.save_png("%s/mask_%s.png" % [dir, z["id"]])


func _scatter(spec: Array, glow_table: Dictionary, y_off: float, placed: Array[Vector2], tag: String, zone: Dictionary = {}) -> void:
	var n := 0
	for entry in spec:
		var prop_name: String = entry[0]
		if not PROPS.has(prop_name) or not ResourceLoader.exists(ART + String(PROPS[prop_name][0])):
			continue
		for _i in range(int(entry[1])):
			for _attempt in range(40):
				var edge := _rng.randf() >= float(entry[2])
				var x := _rng.randf_range(-PLAY_HALF.x, PLAY_HALF.x)
				if edge:
					x = signf(_rng.randf() - 0.5) * _rng.randf_range(95.0, PLAY_HALF.x + 110.0)
				var pos := Vector2(x, y_off + _rng.randf_range(-PLAY_HALF.y + 40.0, PLAY_HALF.y))
				if y_off == 0.0 and pos.distance_to(Vector2(0.0, 120.0)) < 90.0:
					continue
				if y_off == 0.0 and prop_name != "stepping_stones" and _on_path(pos):
					continue
				if not zone.is_empty() and _on_zone_path(zone, pos - Vector2(0.0, y_off)):
					continue
				var ok := true
				for q in placed:
					if q.distance_to(pos) < SCATTER_MIN_GAP:
						ok = false
						break
				if not ok:
					continue
				placed.append(pos)
				var node := _make_prop(prop_name, pos, _rng.randf() < 0.5)
				node.name = "%s_%s%d" % [prop_name, tag, n]
				n += 1
				if glow_table.has(prop_name):
					_add_glow(node, glow_table[prop_name][0], glow_table[prop_name][1])
				break


## Soft props sway in the wind and part when the slime passes; value = sway in world px.
## Hard things (stones, crystals, stumps, big caps) stay still.
const SWAY := {
	"fern_clump": 5.0, "crystal_bloom": 3.0, "reed_lights": 6.0, "gear_flower": 4.0, "kelp_tuft": 6.0, "flower_bed": 2.0, "lantern_post": 1.5, "bamboo_cluster": 3.5, "petal_ferns": 5.0, "maple_sapling": 4.0, "root_sprout": 5.0, "cloud_flower": 3.0, "star_chime": 4.0, "blossom_bush": 2.5, "glow_reeds": 7.0, "sea_grass_glow": 7.0, "fire_flower": 4.0, "star_flower": 4.0, "orb_plant": 3.0, "glow_lilies": 1.5, "coral_violet_fan": 2.0, "tall_lavender_mushroom": 3.0, "teal_bell_mushroom": 3.0, "cyan_mushroom_trio": 2.0, "dew_leaf_burgundy": 2.0, "dew_leaves_green": 3.0, "teal_grass_tuft": 6.0, "glow_succulent": 2.0, "dune_flower_mound": 2.5, "ice_flower": 3.0, "snow_fir": 2.5, "brick_pile": 1.5, "leaf_plant_violet": 6.0, "lotus_flower_cyan": 3.0, "flower_cluster_pink": 3.5,
	"bellflowers_violet": 6.0, "glow_grass": 7.0, "flower_bush": 3.0, "dandelion_glow": 6.0, "moss_cushion": 1.5,
	"spore_flower": 6.0, "hanging_mushroom_pink": 4.0, "tiny_mushroom_mound": 1.5,
	"reed_clump": 7.0, "cattails": 7.0, "lantern_flower": 5.0, "lily_pads": 1.5,
	"mushroom_violet_cluster": 1.5, "mushroom_cyan_medium": 2.0,
}
const SWAY_SHADER := preload("res://shaders/sway.gdshader")
var _sway_mats: Dictionary = {}


func _sway_material(amount: float) -> ShaderMaterial:
	if not _sway_mats.has(amount):
		var m := ShaderMaterial.new()
		m.shader = SWAY_SHADER
		m.set_shader_parameter("amount", amount)
		_sway_mats[amount] = m
	return _sway_mats[amount]


## A prop is a Node2D whose origin is its base line, so y-sort reads the feet.
func _make_prop(prop_name: String, pos: Vector2, flip: bool) -> Node2D:
	var def: Array = PROPS[prop_name]
	var tex := _tex(ART + def[0])
	var node := Node2D.new()
	node.position = pos
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.94)
	var k: float = float(def[1]) / float(tex.get_height())
	s.scale = Vector2(-k if flip else k, k)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if SWAY.has(prop_name) and not _no_sway:
		s.material = _sway_material(float(SWAY[prop_name]))
	node.add_child(_contact_shadow(float(def[1]), tex.get_width() * k))
	node.add_child(s)
	_props_root.add_child(node)
	return node


func _contact_shadow(h: float, w: float) -> Sprite2D:
	var sh := Sprite2D.new()
	sh.name = "Shadow"
	sh.texture = SOFT_GLOW
	sh.modulate = Color(0.02, 0.04, 0.08, 0.55)
	sh.scale = Vector2(w * 0.95 / 128.0, h * 0.30 / 128.0)
	sh.position = Vector2(h * 0.05, -h * 0.02)
	sh.show_behind_parent = true
	return sh


func _add_glow(parent: Node2D, color: Color, radius: float) -> void:
	var gl := Sprite2D.new()
	gl.name = "Glow"
	gl.texture = SOFT_GLOW
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	gl.material = mat
	gl.modulate = Color(color.r, color.g, color.b, 0.34)
	gl.scale = Vector2.ONE * radius * 2.0 / 128.0
	gl.position = Vector2(0.0, -radius * 0.45)
	gl.set_meta("phase", _rng.randf() * TAU)
	gl.set_meta("base", 0.34)
	parent.add_child(gl)
	_glows.append(gl)


## --- gameplay layer -----------------------------------------------------------

func _build_player() -> void:
	player = PlayerSlime.new()
	player.name = "Player"
	_props_root.add_child(player)
	player.initialize_for_run(self)
	player.peak_mass = MassSystem.MAX_MASS  # lab must not write the save stat
	player.global_position = Vector2(0.0, 120.0)
	if Slime25D.available() and not OS.get_cmdline_user_args().has("--g25-oldslime"):
		hero = Slime25D.new()
		_props_root.add_child(hero)
		hero.setup(player)


## Arena contract used by PlayerSlime: keep the slime on the glade.
func constrain_player_position(pos: Vector2, radius: float, _dashing: bool) -> Vector2:
	var b := play_bounds()
	return Vector2(
		clampf(pos.x, b.position.x + radius, b.end.x - radius),
		clampf(pos.y, b.position.y + radius, b.end.y - radius))


func _physics_process(_delta: float) -> void:
	_steer()
	var reach := player.get_radius() + FOOD_REACH
	for f in food:
		if player.global_position.distance_to(f["pos"]) < reach:
			_absorb(f)


func _steer() -> void:
	if _touching:
		var to := get_global_mouse_position() - player.global_position
		player.move_input = to.normalized() * clampf(to.length() / 80.0, 0.0, 1.0) if to.length() > 4.0 else Vector2.ZERO
	elif auto_steer:
		_auto_angle += get_physics_process_delta_time() * 0.5
		var goal := Vector2(sin(_auto_angle) * 250.0, 40.0 + cos(_auto_angle * 0.7) * 380.0)
		player.move_input = (goal - player.global_position).normalized()
	else:
		player.move_input = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touching = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				glow_on = not glow_on
			KEY_H:
				haze_on = not haze_on
				_haze_layer.visible = haze_on
			KEY_EQUAL:
				zoom_level = minf(zoom_level + 0.1, 2.4)
			KEY_MINUS:
				zoom_level = maxf(zoom_level - 0.1, 0.8)


## --- food ---------------------------------------------------------------------

func _build_food() -> void:
	for i in range(FOOD_COUNT * (1 + _active_zones.size())):
		var crystal := i % 4 == 3
		var node := Node2D.new()
		node.name = "Food%d" % i
		var s := Sprite2D.new()
		var path := ART + ("props/crystal_purple.png" if crystal else "props/spore_bubble.png")
		s.texture = _tex(path)
		var h := 20.0 if crystal else 22.0
		var k := h / float(s.texture.get_height())
		s.scale = Vector2.ONE * k
		s.position = Vector2(0, -h * 0.5)
		node.add_child(s)
		var gl := Sprite2D.new()
		gl.texture = SOFT_GLOW
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gl.material = mat
		gl.modulate = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5) if crystal else Color(CYAN.r, CYAN.g, CYAN.b, 0.45)
		gl.scale = Vector2.ONE * 0.5
		gl.position = Vector2(0, -h * 0.5)
		node.add_child(gl)
		_props_root.add_child(node)
		var f := {"node": node, "crystal": crystal, "pos": Vector2.ZERO, "phase": _rng.randf() * TAU}
		food.append(f)
		_place_food(f)


func _place_food(f: Dictionary) -> void:
	for _attempt in range(16):
		var b := play_bounds()
		var p := Vector2(_rng.randf_range(b.position.x + 70.0, b.end.x - 70.0),
				_rng.randf_range(b.position.y + 120.0, b.end.y - 120.0))
		if player == null or p.distance_to(player.global_position) > 160.0:
			f["pos"] = p
			break
	(f["node"] as Node2D).position = f["pos"]


func _absorb(f: Dictionary) -> void:
	var gain := 1.4 if f["crystal"] else 0.8
	player.mass = MassSystem.clamp_mass(player.mass + MassSystem.effective_gain(player.mass, gain))
	player._sync_mass_metrics()
	var local: Vector2 = (f["pos"] as Vector2) - player.global_position
	var v := player.visual
	if hero != null:
		hero.gulp()
	elif v is SlimeVisualClaude:
		(v as SlimeVisualClaude).trigger_swallow(local, VIOLET if f["crystal"] else CYAN, 7.0)
	else:
		v.trigger_gulp()
	if f["crystal"]:
		Audio.play_sfx("absorb", 0.94 + 0.05 * float(Audio.chime_step() % 5))
	else:
		Audio.play_orb_chime()
	_place_food(f)


## --- camera, light, haze ------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	var r := ground_rect()
	_camera.limit_left = int(r.position.x)
	_camera.limit_right = int(r.end.x)
	_camera.limit_top = int(r.position.y)
	_camera.limit_bottom = int(r.end.y)
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS  # physics interpolation is on
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0
	add_child(_camera)
	_camera.make_current()


func _build_atmosphere() -> void:
	# One cool tint over everything painted: pulls the brighter sprites toward the
	# concept's moonlit blue-teal without repainting them.
	_tint = CanvasModulate.new()
	_tint.color = Color(0.9, 0.87, 1.0)
	add_child(_tint)

	_haze_layer = CanvasLayer.new()
	_haze_layer.name = "Haze"
	_haze_layer.layer = 5
	add_child(_haze_layer)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.27, 0.29, 0.56, 0.34), Color(0.27, 0.29, 0.56, 0.08),
		Color(0.1, 0.16, 0.3, 0.0), Color(0.04, 0.07, 0.12, 0.38)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	var veil := TextureRect.new()
	veil.texture = gt
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze_layer.add_child(veil)
	# Vignette: darker rim keeps the open centre as the focus.
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.02, 0.04, 0.08, 0.0), Color(0.02, 0.04, 0.08, 0.5)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 0.85)
	vt.width = 128
	vt.height = 256
	var vig := TextureRect.new()
	vig.texture = vt
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze_layer.add_child(vig)
	# Sky beams from the upper-left: soft-edged shafts that fade out downwards.
	var beam_tex := _beam_texture()
	var beam_root := Node2D.new()
	_haze_layer.add_child(beam_root)
	var shafts := [[70.0, 0.30, 150.0], [250.0, 0.22, 210.0], [430.0, 0.26, 130.0], [610.0, 0.16, 170.0]]
	for i in range(shafts.size()):
		var sp := Sprite2D.new()
		sp.texture = beam_tex
		sp.centered = false
		sp.offset = Vector2(-beam_tex.get_width() * 0.5, 0.0)
		sp.position = Vector2(float(shafts[i][0]), -40.0)
		sp.rotation = deg_to_rad(-17.0)
		sp.scale = Vector2(float(shafts[i][2]) / float(beam_tex.get_width()), 1250.0 / float(beam_tex.get_height()))
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sp.material = m
		sp.modulate = Color(0.62, 0.7, 1.0, float(shafts[i][1]))
		sp.set_meta("phase", float(i) * 1.7)
		sp.set_meta("base", float(shafts[i][1]))
		beam_root.add_child(sp)
		_beams.append(sp)

	# Ground light: pools of cool moonlight and coloured mushroom light on the floor
	# (world space, additive, under the props).
	var all_pools: Array = LIGHT_POOLS.duplicate()
	for k in _active_zones:
		for zp in ZONES[k]["pools"]:
			all_pools.append([zp[0], zp[1] + _zone_y(k + 1), zp[2], zp[3]])
	for pool in all_pools:
		var gl := Sprite2D.new()
		gl.texture = SOFT_GLOW
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gl.material = mat
		var c: Color = pool[3]
		gl.modulate = c
		gl.scale = Vector2(float(pool[2]) * 2.0 / 128.0, float(pool[2]) * 1.25 / 128.0)
		gl.position = Vector2(pool[0], pool[1])
		gl.z_index = -60
		gl.set_meta("phase", _rng.randf() * TAU)
		gl.set_meta("base", c.a)
		add_child(gl)
		_pulsing.append(gl)


## Soft shaft: bright core, feathered sides, fading towards the bottom.
func _beam_texture() -> ImageTexture:
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := 1.0 - float(y) / float(h - 1)
		v = v * v * (3.0 - 2.0 * v)
		for x in range(w):
			var u := absf(float(x) / float(w - 1) * 2.0 - 1.0)
			var side := 1.0 - smoothstep(0.0, 1.0, u)
			side *= side
			var a := side * v
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_clock += delta
	_camera.zoom = Vector2.ONE * _zoom_for_mass()
	_tint.color = _tint_for_y(player.global_position.y)
	_camera.global_position = player.global_position
	for m: ShaderMaterial in _sway_mats.values():
		m.set_shader_parameter("slime_pos", player.global_position)
	for gl in _glows:
		gl.visible = glow_on
		var ph: float = gl.get_meta("phase")
		var b: float = gl.get_meta("base")
		gl.modulate.a = b * (0.78 + 0.22 * sin(_clock * 1.3 + ph))
	for sp in _pulsing:
		sp.modulate.a = float(sp.get_meta("base")) * (0.7 + 0.3 * sin(_clock * 0.9 + float(sp.get_meta("phase"))))
	for f in food:
		var n: Node2D = f["node"]
		n.get_child(0).position.y = -11.0 + 2.2 * sin(_clock * 2.0 + float(f["phase"]))
	for p in _beams:
		p.modulate.a = float(p.get_meta("base")) * (0.7 + 0.3 * sin(_clock * 0.35 + float(p.get_meta("phase"))))


## Biome light: the grade of the zone the slime is in, blended across the overlap.
func _tint_for_y(y: float) -> Color:
	var base := Color(0.9, 0.87, 1.0)
	if _tint_override:
		return _tint.color
	var f := clampf(-y / ZONE_SPACING, 0.0, float(ZONES.size()))
	var i := int(floorf(f))
	var w := smoothstep(0.35, 0.65, f - floorf(f))
	var a: Color = base if i == 0 else (ZONES[i - 1]["tint"] if _active_zones.has(i - 1) else base)
	var b: Color = a
	if i < ZONES.size() and _active_zones.has(i):
		b = ZONES[i]["tint"]
	return a.lerp(b, w)


## The painted ground is authored for the starting size; as the slime grows the
## camera backs off so it keeps the same share of the screen.
func _zoom_for_mass() -> float:
	var r := player.get_radius()
	return zoom_level * pow(MassSystem.MIN_RADIUS / maxf(r, MassSystem.MIN_RADIUS), 0.55)


## --- capture ------------------------------------------------------------------

func _apply_capture_args() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("g25-mass"):
		player.mass = MassSystem.clamp_mass(float(args["g25-mass"]))
		player._sync_mass_metrics()
	if args.has("g25-zoom"):
		zoom_level = float(args["g25-zoom"])
	if args.has("g25-glow"):
		glow_on = args["g25-glow"] != "0"
	if args.has("g25-haze"):
		haze_on = args["g25-haze"] != "0"
		_haze_layer.visible = haze_on
	if args.has("g25-tint"):
		_tint.color = Color.html(args["g25-tint"])
		_tint_override = true
	if args.has("g25-move"):
		auto_steer = true
	if args.has("g25-pos"):
		var xy := String(args["g25-pos"]).split(",")
		player.global_position = Vector2(float(xy[0]), float(xy[1]))
	if args.has("g25-maskdump"):
		_dump_masks(String(args["g25-maskdump"]))
		quit_cleanly()
		return
	if args.has("g25-stagesheet"):
		await _stage_sheet(args["g25-stagesheet"])
		quit_cleanly()
		return
	if args.has("g25-shot"):
		var at := float(args.get("g25-at", "3"))
		await get_tree().create_timer(at).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args["g25-shot"])
		print("G25_SHOT ", args["g25-shot"])
		quit_cleanly()


## All 15 growth stages on the bare glade: one cell each, same crop size.
func _stage_sheet(path: String) -> void:
	for child in _props_root.get_children():
		if child != player and child != hero:
			child.visible = false
	for child in get_children():
		if child.name.begins_with("Decal") or child.name == "PondGlow":
			child.visible = false
	player.global_position = Vector2(0.0, 0.0)
	var cell := 330
	var cols := 5
	var sheet := Image.create(cell * cols, cell * 3, false, Image.FORMAT_RGB8)
	for i in range(EvolutionStages.COUNT):
		player.mass = MassSystem.clamp_mass(EvolutionStages.MASS_KEYS[i] + 0.4)
		player._sync_mass_metrics()
		player.velocity = Vector2.ZERO
		player.global_position = Vector2.ZERO
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var c := get_viewport().get_canvas_transform() * player.global_position
		var half := cell / 2
		var x0 := clampi(int(c.x) - half, 0, img.get_width() - cell)
		var y0 := clampi(int(c.y) - half - 20, 0, img.get_height() - cell)
		sheet.blit_rect(img, Rect2i(x0, y0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
	sheet.save_png(path)
	print("G25_SHEET ", path)


## Same exit path as the other labs: release Vorbis streams before quitting.
func quit_cleanly() -> void:
	Audio.set_process(false)
	for child in Audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	for _i in range(8):
		await get_tree().process_frame
	get_tree().quit()
