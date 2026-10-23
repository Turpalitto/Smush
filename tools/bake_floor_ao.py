#!/usr/bin/env python3
"""Bake a ray-traced ambient-occlusion map for the seamless forest floor tile.

`generate_floor_texture.py` produces three maps: albedo, height and normal. The
normal map gives the floor relief, but relief alone still looks like a picture of
a floor rather than a floor: nothing gets darker where moss cushions meet or
under a pebble. That occlusion needs actual rays, so this script hands the job to
Blender.

How the periodicity survives the round trip:

* the height field is turned into a mesh of **nine copies** of the tile in a 3x3
  grid, with vertex UVs extrapolated past 0..1 for the eight neighbours. The
  centre tile therefore sees its own wrap-around neighbours on every side, and
  rays that leave it land on real geometry instead of on empty space. Without
  this the border bakes bright and the repeated tile shows a glowing grid.
* the bake target keeps UV 0..1, so only the centre tile is written to the image.
* height sampling is bilinear with a modulo, so the geometry itself is continuous
  across the seams.

The occlusion is measured with the Cycles *Ambient Occlusion node* feeding an
emission shader and baking the EMIT pass, not with the built-in AO bake pass:
the node has an explicit Distance input, which is the only way to say "occlude
over roughly a fifth of a tile" instead of accepting whatever radius the pass
happens to use.

Output goes straight to `<out>` as a PNG. Blender's float buffer is written with
the image's Non-Color transform, i.e. the byte values *are* the AO values (checked
against the float buffer: max difference 1/255), so no re-encode step is needed.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python tools/bake_floor_ao.py -- \
        resources/art/environment/_source/forest_floor_height.png \
        resources/art/environment/forest_floor_ao.png \
        --res 1024 --grid 340 --depth 0.30 --distance 0.22 --samples 16 --cpu
"""

import argparse
import os
import sys
import time

import bpy
import numpy as np


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(description="Bake the forest floor AO map.")
    ap.add_argument("height", help="seamless height map produced by generate_floor_texture.py")
    ap.add_argument("out", help="target path; .npy is written next to the .png")
    ap.add_argument("--res", type=int, default=1024, help="bake resolution")
    ap.add_argument("--grid", type=int, default=340, help="mesh segments per tile side")
    ap.add_argument("--depth", type=float, default=0.30, help="relief height in tile units")
    ap.add_argument("--distance", type=float, default=0.22, help="AO ray distance in tile units")
    ap.add_argument("--samples", type=int, default=16, help="Cycles samples (anti-aliasing)")
    ap.add_argument("--ao-samples", type=int, default=24, help="rays per AO node evaluation")
    ap.add_argument("--cpu", action="store_true", help="force CPU instead of Metal")
    return ap.parse_args(argv)


def seam_report(plane: np.ndarray) -> dict:
    """Same measurement `generate_floor_texture.py` uses, so both maps are held
    to one standard: the step across the border versus the p99 interior step."""
    h_steps = np.abs(np.diff(plane, axis=1))
    v_steps = np.abs(np.diff(plane, axis=0))
    interior = np.concatenate([h_steps.ravel(), v_steps.ravel()])
    p99 = float(np.percentile(interior, 99.0))
    seam_h = float(np.abs(plane[:, 0] - plane[:, -1]).mean())
    seam_v = float(np.abs(plane[0, :] - plane[-1, :]).mean())
    return {
        "seam_h": seam_h,
        "seam_v": seam_v,
        "interior_mean": float(interior.mean()),
        "interior_p99": p99,
        "ratio": max(seam_h, seam_v) / max(1e-9, p99),
    }


def load_height(path: str) -> np.ndarray:
    """Read the height map as raw floats, bottom row first (Blender's order)."""
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    height = buf.reshape(h, w, 4)[:, :, 0].copy()
    bpy.data.images.remove(img)
    return height


def sample_wrapped(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Bilinear sample with a modulo, so the field is periodic in both axes."""
    h, w = tex.shape
    x = u * w - 0.5
    y = v * h - 0.5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = (x - x0).astype(np.float32)
    fy = (y - y0).astype(np.float32)
    x0m = x0 % w
    x1m = (x0 + 1) % w
    y0m = y0 % h
    y1m = (y0 + 1) % h
    top = tex[y0m, x0m] * (1.0 - fx) + tex[y0m, x1m] * fx
    bot = tex[y1m, x0m] * (1.0 - fx) + tex[y1m, x1m] * fx
    return (top * (1.0 - fy) + bot * fy).astype(np.float32)


def build_relief(height: np.ndarray, grid: int, depth: float):
    """Nine tiled copies of the height field as one mesh, centre tile on UV 0..1."""
    seg = 3 * grid
    n = seg + 1
    axis = np.linspace(-1.5, 1.5, n, dtype=np.float32)
    gx, gy = np.meshgrid(axis, axis, indexing="xy")

    uvx = gx.ravel() + 0.5
    uvy = gy.ravel() + 0.5
    z = sample_wrapped(height, uvx, uvy) * depth

    co = np.empty((n * n, 3), dtype=np.float32)
    co[:, 0] = gx.ravel()
    co[:, 1] = gy.ravel()
    co[:, 2] = z

    ids = np.arange(n * n, dtype=np.int32).reshape(n, n)
    a = ids[:-1, :-1].ravel()
    b = ids[:-1, 1:].ravel()
    c = ids[1:, 1:].ravel()
    d = ids[1:, :-1].ravel()
    quads = np.stack([a, b, c, d], axis=1).astype(np.int32)
    loops = quads.ravel()
    npoly = quads.shape[0]

    mesh = bpy.data.meshes.new("FloorRelief")
    mesh.vertices.add(n * n)
    mesh.vertices.foreach_set("co", co.ravel())
    mesh.loops.add(npoly * 4)
    mesh.loops.foreach_set("vertex_index", loops)
    mesh.polygons.add(npoly)
    mesh.polygons.foreach_set("loop_start", np.arange(0, npoly * 4, 4, dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.full(npoly, 4, dtype=np.int32))
    mesh.polygons.foreach_set("use_smooth", np.ones(npoly, dtype=bool))
    mesh.update(calc_edges=True)
    mesh.validate(verbose=False)

    uv_layer = mesh.uv_layers.new(name="UVMap")
    uvs = np.empty((npoly * 4, 2), dtype=np.float32)
    uvs[:, 0] = co[loops, 0] + 0.5
    uvs[:, 1] = co[loops, 1] + 0.5
    uv_layer.data.foreach_set("uv", uvs.ravel())

    obj = bpy.data.objects.new("FloorRelief", mesh)
    bpy.context.collection.objects.link(obj)
    return obj, npoly


def setup_cycles(args) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = args.res
    scene.render.resolution_y = args.res
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = False
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.seed = 0

    bake = scene.render.bake
    bake.margin = 12
    bake.margin_type = "EXTEND"
    bake.use_clear = True
    bake.use_selected_to_active = False

    if args.cpu:
        scene.cycles.device = "CPU"
        print("AO_BAKE device=CPU")
        return

    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        enabled = []
        for dev in prefs.devices:
            dev.use = dev.type == "METAL"
            if dev.use:
                enabled.append(dev.name)
        if not enabled:
            raise RuntimeError("no Metal device")
        scene.cycles.device = "GPU"
        print("AO_BAKE device=METAL %s" % ", ".join(enabled))
    except Exception as exc:  # noqa: BLE001 - any failure here just means CPU
        print("AO_BAKE device=CPU (metal unavailable: %s)" % exc)
        scene.cycles.device = "CPU"


def bake(obj, args) -> np.ndarray:
    res = args.res
    target = bpy.data.images.new("FloorAO", res, res, alpha=False, float_buffer=True)
    target.colorspace_settings.name = "Non-Color"

    mat = bpy.data.materials.new("FloorAO")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (420, 0)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (200, 0)
    emit.inputs["Strength"].default_value = 1.0
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.location = (-120, 0)
    ao.samples = args.ao_samples
    ao.only_local = False
    ao.inputs["Distance"].default_value = args.distance
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (200, -280)
    tex.image = target

    nt.links.new(ao.outputs["AO"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    nt.nodes.active = tex

    obj.data.materials.clear()
    obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.object.bake(type="EMIT")

    buf = np.empty(res * res * 4, dtype=np.float32)
    target.pixels.foreach_get(buf)
    ao_map = buf.reshape(res, res, 4)[:, :, 0].copy()
    bpy.data.images.remove(target)
    return ao_map


def main() -> None:
    args = parse_args()
    height_path = os.path.abspath(args.height)
    out_png = os.path.abspath(args.out)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    height = load_height(height_path)
    print("AO_BAKE height %dx%d mean %.4f" % (height.shape[1], height.shape[0], float(height.mean())))

    setup_cycles(args)
    t0 = time.time()
    obj, npoly = build_relief(height, args.grid, args.depth)
    print("AO_BAKE mesh %d faces (%.1fs)" % (npoly, time.time() - t0))

    t0 = time.time()
    ao_map = bake(obj, args)
    print("AO_BAKE bake %.1fs" % (time.time() - t0))

    lo = float(ao_map.min())
    hi = float(ao_map.max())
    mean = float(ao_map.mean())
    std = float(ao_map.std())
    p01, p10, p50, p90 = (float(v) for v in np.percentile(ao_map, [1, 10, 50, 90]))
    print("AO_BAKE map min %.4f max %.4f mean %.4f std %.4f" % (lo, hi, mean, std))
    print("AO_BAKE percentiles p01 %.4f p10 %.4f p50 %.4f p90 %.4f" % (p01, p10, p50, p90))

    seam = seam_report(ao_map)
    print(
        "AO_BAKE seam h %.4f v %.4f  interior mean %.4f p99 %.4f  ratio %.2f"
        % (seam["seam_h"], seam["seam_v"], seam["interior_mean"], seam["interior_p99"], seam["ratio"])
    )
    if seam["ratio"] >= 1.0:
        raise SystemExit("AO map is not seamless: border step is larger than the p99 interior step")

    target = bpy.data.images.new("FloorAOOut", args.res, args.res, alpha=False, float_buffer=True)
    target.colorspace_settings.name = "Non-Color"
    rgba = np.empty((args.res * args.res * 4,), dtype=np.float32)
    rgba[0::4] = ao_map.ravel()
    rgba[1::4] = ao_map.ravel()
    rgba[2::4] = ao_map.ravel()
    rgba[3::4] = 1.0
    target.pixels.foreach_set(rgba)
    target.filepath_raw = out_png
    target.file_format = "PNG"
    target.save()
    print("AO_BAKE wrote %s" % out_png)


main()
