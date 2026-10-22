#!/usr/bin/env python3
"""
Deterministic procedural asset & audio generator for SLIME RUSH: EVOLUTION.
Generates 100% original, royalty-free PNG artwork (icons, props, branding) and
16-bit PCM WAV sound effects + optional ambient music loop.
"""
from __future__ import annotations

import math
import os
import struct
import sys
import wave
from pathlib import Path

if "/tmp/pytools" not in sys.path and os.path.isdir("/tmp/pytools"):
    sys.path.insert(0, "/tmp/pytools")

from PIL import Image, ImageDraw, ImageFilter  # type: ignore

ROOT = Path(__file__).resolve().parent.parent


def ensure_dirs() -> None:
    for rel in [
        "resources/branding",
        "resources/icons/mutations",
        "resources/icons/synergies",
        "resources/icons/enemies",
        "resources/sprites",
        "audio/sfx",
        "audio/music",
    ]:
        (ROOT / rel).mkdir(parents=True, exist_ok=True)


def draw_slime_emblem(size: int, bg_mode: str = "full") -> Image.Image:
    """Renders the signature translucent glowing Slime Rush character emblem."""
    ss = size * 2  # 2x supersampling for crisp anti-aliasing
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if bg_mode in ("full", "background"):
        # Deep enchanted forest radial gradient
        bg = Image.new("RGBA", (ss, ss), (12, 24, 34, 255))
        bg_draw = ImageDraw.Draw(bg)
        cx, cy = ss // 2, int(ss * 0.54)
        for r in range(int(ss * 0.72), 10, -8):
            t = 1.0 - r / (ss * 0.72)
            col = (
                int(14 + 34 * t),
                int(28 + 86 * t),
                int(40 + 78 * t),
                255,
            )
            bg_draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
        # Subtle glowing forest spores in background
        for angle_deg, dist_f, rad_f, col in [
            (35, 0.34, 0.032, (110, 255, 200, 150)),
            (145, 0.36, 0.026, (130, 220, 255, 140)),
            (215, 0.33, 0.028, (255, 210, 110, 140)),
            (315, 0.35, 0.030, (190, 140, 255, 140)),
        ]:
            ang = math.radians(angle_deg)
            px = int(ss * 0.5 + math.cos(ang) * ss * dist_f)
            py = int(ss * 0.5 + math.sin(ang) * ss * dist_f)
            pr = max(3, int(ss * rad_f))
            bg_draw.ellipse((px - pr, py - pr, px + pr, py + pr), fill=col)
        if bg_mode == "background":
            return bg.resize((size, size), Image.Resampling.LANCZOS)
        img = Image.alpha_composite(img, bg)
        draw = ImageDraw.Draw(img)

    cx, cy = ss // 2, int(ss * 0.54)
    rx, ry = int(ss * 0.31), int(ss * 0.27)

    # Outer bioluminescent aura
    aura = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    ad = ImageDraw.Draw(aura)
    ad.ellipse(
        (cx - int(rx * 1.22), cy - int(ry * 1.22), cx + int(rx * 1.22), cy + int(ry * 1.18)),
        fill=(64, 245, 190, 95),
    )
    aura = aura.filter(ImageFilter.GaussianBlur(radius=max(4, ss // 28)))
    img = Image.alpha_composite(img, aura)
    draw = ImageDraw.Draw(img)

    # Little enchanted leaf sprout / mutation crest on top
    leaf_pts = [
        (cx, cy - ry - int(ss * 0.01)),
        (cx - int(ss * 0.07), cy - ry - int(ss * 0.09)),
        (cx + int(ss * 0.01), cy - ry - int(ss * 0.14)),
        (cx + int(ss * 0.08), cy - ry - int(ss * 0.07)),
    ]
    draw.polygon(leaf_pts, fill=(118, 255, 152, 240))

    # Main jelly body (layered dome)
    body_box = (cx - rx, cy - ry, cx + rx, cy + int(ry * 0.92))
    draw.ellipse(body_box, fill=(34, 208, 168, 235), outline=(165, 255, 232, 255), width=max(3, ss // 90))

    # Inner cytoplasm gradient layer
    inner_box = (
        cx - int(rx * 0.82),
        cy - int(ry * 0.78),
        cx + int(rx * 0.82),
        cy + int(ry * 0.74),
    )
    draw.ellipse(inner_box, fill=(68, 242, 198, 210))

    # Glowing golden-cyan nucleus core
    core_layer = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core_layer)
    cr = int(rx * 0.36)
    cd.ellipse((cx - cr, cy - int(cr * 0.7), cx + cr, cy + int(cr * 1.3)), fill=(255, 240, 128, 225))
    core_layer = core_layer.filter(ImageFilter.GaussianBlur(radius=max(2, ss // 64)))
    img = Image.alpha_composite(img, core_layer)
    draw = ImageDraw.Draw(img)
    cr_in = int(rx * 0.20)
    draw.ellipse(
        (cx - cr_in, cy - int(cr_in * 0.4), cx + cr_in, cy + int(cr_in * 1.6)),
        fill=(255, 252, 205, 245),
    )

    # Top glossy specular highlight
    hl_box = (
        cx - int(rx * 0.58),
        cy - int(ry * 0.76),
        cx - int(rx * 0.08),
        cy - int(ry * 0.36),
    )
    draw.ellipse(hl_box, fill=(235, 255, 250, 185))

    # Expressive cute eyes
    eye_dx = int(rx * 0.36)
    eye_y = cy - int(ry * 0.08)
    eye_r = int(rx * 0.16)
    for sign in (-1, 1):
        ex = cx + sign * eye_dx
        draw.ellipse((ex - eye_r, eye_y - eye_r, ex + eye_r, eye_y + eye_r), fill=(16, 30, 42, 255))
        shine_r = max(2, int(eye_r * 0.38))
        sx = ex - int(eye_r * 0.25)
        sy = eye_y - int(eye_r * 0.28)
        draw.ellipse((sx - shine_r, sy - shine_r, sx + shine_r, sy + shine_r), fill=(255, 255, 255, 255))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def generate_branding() -> None:
    draw_slime_emblem(512, "full").save(ROOT / "resources/branding/icon.png")
    draw_slime_emblem(432, "foreground").save(ROOT / "resources/branding/icon_foreground.png")
    draw_slime_emblem(432, "background").save(ROOT / "resources/branding/icon_background.png")

    # Vertical 720x1280 splash screen
    splash = Image.new("RGBA", (720, 1280), (11, 22, 30, 255))
    sd = ImageDraw.Draw(splash)
    for r in range(520, 20, -10):
        t = 1.0 - r / 520.0
        sd.ellipse(
            (360 - r, 580 - r, 360 + r, 580 + r),
            fill=(int(12 + 30 * t), int(26 + 78 * t), int(36 + 68 * t), 255),
        )
    emblem = draw_slime_emblem(300, "foreground")
    splash.alpha_composite(emblem, (210, 410))
    splash.save(ROOT / "resources/branding/splash.png")


def make_badge_icon(primary: tuple[int, int, int], accent: tuple[int, int, int], motif: str, size: int = 96) -> Image.Image:
    ss = size * 2
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 12
    d.rounded_rectangle(
        (pad, pad, ss - pad, ss - pad),
        radius=36,
        fill=(primary[0] // 4, primary[1] // 4, primary[2] // 4, 235),
        outline=(*primary, 245),
        width=6,
    )
    cx, cy = ss // 2, ss // 2

    if motif == "magnet":
        d.arc((cx - 46, cy - 46, cx + 46, cy + 46), 0, 180, fill=(*primary, 255), width=16)
        d.rectangle((cx - 46, cy - 28, cx - 30, cy + 2), fill=(*accent, 255))
        d.rectangle((cx + 30, cy - 28, cx + 46, cy + 2), fill=(255, 95, 110, 255))
    elif motif == "speed":
        for i, off in enumerate((-26, 0, 26)):
            w = 48 - i * 6
            d.polygon(
                [(cx + 42, cy + off), (cx - w, cy + off - 12), (cx - w + 14, cy + off), (cx - w, cy + off + 12)],
                fill=(*(accent if i == 1 else primary), 245),
            )
    elif motif == "spikes":
        for i in range(8):
            a = i * math.pi / 4.0
            a1, a2 = a - 0.22, a + 0.22
            d.polygon(
                [
                    (cx + math.cos(a) * 58, cy + math.sin(a) * 58),
                    (cx + math.cos(a1) * 26, cy + math.sin(a1) * 26),
                    (cx + math.cos(a2) * 26, cy + math.sin(a2) * 26),
                ],
                fill=(*primary, 250),
            )
        d.ellipse((cx - 24, cy - 24, cx + 24, cy + 24), fill=(*accent, 255))
    elif motif == "poison":
        for ox, oy, r in [(-22, 16, 22), (20, 20, 18), (0, -14, 28)]:
            d.ellipse((cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r), fill=(*primary, 230))
        d.ellipse((cx - 10, cy - 26, cx + 8, cy - 8), fill=(*accent, 245))
    elif motif == "split":
        for ox in (-24, 24):
            d.ellipse((cx + ox - 28, cy - 26, cx + ox + 28, cy + 26), fill=(*primary, 220), outline=(*accent, 255), width=4)
    elif motif == "shield":
        pts = [(cx, cy - 52), (cx + 44, cy - 30), (cx + 36, cy + 22), (cx, cy + 54), (cx - 36, cy + 22), (cx - 44, cy - 30)]
        d.polygon(pts, fill=(*primary, 185), outline=(*accent, 255))
    elif motif == "regen":
        d.rectangle((cx - 14, cy - 46, cx + 14, cy + 46), fill=(*primary, 250))
        d.rectangle((cx - 46, cy - 14, cx + 46, cy + 14), fill=(*primary, 250))
        d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(*accent, 255))
    elif motif == "dash":
        d.polygon([(cx + 54, cy), (cx - 18, cy - 38), (cx - 4, cy), (cx - 18, cy + 38)], fill=(*accent, 255))
        d.polygon([(cx + 12, cy), (cx - 50, cy - 26), (cx - 38, cy), (cx - 50, cy + 26)], fill=(*primary, 200))
    elif motif == "tendril":
        pts = [(cx - 48, cy + 36), (cx - 16, cy - 24), (cx + 18, cy + 16), (cx + 48, cy - 34)]
        d.line(pts, fill=(*primary, 255), width=14, joint="curve")
        d.ellipse((cx + 34, cy - 48, cx + 60, cy - 22), fill=(*accent, 255))
    elif motif == "electro":
        bolt = [(cx + 10, cy - 54), (cx - 28, cy + 2), (cx + 2, cy + 2), (cx - 14, cy + 54), (cx + 32, cy - 6), (cx + 2, cy - 6)]
        d.polygon(bolt, fill=(*accent, 255), outline=(*primary, 255))
    elif motif == "freeze":
        for i in range(6):
            a = i * math.pi / 3.0
            d.line((cx, cy, cx + math.cos(a) * 50, cy + math.sin(a) * 50), fill=(*accent, 255), width=8)
        d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(*primary, 255))
    elif motif == "mimicry":
        d.polygon([(cx, cy - 50), (cx + 42, cy), (cx, cy + 50), (cx - 42, cy)], fill=(*primary, 210), outline=(*accent, 255))
        d.line((cx, cy - 44, cx, cy + 44), fill=(*accent, 255), width=5)
    elif motif == "synergy":
        for i in range(12):
            a = i * math.pi / 6.0
            r = 54 if i % 2 == 0 else 26
            pts_star = []
        star = [
            (cx + math.cos(i * math.pi / 5.0 - math.pi / 2) * (54 if i % 2 == 0 else 24),
             cy + math.sin(i * math.pi / 5.0 - math.pi / 2) * (54 if i % 2 == 0 else 24))
            for i in range(10)
        ]
        d.polygon(star, fill=(*accent, 245), outline=(*primary, 255))
    else:
        # Creature silhouette badge
        d.ellipse((cx - 38, cy - 34, cx + 38, cy + 36), fill=(*primary, 240), outline=(*accent, 255), width=5)
        d.ellipse((cx - 18, cy - 10, cx - 6, cy + 2), fill=(255, 255, 255, 255))
        d.ellipse((cx + 6, cy - 10, cx + 18, cy + 2), fill=(255, 255, 255, 255))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def generate_icons_and_sprites() -> None:
    mutations = [
        ("magnet", (80, 210, 255), (255, 230, 120), "magnet"),
        ("speed_boost", (80, 245, 190), (220, 255, 245), "speed"),
        ("spikes", (235, 95, 125), (255, 215, 140), "spikes"),
        ("poison_trail", (135, 245, 75), (210, 120, 255), "poison"),
        ("split", (95, 225, 235), (255, 250, 175), "split"),
        ("shield", (95, 175, 255), (215, 245, 255), "shield"),
        ("regeneration", (85, 235, 130), (235, 255, 195), "regen"),
        ("dash", (255, 175, 75), (255, 245, 190), "dash"),
        ("ranged_absorb", (200, 115, 255), (120, 250, 220), "tendril"),
        ("electro_discharge", (95, 215, 255), (255, 238, 95), "electro"),
        ("freeze", (120, 220, 255), (235, 252, 255), "freeze"),
        ("mimicry", (95, 195, 125), (210, 255, 165), "mimicry"),
    ]
    for mid, c1, c2, motif in mutations:
        make_badge_icon(c1, c2, motif).save(ROOT / f"resources/icons/mutations/{mid}.png")

    synergies = [
        ("em_storm", (90, 200, 255), (255, 235, 95)),
        ("toxic_clones", (145, 245, 85), (210, 110, 255)),
        ("piercing_strike", (255, 120, 95), (255, 235, 165)),
        ("ice_armor", (110, 215, 255), (240, 252, 255)),
        ("bio_vampirism", (225, 80, 145), (110, 250, 175)),
    ]
    for sid, c1, c2 in synergies:
        make_badge_icon(c1, c2, "synergy").save(ROOT / f"resources/icons/synergies/{sid}.png")

    enemies = [
        ("tiny_mushroom", (240, 135, 165), (255, 235, 210)),
        ("forest_beetle", (115, 195, 95), (215, 245, 155)),
        ("firefly", (255, 230, 95), (150, 255, 220)),
        ("stone_slug", (145, 155, 170), (215, 225, 235)),
        ("poison_toad", (145, 215, 70), (195, 95, 235)),
        ("predator_flower", (225, 70, 110), (120, 230, 115)),
        ("electric_beetle", (75, 190, 255), (255, 235, 95)),
        ("shadow_slime", (115, 75, 185), (215, 140, 255)),
        ("umbral_alpha", (155, 60, 215), (255, 180, 110)),
        ("ancient_guardian", (80, 185, 120), (255, 215, 95)),
    ]
    for eid, c1, c2 in enemies:
        make_badge_icon(c1, c2, "creature").save(ROOT / f"resources/icons/enemies/{eid}.png")

    # Soft radial glow sprite (128x128)
    glow = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = glow.load()
    for y in range(128):
        for x in range(128):
            dx = (x - 63.5) / 63.5
            dy = (y - 63.5) / 63.5
            dist = math.sqrt(dx * dx + dy * dy)
            a = int(max(0.0, 1.0 - dist) ** 2.2 * 255)
            px[x, y] = (255, 255, 255, a)
    glow.save(ROOT / "resources/sprites/soft_glow.png")

    # Faceted essence crystal (64x64)
    gem = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gem)
    gd.polygon([(32, 4), (54, 24), (46, 58), (18, 58), (10, 24)], fill=(90, 245, 200, 240), outline=(225, 255, 245, 255))
    gd.polygon([(32, 10), (46, 26), (32, 50), (18, 26)], fill=(195, 255, 235, 210))
    gem.save(ROOT / "resources/sprites/essence_gem.png")


def write_wav(path: Path, samples: list[float], sample_rate: int = 22050) -> None:
    clamped = [max(-1.0, min(1.0, s)) for s in samples]
    pcm = struct.pack(f"<{len(clamped)}h", *(int(s * 32760) for s in clamped))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm)


def synth_sfx() -> None:
    sr = 22050

    # 1. move_pulse.wav — soft watery gel ripple
    dur = 0.14
    n = int(sr * dur)
    write_wav(
        ROOT / "audio/sfx/move_pulse.wav",
        [
            math.sin(2 * math.pi * (150 + 70 * math.sin(i / n * math.pi)) * (i / sr))
            * math.sin(i / n * math.pi)
            * 0.28
            for i in range(n)
        ],
        sr,
    )

    # 2. absorb.wav — juicy ascending pop-bloop
    dur = 0.22
    n = int(sr * dur)
    absorb = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = 240.0 + 520.0 * (t ** 1.5)
        phase += 2.0 * math.pi * freq / sr
        env = math.sin(t * math.pi) ** 0.65
        val = (0.72 * math.sin(phase) + 0.28 * math.sin(phase * 2.0)) * env * 0.55
        absorb.append(val)
    write_wav(ROOT / "audio/sfx/absorb.wav", absorb, sr)

    # 3. evolution.wav — magical forest chime arpeggio
    notes = [523.25, 659.25, 783.99, 1046.50, 1318.51]
    dur = 0.75
    n = int(sr * dur)
    evo = [0.0] * n
    for idx, f in enumerate(notes):
        start = int(idx * 0.10 * sr)
        for i in range(start, n):
            lt = (i - start) / sr
            env = math.exp(-lt * 4.5) * min(1.0, lt * 60.0)
            evo[i] += (math.sin(2 * math.pi * f * lt) + 0.35 * math.sin(4 * math.pi * f * lt)) * env * 0.26
    write_wav(ROOT / "audio/sfx/evolution.wav", evo, sr)

    # 4. mutation_pick.wav — warm crystalline power chord
    dur = 0.45
    n = int(sr * dur)
    mpick = []
    for i in range(n):
        lt = i / sr
        env = math.exp(-lt * 5.2) * min(1.0, lt * 80.0)
        s = (
            math.sin(2 * math.pi * 587.33 * lt)
            + 0.8 * math.sin(2 * math.pi * 880.0 * lt)
            + 0.6 * math.sin(2 * math.pi * 1174.66 * lt)
        )
        mpick.append(s * env * 0.24)
    write_wav(ROOT / "audio/sfx/mutation_pick.wav", mpick, sr)

    # 5. attack.wav — energetic dash / strike sweep
    dur = 0.20
    n = int(sr * dur)
    atk = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = 680.0 - 480.0 * t
        phase += 2 * math.pi * freq / sr
        noise = math.sin(i * 1.73) * math.cos(i * 0.91) * 0.25
        env = (1.0 - t) ** 1.4
        atk.append((math.sin(phase) * 0.65 + noise) * env * 0.5)
    write_wav(ROOT / "audio/sfx/attack.wav", atk, sr)

    # 6. hurt.wav — squishy impact thud
    dur = 0.24
    n = int(sr * dur)
    hurt = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = 190.0 - 115.0 * t
        phase += 2 * math.pi * freq / sr
        env = (1.0 - t) ** 1.6
        hurt.append((math.sin(phase) + 0.45 * math.sin(phase * 2.7)) * env * 0.52)
    write_wav(ROOT / "audio/sfx/hurt.wav", hurt, sr)

    # 7. victory.wav — triumphant enchanted fanfare
    v_notes = [(523.25, 0.0), (659.25, 0.14), (783.99, 0.28), (1046.5, 0.44)]
    dur = 1.25
    n = int(sr * dur)
    vic = [0.0] * n
    for f, st in v_notes:
        s_idx = int(st * sr)
        for i in range(s_idx, n):
            lt = (i - s_idx) / sr
            env = math.exp(-lt * 2.6) * min(1.0, lt * 50.0)
            vic[i] += (math.sin(2 * math.pi * f * lt) + 0.4 * math.sin(4 * math.pi * f * lt)) * env * 0.26
    write_wav(ROOT / "audio/sfx/victory.wav", vic, sr)

    # 8. defeat.wav — gentle descending forest sigh
    d_notes = [(440.0, 0.0), (392.0, 0.20), (349.23, 0.40), (293.66, 0.62)]
    dur = 1.20
    n = int(sr * dur)
    dft = [0.0] * n
    for f, st in d_notes:
        s_idx = int(st * sr)
        for i in range(s_idx, n):
            lt = (i - s_idx) / sr
            env = math.exp(-lt * 3.0) * min(1.0, lt * 40.0)
            dft[i] += math.sin(2 * math.pi * f * lt) * env * 0.30
    write_wav(ROOT / "audio/sfx/defeat.wav", dft, sr)

    # 9. button_click.wav — clean tactile UI tap
    dur = 0.07
    n = int(sr * dur)
    btn = [
        math.sin(2 * math.pi * (820.0 + 220.0 * (1.0 - i / n)) * (i / sr)) * ((1.0 - i / n) ** 2.2) * 0.42
        for i in range(n)
    ]
    write_wav(ROOT / "audio/sfx/button_click.wav", btn, sr)

    # 10. boss_warning.wav — deep ancient guardian horn
    dur = 0.95
    n = int(sr * dur)
    horn = []
    for i in range(n):
        lt = i / sr
        env = math.sin(min(1.0, i / n) * math.pi) ** 0.55
        s = (
            0.65 * math.sin(2 * math.pi * 110.0 * lt)
            + 0.35 * math.sin(2 * math.pi * 164.81 * lt)
            + 0.25 * math.sin(2 * math.pi * 220.0 * lt)
        )
        horn.append(s * env * 0.48)
    write_wav(ROOT / "audio/sfx/boss_warning.wav", horn, sr)

    # 11. shield_break.wav — glassy energy pop
    dur = 0.22
    n = int(sr * dur)
    shb = [
        (math.sin(2 * math.pi * 960.0 * (i / sr)) + 0.5 * math.sin(2 * math.pi * 1420.0 * (i / sr)))
        * math.exp(-(i / sr) * 14.0)
        * 0.42
        for i in range(n)
    ]
    write_wav(ROOT / "audio/sfx/shield_break.wav", shb, sr)

    # 12. ambient_forest.wav — gentle seamless 6-second warm pad (OFF by default per spec)
    dur = 6.0
    n = int(sr * dur)
    amb = []
    freqs = [220.0, 277.18, 329.63, 440.0]  # A major warm enchanted chord, integer cycles in 6s
    for i in range(n):
        lt = i / sr
        lfo = 0.82 + 0.18 * math.sin(2 * math.pi * lt / dur)
        s = sum(math.sin(2 * math.pi * f * lt) for f in freqs) / len(freqs)
        amb.append(s * lfo * 0.18)
    write_wav(ROOT / "audio/music/ambient_forest.wav", amb, sr)


def main() -> None:
    ensure_dirs()
    generate_branding()
    generate_icons_and_sprites()
    synth_sfx()
    print("Generated branding, 27 icons, 2 world sprites, 11 SFX WAVs, and 1 ambient WAV.")


if __name__ == "__main__":
    main()
