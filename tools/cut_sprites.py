"""Cut generated sprite sheets on a flat magenta background into transparent PNGs.

Usage: python3 tools/cut_sprites.py
Reads art_sources/2_5d/raw/<sheet>.png, writes resources/art/2_5d/<group>/<name>.png
and a preview on a dark background to reports/production/2_5d/.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_sources", "2_5d", "raw")
OUT = os.path.join(ROOT, "resources", "art", "2_5d")
PREVIEW = os.path.join(ROOT, "reports", "production", "2_5d")

# sheet -> (group, columns, rows, names row-major); None cell = whole image
SHEETS = {
    "mushrooms_sheet.png": ("props", 3, 2, [
        "mushroom_violet_large", "mushroom_cyan_medium", "mushroom_violet_cluster",
        "shelf_fungus_amber", "crystal_purple", "spore_bubble"]),
    "props_sheet.png": ("props", 3, 2, [
        "boulder_large", "stone_medium", "stone_small_clover",
        "moss_cushion", "fern_clump", "leaf_plant_violet"]),
    "stump.png": ("props", 1, 1, ["stump_hollow"]),
    "fungal_sheet.png": ("props", 3, 2, [
        "giant_mushroom", "giant_mushroom_cyan", "hanging_mushroom_pink",
        "tiny_mushroom_mound", "mushroom_log", "spore_flower"]),
    "pond_sheet.png": ("props", 3, 2, [
        "lily_pads", "reed_clump", "water_stone", "lantern_flower", "cattails", "floating_lantern"]),
    "ornaments_sheet.png": ("ornaments", 2, 4, [
        "crown", "halo", "wing_l", "wing_r", "horn_l", "horn_r", "sigil", "fireflies"], 3),
    "grotto_sheet.png": ("props", 3, 2, [
        "crystal_cluster_violet", "crystal_cluster_cyan", "crystal_spire",
        "glow_boulder", "cave_mushroom", "stalagmite"]),
    "meadow_sheet.png": ("props", 3, 2, [
        "lotus_flower_cyan", "flower_cluster_pink", "bellflowers_violet",
        "glow_grass", "flower_bush", "dandelion_glow"]),
    "ruins_sheet.png": ("props", 3, 2, [
        "rune_pillar", "ruin_arch", "rune_block", "cat_statue", "stone_lantern", "brick_pile"]),
    "frost_sheet.png": ("props", 3, 2, [
        "ice_crystal_big", "snow_fir", "frost_flower_mound", "ice_flower", "snow_boulder", "snow_spirit"]),
    "dunes_sheet.png": ("props", 3, 2, [
        "crystal_cactus", "spiral_shell", "sandstone_arch", "glow_succulent", "dune_flower_mound", "sand_boulder"]),
    "boulders_sheet.png": ("props", 3, 2, [
        "moss_boulder_big", "moss_boulder_wide", "moss_boulder_tall", "stone_trio", "shroom_boulder", "moss_slab"]),
    "pathfoliage_sheet.png": ("props", 3, 2, [
        "dew_leaf_burgundy", "dew_leaves_green", "moss_mound_veins", "stepping_stones", "teal_grass_tuft", "lily_pad_flower"]),
    "boulders2_sheet.png": ("props", 3, 2, [
        "moss_boulder_huge", "boulder_stack", "moss_ridge", "cracked_boulder", "vine_boulder", "leaning_stones"]),
    "mushrooms2_sheet.png": ("props", 3, 2, [
        "tall_lavender_mushroom", "cyan_mushroom_trio", "pink_big_mushroom",
        "white_mushroom_pair", "teal_bell_mushroom", "purple_mushroom_bump"]),
    "water_sheet.png": ("decals", 3, 2, [
        "stone_pond", "stream_s", "puddle_ripples", "lily_pond", "stepping_pond", "moss_pool"]),
    "giants_sheet.png": ("props", 2, 2, [
        "giant_mushroom", "giant_mushroom_cyan", "leaf_plant_violet", "crystal_spire"]),
    "reef_sheet.png": ("props", 3, 2, [
        "coral_pink", "coral_violet_fan", "coral_cyan_tubes", "reef_shell", "sea_grass_glow", "starfish_rock"]),
    "ember_sheet.png": ("props", 3, 2, [
        "ember_rock", "fire_flower", "obsidian_spire", "ember_vent", "amber_crystals", "glow_root"]),
    "cosmos_sheet.png": ("props", 3, 2, [
        "star_flower", "crystal_sprouts", "nebula_mushroom", "constellation_stone", "star_bush", "orb_plant"]),
    "swamp_sheet.png": ("props", 3, 2, [
        "mangrove_roots", "glow_lilies", "swamp_shrooms", "glow_reeds", "mossy_log_swamp", "algae_mound"]),
    "clouds_sheet.png": ("props", 3, 2, [
        "cloud_puff", "floating_islet", "sky_crystal", "cloud_flower", "star_chime", "rainbow_orb"]),
    "roots_sheet.png": ("props", 3, 2, [
        "root_arch", "gold_mushrooms", "golden_leaf_pile", "root_sprout", "hollow_root_stump", "amber_seed_pod"]),
    "bamboo_sheet.png": ("props", 3, 2, [
        "bamboo_cluster", "bamboo_lantern", "lotus_pond_small", "zen_stones", "blossom_bush", "petal_ferns"]),
    "autumn_sheet.png": ("props", 3, 2, [
        "red_leaf_pile", "glow_pumpkin", "acorn_cluster", "maple_sapling", "orange_mushrooms", "autumn_log"]),
    "prism_sheet.png": ("props", 3, 2, [
        "prism_crystal_big", "rainbow_geode", "crystal_bloom", "prism_arch", "light_orbs", "crystal_shroom"]),
    "lanterns_sheet.png": ("props", 3, 2, [
        "lantern_raft", "lotus_lantern", "dock_piece", "paper_boat", "lantern_post", "reed_lights"]),
    "clockwork_sheet.png": ("props", 3, 2, [
        "brass_gear", "gear_flower", "clock_shroom", "copper_coil", "cog_stones", "brass_lamp"]),
    "shore_sheet.png": ("props", 3, 2, [
        "shell_pile", "tide_rock", "glow_jelly", "driftwood_glow", "urchin_crystal", "kelp_tuft"]),
    "village_sheet.png": ("props", 3, 2, [
        "mushroom_house", "tiny_cottage", "flower_bed", "fence_piece", "village_lantern", "toadstool_tower"]),
    "wl_pads_sheet.png": ("water/sprites", 3, 2, [
        "wl_pad_xl", "wl_pads_trio", "wl_pad_dew", "wl_pads_five", "wl_pad_curl", "wl_pads_bud"]),
    "wl_lotus_sheet.png": ("water/sprites", 3, 2, [
        "wl_lotus_pink", "wl_lotus_white", "wl_lotus_cyan", "wl_lotus_bud", "wl_lotus_purple", "wl_lotus_pod"]),
    "wl_petals_sheet.png": ("water/sprites", 3, 2, [
        "wl_petals_pink", "wl_duck_a", "wl_duck_b", "wl_leaf_single", "wl_petals_white", "wl_leaf_raft"]),
    "wl_fish_sheet.png": ("water/sprites", 3, 2, [
        "wl_fish_koi", "wl_fish_small", "wl_fish_pair", "wl_fish_school", "wl_fish_slim", "wl_turtle"]),
    "wl_reeds_sheet.png": ("water/sprites", 3, 2, [
        "wl_reeds", "wl_stone_ring", "wl_iris", "wl_driftwood", "wl_pebbles", "wl_grass_teal"]),
    "uw_stones_sheet.png": ("water/sprites", 3, 2, [
        "uw_stone_big", "uw_stones_moss", "uw_slab_crystal", "uw_pebbles", "uw_log", "uw_stone_algae"]),
    "gr_mushrooms_sheet.png": ("water/sprites", 3, 2, [
        "gr_mush_violet", "gr_mush_cyan_trio", "gr_mush_pink", "gr_mush_white", "gr_mush_bell", "gr_mush_giant"]),
    "gr_stones_sheet.png": ("water/sprites", 3, 2, [
        "gr_boulder", "gr_trunk", "gr_root_arch", "gr_ferns", "gr_steps", "gr_branch"]),
    "fin_giants_sheet.png": ("water/sprites", 3, 2, [
        "fin_mush_giant", "fin_coral_violet", "fin_tubes_cyan", "fin_root_arch", "fin_mush_pink", "fin_sea_fan"]),
    "fin_small_sheet.png": ("water/sprites", 3, 2, [
        "fin_shell", "fin_anemones", "fin_mush_small", "fin_starfish", "fin_seaweed", "fin_crystals"]),
    "dw_puddles_sheet.png": ("water/sprites", 3, 2, [
        "dw_puddle_round", "dw_puddle_leaves", "dw_puddle_tiny", "dw_dew_moss", "dw_web", "dw_leaf_dew"]),
    "dw_flora_sheet.png": ("water/sprites", 3, 2, [
        "dw_mush_violet", "dw_mush_cyan", "dw_fern", "dw_clover", "dw_stone", "dw_bud"]),
    "slime_sheet.png": ("slime", 2, 2, ["idle", "blink", "squash", "stretch"]),
    "glade_sheet.png": ("decals", 3, 2, [
        "pond", "glow_cyan", "glow_violet", "mycelium_a", "mycelium_b", "spore_dots"]),
}

EDGE_LOW = 0.30   # magenta-ness below this is fully opaque
EDGE_HIGH = 0.85  # above this is fully transparent


def key_magenta(img):
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mag = (np.minimum(r, b) - g) / 255.0
    alpha = np.clip(1.0 - (mag - EDGE_LOW) / (EDGE_HIGH - EDGE_LOW), 0.0, 1.0)
    # despill: on partially transparent edge pixels pull red/blue toward green
    edge = alpha < 0.999
    cap = g + 36.0
    r = np.where(edge, np.minimum(r, cap), r)
    b = np.where(edge, np.minimum(b, np.maximum(cap, g + 70.0)), b)
    out = np.stack([r, g, b, alpha * 255.0], axis=-1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def components(alpha, scale=4, grow=1, min_area=20):
    """Label blobs of a dilated, downsampled alpha mask (no scipy). Returns label map at full size."""
    small = np.asarray(Image.fromarray(((alpha > 16) * 255).astype(np.uint8)).resize(
        (alpha.shape[1] // scale, alpha.shape[0] // scale), Image.BOX)) > 0
    grown = small.copy()
    for dy in range(-grow, grow + 1, 2):
        for dx in range(-grow, grow + 1, 2):
            grown |= np.roll(np.roll(small, dy, 0), dx, 1)
    h, w = grown.shape
    labels = np.zeros((h, w), np.int32)
    n = 0
    for y0 in range(h):
        for x0 in range(w):
            if grown[y0, x0] and not labels[y0, x0]:
                n += 1
                stack = [(y0, x0)]
                labels[y0, x0] = n
                while stack:
                    y, x = stack.pop()
                    for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                        if 0 <= yy < h and 0 <= xx < w and grown[yy, xx] and not labels[yy, xx]:
                            labels[yy, xx] = n
                            stack.append((yy, xx))
    keep = [i for i in range(1, n + 1) if (labels == i).sum() >= min_area]
    full = np.asarray(Image.fromarray(labels.astype(np.int32), "I").resize(
        (alpha.shape[1], alpha.shape[0]), Image.NEAREST))
    return full, keep


def crop_alpha(img, pad=4):
    a = np.asarray(img)[..., 3]
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        return img
    box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0),
           min(xs.max() + pad + 1, img.width), min(ys.max() + pad + 1, img.height))
    return img.crop(box)


def main():
    os.makedirs(PREVIEW, exist_ok=True)
    made = []
    for sheet, spec in SHEETS.items():
        group, cols, rows, names = spec[:4]
        grow = spec[4] if len(spec) > 4 else 1
        path = os.path.join(RAW, sheet)
        if not os.path.exists(path):
            print("skip (missing):", sheet)
            continue
        keyed = key_magenta(Image.open(path))
        os.makedirs(os.path.join(OUT, group), exist_ok=True)
        arr = np.asarray(keyed)
        full, keep = components(arr[..., 3], grow=grow)
        full = full.copy()
        info = []
        for lab in keep:
            ys, xs = np.where(full == lab)
            info.append((lab, xs.mean(), ys.mean()))
        # merge the smallest satellites (bubbles, stray pixels) into the nearest larger blob
        while len(info) > len(names):
            sizes = {t[0]: int((full == t[0]).sum()) for t in info}
            small = min(info, key=lambda t: sizes[t[0]])
            rest = [t for t in info if t is not small]
            near = min(rest, key=lambda t: (t[1] - small[1]) ** 2 + (t[2] - small[2]) ** 2)
            full[full == small[0]] = near[0]
            info = rest
        if len(info) != len(names):
            print("WARNING %s: found %d blobs, expected %d" % (sheet, len(info), len(names)))
        # order: row bands top-to-bottom, then left-to-right
        info.sort(key=lambda t: (int(t[2] // (keyed.height / rows)), t[1]))
        for (lab, _, _), name in zip(info, names):
            masked = arr.copy()
            masked[..., 3] = np.where(full == lab, masked[..., 3], 0)
            sprite = crop_alpha(Image.fromarray(masked))
            sprite.save(os.path.join(OUT, group, name + ".png"))
            made.append((name, sprite))
            print(name, sprite.size)
    # contact sheet on dark teal to expose halos
    if made:
        pad, per_row = 24, 6
        cell = 330
        rows_n = (len(made) + per_row - 1) // per_row
        sheet = Image.new("RGBA", (per_row * cell, rows_n * cell), (22, 30, 44, 255))
        for i, (name, spr) in enumerate(made):
            s = min((cell - pad) / spr.width, (cell - pad) / spr.height, 1.0)
            t = spr.resize((max(1, int(spr.width * s)), max(1, int(spr.height * s))), Image.LANCZOS)
            x = (i % per_row) * cell + (cell - t.width) // 2
            y = (i // per_row) * cell + (cell - t.height) // 2
            sheet.alpha_composite(t, (x, y))
        sheet.convert("RGB").save(os.path.join(PREVIEW, "cutout_contact_sheet.png"))


main()
