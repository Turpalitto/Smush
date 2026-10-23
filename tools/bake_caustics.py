#!/usr/bin/env python3
"""Bake a seamless caustics tile: the net of light that water throws on the ground.

The forest floor already has albedo, relief, occlusion and a moving canopy shadow.
All four describe the *ground*. What is missing is the thing under the ground: the
arena is an enchanted grove, and the light that reaches the moss has passed through
water on its way down. Caustics are not a texture you can invent convincingly with
noise — a caustic is a *fold in a light field*, and the filaments only appear where
the mapping from surface to floor actually folds over itself. So the tile is
rendered, not drawn:

* the water is a single grid spanning **3x3 tiles**, displaced by a height field
  built from integer-frequency plane waves. Integer frequencies are what make the
  tile periodic: h(x + 1) == h(x) exactly, so the surface above the centre tile is
  continuous with its neighbours by construction, not by fading.
* the 3x3 span matters because light is *refracted sideways*: rays reaching the
  centre tile come from the water outside it. Rendering a 1x1 surface would leave
  the border of the tile lit only by the water directly above it, and the tile
  would not repeat.
* the camera is orthographic, framing exactly the centre tile, so the crop is done
  by the camera and no pixels are wasted.
* the surface is a Principled BSDF with transmission 1.0 and IOR 1.333 (water),
  roughness 0. The floor is white diffuse. Cycles renders the transmission
  caustics; `caustics_refractive` is on and glossy blurring is off, because
  blurring a caustic is exactly the same as throwing away its filaments.
* the wave amplitude is not a magic number: the surface's curvature is measured
  and the amplitude is scaled so the refracted mapping folds by `--focus`. That is
  the one parameter that decides whether the net is visible at all — under 0.3 the
  tile is a flat wash, and at 1.0 the whole image collapses into bright points.

Output is normalised so the brightest texel is 1.0 — the shader multiplies it by a
small amount and adds it, so the absolute scale belongs to the shader, not the tile.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python tools/bake_caustics.py -- \
        resources/art/environment/forest_caustics.png \
        --res 512 --seed 7 --waves 24 --focus 0.62 --thickness 1.0 --samples 1024
"""

import argparse
import os
import sys
import time

import bpy
import numpy as np

TAU = 6.283185307179586
TILE = 1.0
SPAN = 3.0  # tiles of water, in each direction


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(description="Bake the caustics tile.")
    ap.add_argument("out", help="target PNG path")
    ap.add_argument("--res", type=int, default=512)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--waves", type=int, default=24)
    ap.add_argument("--kmax", type=int, default=16, help="highest wave number, cycles per tile")
    ap.add_argument("--falloff", type=float, default=0.5, help="amplitude exponent on |k|")
    ap.add_argument("--focus", type=float, default=0.62,
                    help="RMS of the fold term in the refracted Jacobian; 1.0 is a fold")
    ap.add_argument("--thickness", type=float, default=1.0, help="water depth, tile units")
    ap.add_argument("--grid", type=int, default=192, help="vertices per tile of water mesh")
    ap.add_argument("--margin", type=float, default=0.06,
                    help="extra frame rendered around the tile and cropped away")
    ap.add_argument("--gamma", type=float, default=1.0,
                    help="tone curve applied after normalisation, to lift the cells")
    ap.add_argument("--sun-angle", type=float, default=0.4, help="sun angular diameter, deg")
    ap.add_argument("--samples", type=int, default=512)
    ap.add_argument("--denoise", action="store_true",
                    help="run OIDN over the render (it smears caustic filaments)")
    ap.add_argument("--cpu", action="store_true")
    return ap.parse_args(argv)


def seam_report(plane: np.ndarray) -> dict:
    """Same measurement the floor, AO and canopy tiles are held to."""
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


def wave_field(args) -> tuple:
    """Periodic height field plus its analytic gradient.

    Every wave vector has integer components, so the field repeats exactly once per
    tile in x and in y. Amplitudes fall off as |k|^-`falloff`: the long swells bend
    the light, the short ones are what chop it into a net. A field made only of long
    swells is a handful of giant lenses — it throws a few bright dots and nothing
    that reads as caustics — so `kmax` has to be high enough for ten-odd cells
    across the tile.
    """
    rng = np.random.default_rng(args.seed)
    ks: list = []
    limit = max(2, args.kmax)
    while len(ks) < args.waves:
        kx, ky = rng.integers(-limit, limit + 1, 2)
        if kx == 0 and ky == 0:
            continue
        if (int(kx), int(ky)) in ks:
            continue
        ks.append((int(kx), int(ky)))

    ks = np.asarray(ks, dtype=np.float64)
    kmag = np.hypot(ks[:, 0], ks[:, 1])
    amps = kmag ** -args.falloff
    # Normalised by RMS, not by the sum: with a handful of discrete modes, dividing
    # by the sum lets the single longest wave carry two thirds of the amplitude and
    # the surface becomes a set of parallel ridges. That is what the first bake did,
    # and it printed straight bands instead of a net. Equal energy per mode, and a
    # gentle falloff, is what makes the field isotropic.
    amps /= np.sqrt(float((amps * amps).sum()))
    phases = rng.uniform(0.0, TAU, len(ks))

    def field(x, y):
        h = np.zeros_like(x)
        gx = np.zeros_like(x)
        gy = np.zeros_like(x)
        hxx = np.zeros_like(x)
        hxy = np.zeros_like(x)
        hyy = np.zeros_like(x)
        for (kx, ky), a, ph in zip(ks, amps, phases):
            arg = TAU * (kx * x + ky * y) + ph
            s = np.sin(arg)
            c = np.cos(arg)
            wkx = TAU * kx
            wky = TAU * ky
            h += a * s
            gx += a * wkx * c
            gy += a * wky * c
            # Second derivatives, so the calibration below can measure the fold
            # directly instead of guessing from the slope.
            hxx -= a * wkx * wkx * s
            hxy -= a * wkx * wky * s
            hyy -= a * wky * wky * s
        return h, gx, gy, hxx, hxy, hyy

    return field, ks, amps


def calibrate_amplitude(field, args) -> float:
    """Scale the field so the refracted mapping folds by the requested amount.

    A caustic is a fold in a light field, and the fold is set by the *curvature* of
    the water, not by its steepness: a ray is displaced by (1 - 1/n) * depth * slope,
    so the Jacobian of "where does this texel's light come from" is
    I + (1 - 1/n) * depth * Hessian(h). The image compresses to nothing where an
    eigenvalue of that matrix reaches -1.

    Calibrating on slope instead — which is what the first version did — gives a
    surface whose folds are eleven times over-driven: the whole tile collapses to a
    handful of firefly texels (measured: median texel 0.000, 0.7% of the tile lit)
    and the only thing that makes it look like a texture is the denoiser smearing
    the dots into streaks. Fixing the RMS of the Jacobian deviation instead makes
    the one parameter that matters portable across seeds and wave counts.
    """
    n = 256
    u = (np.arange(n) + 0.5) / n * TILE
    x, y = np.meshgrid(u, u, indexing="xy")
    _h, _gx, _gy, hxx, hxy, hyy = field(x, y)
    # Frobenius norm of the (symmetric) Hessian.
    frob = hxx * hxx + 2.0 * hxy * hxy + hyy * hyy
    rms_h = float(np.sqrt(np.mean(frob)))
    if rms_h <= 1e-9:
        raise SystemExit("caustics wave field has no curvature")
    bend = (1.0 - 1.0 / 1.333) * args.thickness
    return args.focus / (bend * rms_h)


def build_water(field, amp: float, args) -> object:
    """One grid over 3x3 tiles, displaced by the periodic field."""
    n = args.grid * int(SPAN)
    half = SPAN * 0.5
    u = np.linspace(-half, half, n + 1)
    x, y = np.meshgrid(u, u, indexing="xy")
    h, _gx, _gy, _hxx, _hxy, _hyy = field(x, y)
    z = args.thickness + amp * h

    co = np.stack([x.ravel(), y.ravel(), z.ravel()], axis=1).astype(np.float32)

    idx = np.arange(n * n, dtype=np.int32).reshape(n, n)
    quads = np.stack([
        idx[:-1, :-1].ravel(),
        idx[:-1, 1:].ravel(),
        idx[1:, 1:].ravel(),
        idx[1:, :-1].ravel(),
    ], axis=1).astype(np.int32)

    mesh = bpy.data.meshes.new("CausticWater")
    mesh.vertices.add(co.shape[0])
    mesh.vertices.foreach_set("co", co.ravel())
    mesh.loops.add(quads.size)
    mesh.loops.foreach_set("vertex_index", quads.ravel())
    mesh.polygons.add(quads.shape[0])
    mesh.polygons.foreach_set("loop_start", np.arange(0, quads.size, 4, dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.full(quads.shape[0], 4, dtype=np.int32))
    mesh.update(calc_edges=False)
    mesh.validate(verbose=False)
    # Smooth, not flat: the mesh spacing is about two texels, so flat shading would
    # print its own grid into the refraction as a checkerboard of facets.
    mesh.polygons.foreach_set("use_smooth", np.ones(quads.shape[0], dtype=bool))

    obj = bpy.data.objects.new("CausticWater", mesh)
    bpy.context.collection.objects.link(obj)

    mat = bpy.data.materials.new("CausticWaterMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.333
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mesh.materials.append(mat)
    print("CAUSTICS water %d verts, %d quads over %.0fx%.0f tiles"
          % (co.shape[0], quads.shape[0], SPAN, SPAN))
    return obj


def build_floor(args) -> object:
    """White diffuse plane at z=0. The bake target is the light that lands on it."""
    half = SPAN * 0.5
    co = np.array([[-half, -half, 0.0], [half, -half, 0.0],
                   [half, half, 0.0], [-half, half, 0.0]], dtype=np.float32)
    mesh = bpy.data.meshes.new("CausticFloor")
    mesh.vertices.add(4)
    mesh.vertices.foreach_set("co", co.ravel())
    mesh.loops.add(4)
    mesh.loops.foreach_set("vertex_index", np.array([0, 1, 2, 3], dtype=np.int32))
    mesh.polygons.add(1)
    mesh.polygons.foreach_set("loop_start", np.array([0], dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.array([4], dtype=np.int32))
    mesh.update(calc_edges=True)
    mesh.validate(verbose=False)

    mat = bpy.data.materials.new("CausticFloorMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
    bsdf.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mesh.materials.append(mat)

    obj = bpy.data.objects.new("CausticFloor", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def setup_scene(args) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = args.render_res
    scene.render.resolution_y = args.render_res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    # The bake is a light measurement, so it must not be tone-mapped on the way out.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0

    scene.cycles.samples = args.samples
    # Adaptive sampling is off: a caustic is almost entirely dark with a few very
    # bright texels, so a variance threshold stops the dark cells after two samples
    # and leaves the image patchy.
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.seed = 0
    # Sun -> water -> floor -> camera needs three; two spare for the folds that
    # bounce twice inside a filament.
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 1
    scene.cycles.transmission_bounces = 3
    scene.cycles.transparent_max_bounces = 4
    # Caustics are the subject, so nothing is allowed to blur or discard them.
    scene.cycles.caustics_refractive = True
    scene.cycles.caustics_reflective = False
    scene.cycles.blur_glossy = 0.0
    scene.cycles.use_denoising = bool(args.denoise)
    scene.cycles.filter_width = 0.8

    world = bpy.data.worlds.new("CausticVoid")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world

    if args.cpu:
        scene.cycles.device = "CPU"
        print("CAUSTICS device=CPU")
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
        print("CAUSTICS device=METAL %s" % ", ".join(enabled))
    except Exception as exc:  # noqa: BLE001
        print("CAUSTICS device=CPU (metal unavailable: %s)" % exc)
        scene.cycles.device = "CPU"


def add_sun(args) -> None:
    light = bpy.data.lights.new("CausticSun", type="SUN")
    light.energy = 4.0
    light.angle = np.radians(args.sun_angle)
    obj = bpy.data.objects.new("CausticSun", light)
    bpy.context.collection.objects.link(obj)
    # Straight down. A tilted sun would shear the net in one direction, which reads
    # as a smear rather than as water.
    obj.rotation_euler = (0.0, 0.0, 0.0)


def add_camera(args) -> None:
    cam = bpy.data.cameras.new("CausticCam")
    cam.type = "ORTHO"
    # Framed slightly wider than the tile: the denoiser pads its own border, and any
    # artefact it leaves there would sit exactly on the wrap line of the texture.
    # Rendering the margin and cropping it off is what keeps the seam clean.
    cam.ortho_scale = TILE * float(args.render_res) / float(args.res)
    obj = bpy.data.objects.new("CausticCam", cam)
    obj.location = (0.0, 0.0, 6.0)
    bpy.context.collection.objects.link(obj)
    bpy.context.scene.camera = obj


def render(args, tmp_exr: str) -> np.ndarray:
    bpy.context.scene.render.filepath = tmp_exr
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print("CAUSTICS render %.1fs" % (time.time() - t0))

    img = bpy.data.images.load(tmp_exr)
    n = args.render_res
    buf = np.empty(n * n * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    # Read and written bottom-up, like every other bake in tools/, so the round trip
    # through Blender's pixel buffer needs no flip.
    rgb = buf.reshape(n, n, 4)[:, :, :3]
    bpy.data.images.remove(img)
    # Luminance, because the shader adds one channel and the light is white.
    lum = rgb.mean(axis=2)
    pad = args.pad
    return lum[pad:pad + args.res, pad:pad + args.res]


def main() -> None:
    args = parse_args()
    out_png = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    tmp_exr = out_png.replace(".png", "_render.exr")
    args.pad = max(4, int(round(args.res * args.margin)))
    args.render_res = args.res + 2 * args.pad

    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene(args)
    add_sun(args)
    add_camera(args)
    build_floor(args)

    field, ks, _amps = wave_field(args)
    amp = calibrate_amplitude(field, args)
    print("CAUSTICS %d waves, amplitude %.5f for fold %.3f"
          % (len(ks), amp, args.focus))
    build_water(field, amp, args)

    caustic = render(args, tmp_exr)
    if os.path.exists(tmp_exr):
        os.remove(tmp_exr)

    peak = float(caustic.max())
    if peak <= 1e-6:
        raise SystemExit("caustics render came back black")
    # Normalised by a high percentile, not by the maximum: a fold in a light field is
    # arbitrarily bright, and one texel can be fifty times the next. Dividing by that
    # single texel throws away the whole net, which is what the first bake did — the
    # tile came out at a mean of 0.004 with everything but two dots at black.
    ref = float(np.percentile(caustic, 99.7))
    if ref <= 1e-6:
        raise SystemExit("caustics render has no bright texels")
    caustic = np.clip(caustic / ref, 0.0, 1.0)
    if args.gamma != 1.0:
        # Lifting the dark cells is a display decision, not a physical one, so it is
        # a flag and it is printed: the numbers below describe the shipped tile.
        caustic = np.clip(caustic, 0.0, 1.0) ** args.gamma
        print("CAUSTICS gamma %.2f applied (display only)" % args.gamma)

    mean = float(caustic.mean())
    p02, p10, p50, p90, p99 = (float(v) for v in np.percentile(caustic, [2, 10, 50, 90, 99]))
    print("CAUSTICS map mean %.4f min %.4f max %.4f std %.4f"
          % (mean, float(caustic.min()), float(caustic.max()), float(caustic.std())))
    print("CAUSTICS percentiles p02 %.3f p10 %.3f p50 %.3f p90 %.3f p99 %.3f"
          % (p02, p10, p50, p90, p99))
    # A caustic net is sparse by definition: most of the floor is in a dark cell and
    # a few percent of it is a filament. If this fraction is large, the "caustics"
    # are a noise texture and the bake did not converge.
    print("CAUSTICS bright fraction %.4f (texels above 0.5)" % float((caustic > 0.5).mean()))

    seam = seam_report(caustic)
    print("CAUSTICS seam h %.4f v %.4f  interior mean %.4f p99 %.4f  ratio %.2f"
          % (seam["seam_h"], seam["seam_v"], seam["interior_mean"], seam["interior_p99"],
             seam["ratio"]))

    target = bpy.data.images.new("CausticOut", args.res, args.res, alpha=False,
                                 float_buffer=True)
    target.colorspace_settings.name = "Non-Color"
    rgba = np.empty((args.res * args.res * 4,), dtype=np.float32)
    rgba[0::4] = caustic.ravel()
    rgba[1::4] = caustic.ravel()
    rgba[2::4] = caustic.ravel()
    rgba[3::4] = 1.0
    target.pixels.foreach_set(rgba)
    target.filepath_raw = out_png
    target.file_format = "PNG"
    target.save()
    print("CAUSTICS wrote %s" % out_png)
    print("CAUSTICS mean for the shader: %.4f" % mean)

    if seam["ratio"] >= 1.0:
        raise SystemExit("caustics tile is not seamless (ratio %.2f)" % seam["ratio"])


main()
