#!/usr/bin/env python3
"""Generate the lake's water sounds: audio/sfx/water/*.wav (22050 Hz, mono, 16-bit PCM like the rest of audio/sfx).

Everything is synthesised (no samples, nothing to license): short one-shots (drips, soft plips, bubbles, two
splashes, dive and resurface whooshes) and three seamless loops (surface lapping, underwater drone, a soft
glide swish whose volume the lab drives from the slime's speed). Levels are conservative: the lake is a
relaxing place, so nothing here is louder than the existing absorb chimes.

Usage: python3 tools/generate_water_sfx.py
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "sfx", "water")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(20261104)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff in Hz, scalar or per-sample array."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env_exp(t, decay, attack=0.004):
    e = np.exp(-t / decay)
    a = np.clip(t / attack, 0.0, 1.0)
    return e * a


def normalise(x, peak=0.6):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def save(name, x):
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, round(len(x) / SR, 2), "s")


def drip(f0, f1, dur=0.38, decay=0.09):
    t = t_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) * env_exp(t, decay)
    click = highpass(rng.standard_normal(len(t)), 2500) * env_exp(t, 0.006) * 0.25
    return normalise(tone * 0.8 + click, 0.5)


for i, (a, b) in enumerate([(1500, 760), (1250, 640), (1750, 880)], 1):
    save("water_drip_%02d" % i, drip(a, b))


def plip(f0, dur=0.2):
    t = t_axis(dur)
    f = f0 * (1.0 + 0.5 * np.exp(-t / 0.03))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return normalise(np.sin(ph) * env_exp(t, 0.045, 0.003), 0.35)


for i, f in enumerate([880, 1040, 1240], 1):
    save("water_plip_%02d" % i, plip(f))


def bubble(f0, dur=0.22):
    t = t_axis(dur)
    f = f0 * (1.0 + 1.1 * (t / dur))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return normalise(np.sin(ph) * env_exp(t, 0.05, 0.006) * (0.7 + 0.3 * np.sin(2 * np.pi * 38 * t)), 0.4)


for i, f in enumerate([520, 640, 760], 1):
    save("water_bubble_%02d" % i, bubble(f))


def splash(dur, low_hz, body):
    t = t_axis(dur)
    noise = rng.standard_normal(len(t))
    cutoff = 5200 * np.exp(-t / (dur * 0.35)) + 500
    band = lowpass(highpass(noise, 300), cutoff) * env_exp(t, dur * 0.28, 0.006)
    thump = np.sin(2 * np.pi * low_hz * (1.0 + 0.6 * np.exp(-t / 0.06)) * t) * env_exp(t, 0.12) * body
    drops = np.zeros(len(t))
    for _ in range(int(6 + dur * 8)):
        s = int(rng.uniform(0.04, dur * 0.8) * SR)
        n = int(0.09 * SR)
        tt = np.arange(n) / SR
        f0 = rng.uniform(900, 2000)
        drops[s:s + n] += np.sin(2 * np.pi * f0 * (1 + 0.5 * np.exp(-tt / 0.03)) * tt)[:len(drops[s:s + n])] * np.exp(-tt / 0.025)[:len(drops[s:s + n])] * 0.12
    return normalise(band * 0.9 + thump + drops, 0.55)


save("water_splash_small", splash(0.55, 190, 0.35))
save("water_splash_large", splash(1.0, 120, 0.55))


def whoosh(dur, down=True):
    t = t_axis(dur)
    noise = rng.standard_normal(len(t))
    s = t / dur
    cutoff = (4200 * (1 - s) + 260) if down else (260 + 4200 * s)
    sweep = lowpass(highpass(noise, 120), cutoff)
    env = np.sin(np.pi * np.clip(s, 0, 1)) ** 1.5
    tone_f = (420 * (1 - s) + 110) if down else (110 + 420 * s)
    tone = np.sin(2 * np.pi * np.cumsum(tone_f) / SR) * 0.35
    bubbles = np.zeros(len(t))
    for _ in range(14):
        st = int(rng.uniform(0.15, dur * 0.95) * SR)
        n = int(0.18 * SR)
        b = bubble(rng.uniform(420, 900), 0.18)
        end = min(st + n, len(bubbles))
        bubbles[st:end] += b[:end - st] * 0.4
    return normalise((sweep * 0.8 + tone) * env + bubbles, 0.55)


save("water_dive", whoosh(1.9, True))
save("water_surface", whoosh(1.5, False))


def loop_fix(x, fade):
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:].copy()
    w = np.linspace(0, 1, n)
    y = x[:-n].copy()
    y[:n] = head * w + tail * (1 - w)
    return y


# seamless loops
dur = 11.0
t = t_axis(dur + 1.0)
brown = lowpass(rng.standard_normal(len(t)), 420)
lap = brown * (0.55 + 0.45 * np.sin(2 * np.pi * 0.23 * t + 1.1) * np.sin(2 * np.pi * 0.11 * t))
sparkle = highpass(lowpass(rng.standard_normal(len(t)), 6500), 3200) * (np.sin(2 * np.pi * 0.37 * t) ** 8) * 0.25
amb_surface = normalise(lap + sparkle, 0.28)
save("ambience_surface", loop_fix(amb_surface, 1.0))

t = t_axis(dur + 1.0)
drone = lowpass(rng.standard_normal(len(t)), 160) * 1.2
pad = sum(np.sin(2 * np.pi * f * t + p) * (0.5 + 0.5 * np.sin(2 * np.pi * r * t + p)) * a
          for f, p, r, a in [(110, 0.3, 0.07, 0.25), (165, 1.2, 0.09, 0.18), (247, 2.1, 0.05, 0.12), (330, 0.7, 0.11, 0.08)])
amb_under = normalise(drone + pad, 0.3)
save("ambience_underwater", loop_fix(amb_under, 1.0))

dur = 3.0
t = t_axis(dur + 0.5)
glide = lowpass(highpass(rng.standard_normal(len(t)), 250), 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.9 * t))
save("water_glide", loop_fix(normalise(glide, 0.3), 0.4))
