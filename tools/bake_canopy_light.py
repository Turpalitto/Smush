#!/usr/bin/env python3
"""Bake a seamless canopy-light tile: the sunlight that reaches the forest floor.

The floor already has relief and occlusion, but every square metre of it is lit the
same way. A forest floor is not: the light arrives in patches, in the shape of the
gaps between leaves, and those patches move when the canopy moves. That is the
single biggest thing missing from the arena's atmosphere, and it cannot be faked
with noise convincingly — the shapes have to come from real occlusion.

So Blender builds a canopy and Cycles casts the shadows:

* a 1x1 ground quad with UV 0..1 is the bake target;
* the canopy is ~14 clusters of tilted diamond leaves per tile, and the whole
  cluster field is instanced **nine times** over a 3x3 area. That is what makes the
  tile periodic: the centre sees its own wrap-around neighbours, so the shadow
  field repeats exactly instead of fading out at the border.
* the sun is a sun lamp at the same direction the floor shader lights the relief
  from (upper-left, ~45 deg). If the two disagreed, the bumps and the patches would
  cast light in different directions and the floor would read as a flat picture.
* the bake is a DIFFUSE pass with direct light only, on a white diffuse plane: the
  result is proportional to how much sun reaches each texel. Indirect is off, so
  the leaves cannot bounce light back and wash out the shadows.

Output is normalised so the brightest texel is 1.0; the shader divides by the
tile's mean, so the patches add contrast without changing the arena's brightness.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python tools/bake_canopy_light.py -- \
        resources/art/environment/forest_canopy_light.png \
        --res 1024 --seed 3 --clusters 14 --sun-angle 3.0 --samples 48 --cpu
"""

import argparse
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

TAU = 6.283185307179586


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(description="Bake the canopy dapple light tile.")
    ap.add_argument("out", help="target PNG path")
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--clusters", type=int, default=14, help="leaf clusters per tile")
    ap.add_argument("--leaves-min", type=int, default=14)
    ap.add_argument("--leaves-max", type=int, default=26)
    ap.add_argument("--cluster-radius", type=float, default=0.13, help="in tile units")
    ap.add_argument("--leaf-size", type=float, default=0.028, help="in tile units")
    ap.add_argument("--canopy-height", type=float, default=0.42, help="in tile units")
    ap.add_argument("--canopy-spread", type=float, default=0.22)
    ap.add_argument("--sun-angle", type=float, default=3.0, help="sun angular diameter, degrees")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--cpu", action="store_true")
    return ap.parse_args(argv)


def seam_report(plane: np.ndarray) -> dict:
    """Same measurement the floor and AO tiles are held to."""
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


def build_ground() -> object:
    """One unit quad at z=0 with UV 0..1 — the bake target."""
    mesh = bpy.data.meshes.new("CanopyGround")
    co = np.array([[-0.5, -0.5, 0.0], [0.5, -0.5, 0.0], [0.5, 0.5, 0.0], [-0.5, 0.5, 0.0]],
                  dtype=np.float32)
    mesh.vertices.add(4)
    mesh.vertices.foreach_set("co", co.ravel())
    mesh.loops.add(4)
    mesh.loops.foreach_set("vertex_index", np.array([0, 1, 2, 3], dtype=np.int32))
    mesh.polygons.add(1)
    mesh.polygons.foreach_set("loop_start", np.array([0], dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.array([4], dtype=np.int32))
    mesh.update(calc_edges=True)
    mesh.validate(verbose=False)

    uv_layer = mesh.uv_layers.new(name="UVMap")
    uv_layer.data.foreach_set(
        "uv", np.array([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], dtype=np.float32).ravel())

    obj = bpy.data.objects.new("CanopyGround", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_canopy(args) -> object:
    """Diamond leaves in clusters, instanced 9x so the shadow field is periodic."""
    rng = np.random.default_rng(args.seed)
    verts: list = []
    quads: list = []

    def leaf_geometry() -> np.ndarray:
        """One leaf, in its own local space. Drawn once and reused for every copy:
        the first version called this per instance, so all nine copies of a leaf got
        different sizes and rotations and the tile never actually repeated."""
        size = args.leaf_size * rng.uniform(0.7, 1.5)
        wide = size * rng.uniform(0.45, 0.75)
        local = np.array([[0.0, -size, 0.0], [wide, 0.0, 0.0], [0.0, size, 0.0], [-wide, 0.0, 0.0]])
        yaw = rng.uniform(0.0, TAU)
        tilt = rng.normal(0.0, 0.7)
        cy_, sy = np.cos(yaw), np.sin(yaw)
        ct, st = np.cos(tilt), np.sin(tilt)
        rot_yaw = np.array([[cy_, -sy, 0.0], [sy, cy_, 0.0], [0.0, 0.0, 1.0]])
        rot_tilt = np.array([[1.0, 0.0, 0.0], [0.0, ct, -st], [0.0, st, ct]])
        return local @ (rot_tilt @ rot_yaw).T

    # Leaves are authored inside the centre tile only, then duplicated over the
    # 3x3 neighbourhood. Any leaf that overhangs the tile edge therefore exists on
    # the far side too, which is exactly the periodicity the tile needs.
    leaves: list = []
    for _ in range(args.clusters):
        ccx, ccy = rng.uniform(-0.5, 0.5, 2)
        ccz = args.canopy_height + rng.normal(0.0, args.canopy_spread * 0.5)
        count = int(rng.integers(args.leaves_min, args.leaves_max + 1))
        for _i in range(count):
            ang = rng.uniform(0.0, TAU)
            rad = args.cluster_radius * rng.uniform(0.0, 1.0) ** 0.6
            leaves.append((
                float(ccx + np.cos(ang) * rad),
                float(ccy + np.sin(ang) * rad),
                float(ccz + rng.normal(0.0, 0.05)),
                leaf_geometry(),
            ))

    for ox in (-1.0, 0.0, 1.0):
        for oy in (-1.0, 0.0, 1.0):
            for lx, ly, lz, pts in leaves:
                base = len(verts)
                for p in pts:
                    verts.append((lx + ox + float(p[0]), ly + oy + float(p[1]), lz + float(p[2])))
                quads.append((base, base + 1, base + 2, base + 3))

    n_verts = len(verts)
    n_quads = len(quads)
    mesh = bpy.data.meshes.new("CanopyLeaves")
    mesh.vertices.add(n_verts)
    mesh.vertices.foreach_set("co", np.asarray(verts, dtype=np.float32).ravel())
    mesh.loops.add(n_quads * 4)
    mesh.loops.foreach_set("vertex_index", np.asarray(quads, dtype=np.int32).ravel())
    mesh.polygons.add(n_quads)
    mesh.polygons.foreach_set("loop_start", np.arange(0, n_quads * 4, 4, dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.full(n_quads, 4, dtype=np.int32))
    mesh.update(calc_edges=True)
    mesh.validate(verbose=False)

    obj = bpy.data.objects.new("CanopyLeaves", mesh)
    bpy.context.collection.objects.link(obj)
    print("CANOPY_LIGHT canopy %d leaves (%d clusters)" % (n_quads, args.clusters))
    return obj


def setup_scene(args) -> None:
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
    scene.cycles.max_bounces = 1
    scene.cycles.diffuse_bounces = 0

    bake = scene.render.bake
    bake.margin = 12
    bake.margin_type = "EXTEND"
    bake.use_clear = True
    bake.use_selected_to_active = False
    bake.use_pass_direct = True
    bake.use_pass_indirect = False
    bake.use_pass_color = True

    # Black world: the only light in the scene is the sun, so the baked value is
    # how much of that sun reaches each texel and nothing else.
    world = bpy.data.worlds.new("CanopyVoid")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world

    if args.cpu:
        scene.cycles.device = "CPU"
        print("CANOPY_LIGHT device=CPU")
        return
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        enabled = [d.name for d in prefs.devices if d.type == "METAL"]
        if not enabled:
            raise RuntimeError("no Metal device")
        for dev in prefs.devices:
            dev.use = dev.type == "METAL"
        scene.cycles.device = "GPU"
        print("CANOPY_LIGHT device=METAL %s" % ", ".join(enabled))
    except Exception as exc:  # noqa: BLE001
        print("CANOPY_LIGHT device=CPU (metal unavailable: %s)" % exc)
        scene.cycles.device = "CPU"


def add_sun(args) -> None:
    """Sun travelling along the same vector the floor shader lights relief from."""
    light = bpy.data.lights.new("CanopySun", type="SUN")
    light.energy = 1.0
    light.angle = np.radians(args.sun_angle)
    obj = bpy.data.objects.new("CanopySun", light)
    bpy.context.collection.objects.link(obj)
    # The shader's light points up-left and out of the screen: (-0.45, 0.55, 0.72).
    # Image +v maps to Blender +Y, so this is the same direction in world space.
    travel = Vector((0.45, -0.55, -0.72)).normalized()
    obj.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()


def bake_light(ground, args) -> np.ndarray:
    res = args.res
    target = bpy.data.images.new("CanopyLight", res, res, alpha=False, float_buffer=True)
    target.colorspace_settings.name = "Non-Color"

    mat = bpy.data.materials.new("CanopyGroundMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
    bsdf.location = (0, 0)
    bsdf.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (0, -260)
    tex.image = target
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    nt.nodes.active = tex

    ground.data.materials.clear()
    ground.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    ground.select_set(True)
    bpy.context.view_layer.objects.active = ground
    bpy.ops.object.bake(type="DIFFUSE")

    buf = np.empty(res * res * 4, dtype=np.float32)
    target.pixels.foreach_get(buf)
    img = buf.reshape(res, res, 4)[:, :, 0].copy()
    bpy.data.images.remove(target)
    return img


def main() -> None:
    args = parse_args()
    out_png = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_png), exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene(args)
    add_sun(args)
    ground = build_ground()
    build_canopy(args)

    t0 = time.time()
    light = bake_light(ground, args)
    print("CANOPY_LIGHT bake %.1fs" % (time.time() - t0))

    peak = float(light.max())
    if peak <= 1e-5:
        raise SystemExit("canopy light bake came back black")
    light = np.clip(light / peak, 0.0, 1.0)

    mean = float(light.mean())
    p02, p10, p50, p90, p98 = (float(v) for v in np.percentile(light, [2, 10, 50, 90, 98]))
    lit = float((light > 0.6).mean())
    print("CANOPY_LIGHT map mean %.4f min %.4f max %.4f std %.4f"
          % (mean, float(light.min()), float(light.max()), float(light.std())))
    print("CANOPY_LIGHT percentiles p02 %.3f p10 %.3f p50 %.3f p90 %.3f p98 %.3f"
          % (p02, p10, p50, p90, p98))
    print("CANOPY_LIGHT sunlit fraction %.3f (texels above 0.6)" % lit)

    seam = seam_report(light)
    print("CANOPY_LIGHT seam h %.4f v %.4f  interior mean %.4f p99 %.4f  ratio %.2f"
          % (seam["seam_h"], seam["seam_v"], seam["interior_mean"], seam["interior_p99"],
             seam["ratio"]))

    # Written before the seam check on purpose: when the tile does not repeat, the
    # first thing anyone wants is the image itself.
    target = bpy.data.images.new("CanopyLightOut", args.res, args.res, alpha=False,
                                 float_buffer=True)
    target.colorspace_settings.name = "Non-Color"
    rgba = np.empty((args.res * args.res * 4,), dtype=np.float32)
    rgba[0::4] = light.ravel()
    rgba[1::4] = light.ravel()
    rgba[2::4] = light.ravel()
    rgba[3::4] = 1.0
    target.pixels.foreach_set(rgba)
    target.filepath_raw = out_png
    target.file_format = "PNG"
    target.save()
    print("CANOPY_LIGHT wrote %s" % out_png)
    print("CANOPY_LIGHT mean for the shader: %.4f" % mean)

    if seam["ratio"] >= 1.0:
        raise SystemExit("canopy light tile is not seamless (ratio %.2f)" % seam["ratio"])


main()
