#!/usr/bin/env python3
"""Synthesise the lake's zone music: audio/music/water/water_{glade,grove,lake,finale}.ogg (stereo, 64 s seamless loops).

The shipped soundtrack (theme_run, theme_zen, ...) lives in A minor over Am - F - C - G; the lake keeps that harmony so a
zone change never clashes with what is already in the ear, but each zone gets its own colour:
  glade   dewy and small: celesta-like plucks, a faint pad, lots of air
  grove   warmer: a slow pad with low bass and sparse marimba-ish notes
  lake    moonlit and wide: shimmering high pad, glassy bells, slow arpeggios
  finale  luminous reward: a rich choir-like pad, a rising bell motif, almost no bass
Seamless by construction: every note tail and the reverb (circular FFT convolution) wrap around the buffer, so there is no seam
to hide. Everything is synthesised from sines and shaped noise: no samples, nothing to license.

Usage: python3 tools/generate_water_music.py [OUT_DIR]
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
LOOP = 64.0
N = int(SR * LOOP)
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "music", "water")
os.makedirs(OUT, exist_ok=True)

CHORDS = [  # (root midi, chord tones relative to root)
    (57, [0, 3, 7, 12]),   # Am
    (53, [0, 4, 7, 12]),   # F
    (48, [0, 4, 7, 12]),   # C
    (55, [0, 4, 7, 12]),   # G
]
PENTA = [0, 3, 5, 7, 10]  # A minor pentatonic degrees


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def add(buf, start, sig):
    """Add a signal at `start` samples, wrapping past the end so tails continue into the head of the loop."""
    n = len(sig)
    i = int(start) % N
    end = i + n
    if end <= N:
        buf[i:end] += sig
    else:
        k = N - i
        buf[i:] += sig[:k]
        buf[:end - N] += sig[k:]


def tone(f, dur, attack, decay_tau, harmonics, detune=0.0, vib=0.0, rng=None):
    t = np.arange(int(SR * dur)) / SR
    env = np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay_tau)
    sig = np.zeros_like(t)
    for h, a in harmonics:
        ph = 2 * np.pi * (f * h * (1.0 + detune) * t + (vib * np.sin(2 * np.pi * 5.0 * t) if vib else 0.0))
        sig += a * np.sin(ph + (rng.random() * 6.28 if rng is not None else 0.0))
    return sig * env


def reverb(x, seconds, wet, rng, damp=3500.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / (seconds / 4.5))
    # darken the tail
    spec = np.fft.rfft(ir)
    fr = np.fft.rfftfreq(n, 1 / SR)
    ir = np.fft.irfft(spec / (1.0 + (fr / damp) ** 2), n)
    ir /= np.sqrt(np.sum(ir ** 2))
    X = np.fft.rfft(x)
    H = np.fft.rfft(ir, N)
    wetsig = np.fft.irfft(X * H, N)   # circular: the tail wraps, so the loop stays seamless
    return x * (1.0 - wet) + wetsig * wet


def make(track, seed):
    rng = np.random.default_rng(seed)
    cfg = {
        "glade":  dict(pad=0.12, bass=0.0,  pluck=0.55, pluck_oct=12, dens=0.55, bell=0.15, shimmer=0.05, rev=3.0, wet=0.42, bpm=52),
        "grove":  dict(pad=0.30, bass=0.28, pluck=0.35, pluck_oct=0,  dens=0.35, bell=0.10, shimmer=0.04, rev=3.8, wet=0.38, bpm=48),
        "lake":   dict(pad=0.26, bass=0.12, pluck=0.30, pluck_oct=12, dens=0.30, bell=0.34, shimmer=0.16, rev=5.0, wet=0.52, bpm=44),
        "finale": dict(pad=0.40, bass=0.0,  pluck=0.14, pluck_oct=24, dens=0.22, bell=0.45, shimmer=0.28, rev=6.0, wet=0.60, bpm=40),
    }[track]
    L = np.zeros(N)
    R = np.zeros(N)
    chord_len = LOOP / 8.0   # eight chords per loop: the four-chord cycle twice
    beat = 60.0 / cfg["bpm"]
    for ci in range(8):
        root, tones = CHORDS[ci % 4]
        t0 = ci * chord_len * SR
        # pad: a few detuned voices per chord tone, long attack and release overlapping the next chord
        for tn in tones[:3] + [tones[3] - 12]:
            for k, det in enumerate((-0.003, 0.0, 0.003)):
                sig = tone(hz(root + tn + (12 if track in ("lake", "finale") and tn >= 7 else 0)), chord_len + 3.0, 1.6, 6.0,
                           [(1, 1.0), (2, 0.25), (3, 0.08)], detune=det, vib=0.0, rng=rng)
                pan = 0.5 + (k - 1) * 0.3
                g = cfg["pad"] * 0.16
                add(L, t0, sig * g * (1.0 - pan))
                add(R, t0, sig * g * pan)
        # bass
        if cfg["bass"] > 0:
            b = tone(hz(root - 12), chord_len + 1.0, 0.3, 3.5, [(1, 1.0), (2, 0.35)])
            add(L, t0, b * cfg["bass"] * 0.28)
            add(R, t0, b * cfg["bass"] * 0.28)
        # plucks / bells on the pentatonic scale, sparse, panned
        steps = int(chord_len / beat)
        for s in range(steps):
            if rng.random() < cfg["dens"]:
                deg = int(rng.choice(PENTA)) + 57 + cfg["pluck_oct"] + (12 if rng.random() < 0.3 else 0)
                f = hz(deg)
                pl = tone(f, 3.2, 0.004, 0.55, [(1, 1.0), (2, 0.4), (3, 0.12), (5.4, 0.05)])
                pan = rng.random()
                st = t0 + s * beat * SR + rng.random() * 0.06 * SR
                add(L, st, pl * cfg["pluck"] * 0.22 * (1.0 - pan))
                add(R, st, pl * cfg["pluck"] * 0.22 * pan)
            if rng.random() < cfg["dens"] * 0.35 and cfg["bell"] > 0:
                deg = int(rng.choice(PENTA)) + 69 + (12 if track == "finale" else 0)
                bl = tone(hz(deg), 5.0, 0.003, 1.3, [(1, 1.0), (2.76, 0.35), (5.4, 0.18), (8.9, 0.07)])
                pan = rng.random()
                st = t0 + s * beat * SR
                add(L, st, bl * cfg["bell"] * 0.16 * (1.0 - pan))
                add(R, st, bl * cfg["bell"] * 0.16 * pan)
        # shimmer: very high airy sines drifting in and out
        if cfg["shimmer"] > 0 and ci % 2 == 0:
            for _ in range(3):
                deg = int(rng.choice(PENTA)) + 93
                sh = tone(hz(deg), chord_len * 1.4, 2.5, 4.0, [(1, 1.0)], vib=0.4)
                pan = rng.random()
                add(L, t0 + rng.random() * SR, sh * cfg["shimmer"] * 0.1 * (1.0 - pan))
                add(R, t0 + rng.random() * SR, sh * cfg["shimmer"] * 0.1 * pan)
    # the finale gets a slow rising bell motif once per chord cycle
    if track == "finale":
        for cyc in range(2):
            for j, d in enumerate([0, 7, 12, 15, 19]):
                st = (cyc * 32.0 + 6.0 + j * 1.4) * SR
                bl = tone(hz(81 + d), 5.0, 0.004, 1.5, [(1, 1.0), (2.76, 0.3), (5.4, 0.15)])
                add(L, st, bl * 0.07)
                add(R, st, bl * 0.07)
    L = reverb(L, cfg["rev"], cfg["wet"], np.random.default_rng(seed + 1))
    R = reverb(R, cfg["rev"], cfg["wet"], np.random.default_rng(seed + 2))
    out = np.stack([L, R], axis=1)
    # master: gentle level (the soundtrack sits a little louder than this), peak below -3 dBFS
    rms = np.sqrt(np.mean(out ** 2))
    out *= (0.075 / max(rms, 1e-9))
    peak = np.max(np.abs(out))
    if peak > 0.7:
        out *= 0.7 / peak
    return out


def save_ogg(name, stereo):
    data = (np.clip(stereo, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(data.tobytes())
        dst = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
    print(name, round(os.path.getsize(dst) / 1024), "KB")


for i, tr in enumerate(["glade", "grove", "lake", "finale"]):
    save_ogg("water_" + tr, make(tr, 20261104 + i * 11))
