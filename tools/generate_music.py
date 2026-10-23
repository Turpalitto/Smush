#!/usr/bin/env python3
"""Compose the game's soundtrack as three seamless loops and encode them to OGG.

The previous "music" was a six-second placeholder loop, so this script writes real
tracks instead of samples: every note is synthesised here (no third-party audio),
which keeps the soundtrack licence-clean and reproducible.

Design notes that matter for the result:

* **Seamless by construction.** Each track is rendered into a buffer that is the loop
  length plus a tail; the tail is folded back onto the head before the final cut, so
  reverb and note decays that run past the loop point reappear at the start instead of
  being chopped. The loop then has no click and no gap.
* **Integer sample grid.** Tempos are chosen so that one beat is a whole number of
  samples (72 / 100 / 126 BPM at 44.1 kHz), which means bar lines never drift and the
  last bar ends exactly on the loop point.
* **No aliasing.** Pads and bells are additive sine stacks rather than naive saws, so
  nothing folds back into the audible band at this sample rate.
* **Headroom.** Tracks are normalised to -2.5 dBFS peak; the game's Master bus runs a
  hard limiter at -1.2 dBFS on top, so music never fights the SFX for the ceiling.
* **Loudness, not just peak.** The three tracks are mastered to the same integrated
  loudness (EBU R128), because a peak-normalised drum track reads several LU quieter
  than a pad at the same ceiling. The trim is measured on the *encoded* file and is
  capped so the true peak stays under the ceiling.

Usage:
    python3 tools/generate_music.py [OUT_DIR]
"""

from __future__ import annotations

import argparse
import math
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np

SR = 44100
TAIL_SEC = 5.0
TWO_PI = 2.0 * math.pi


# --------------------------------------------------------------------------- helpers


def hz(semitone: float) -> float:
    """Semitone offset from A4 (440 Hz)."""
    return 440.0 * (2.0 ** (semitone / 12.0))


def adsr(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """Amplitude envelope in samples, clamped so it always fits the note."""
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    r = max(1, int(release * SR))
    if a + d + r > n:
        scale = n / float(a + d + r)
        a, d, r = int(a * scale), int(d * scale), int(r * scale)
    s = max(0, n - a - d - r)
    env = np.concatenate([
        np.linspace(0.0, 1.0, a, endpoint=False),
        np.linspace(1.0, sustain, d, endpoint=False),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r),
    ])
    if env.size < n:
        env = np.pad(env, (0, n - env.size))
    return env[:n]


def pad_voice(n: int, freq: float, detune_cents: float = 7.0) -> np.ndarray:
    """Warm additive pad: three detuned stacks of the first five harmonics."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for offset, weight in ((-detune_cents, 0.5), (0.0, 1.0), (detune_cents, 0.5)):
        f = freq * (2.0 ** (offset / 1200.0))
        for h, amp in ((1, 1.0), (2, 0.34), (3, 0.18), (4, 0.09), (5, 0.05)):
            if f * h > 9000.0:
                continue
            out += weight * amp * np.sin(TWO_PI * f * h * t + h * 0.7)
    return out / 3.0


def bell_voice(n: int, freq: float, index: float = 2.2) -> np.ndarray:
    """FM bell/pluck with an exponential decay — used for melodies and arpeggios."""
    t = np.arange(n) / SR
    env = np.exp(-t * 4.2)
    mod = np.sin(TWO_PI * freq * 2.01 * t) * index * env
    return np.sin(TWO_PI * freq * t + mod) * env


def bass_voice(n: int, freq: float) -> np.ndarray:
    t = np.arange(n) / SR
    body = np.sin(TWO_PI * freq * t) + 0.35 * np.sin(TWO_PI * freq * 2.0 * t)
    return np.tanh(body * 1.25) * 0.8


def kick_voice(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    freq = 118.0 * np.exp(-t * 26.0) + 44.0
    env = np.exp(-t * 9.0)
    click = np.exp(-t * 220.0) * 0.35
    return np.sin(TWO_PI * np.cumsum(freq) / SR) * env + click * 0.5


def hat_voice(n: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    # one-pole high pass so only the crisp top remains
    hp = np.empty(n)
    prev_x = 0.0
    prev_y = 0.0
    for i in range(n):
        prev_y = 0.86 * (prev_y + noise[i] - prev_x)
        prev_x = noise[i]
        hp[i] = prev_y
    return hp * np.exp(-t * 46.0) * 0.5


def clap_voice(n: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    # cheap band emphasis around 1.6 kHz
    shaped = np.convolve(noise, np.array([0.5, -0.2, 0.35, -0.1, 0.25]), mode="same")
    env = np.exp(-t * 22.0) * (1.0 + 0.6 * np.exp(-t * 60.0))
    return shaped * env * 0.42


def tom_voice(n: int, freq: float) -> np.ndarray:
    t = np.arange(n) / SR
    f = freq * np.exp(-t * 3.4) + freq * 0.72
    return np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t * 7.5)


def stab_voice(n: int, freqs: list[float]) -> np.ndarray:
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for h in (1, 2, 3, 5, 7):
            if f * h > 8000.0:
                continue
            out += np.sin(TWO_PI * f * h * t) / (h ** 1.35)
    return out * np.exp(-t * 5.5)


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = math.exp(-TWO_PI * cutoff / SR)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y = (1.0 - a) * x[i] + a * y
        out[i] = y
    return out


def reverb(x: np.ndarray, wet: float = 0.26) -> np.ndarray:
    """Four feedback combs plus a short allpass — small, dark room."""
    out = np.zeros_like(x)
    for delay_ms, gain in ((37.0, 0.62), (53.0, 0.58), (71.0, 0.54), (89.0, 0.5)):
        d = int(SR * delay_ms / 1000.0)
        buf = np.zeros(len(x) + d)
        buf[: len(x)] = x
        y = np.zeros_like(buf)
        for i in range(d, len(buf)):
            y[i] = buf[i] + gain * y[i - d]
        out += y[: len(x)] * 0.25
    ap = int(SR * 0.011)
    y = out.copy()
    for i in range(ap, len(y)):
        y[i] = -0.5 * out[i] + out[i - ap] + 0.5 * y[i - ap]
    return x * (1.0 - wet) + y * wet


def compress_loop(x: np.ndarray, thresh_ratio: float = 1.55, ratio: float = 3.4,
                  attack: float = 0.004, release: float = 0.18) -> np.ndarray:
    """Feed-forward compressor run twice, so the envelope at the loop point matches.

    Percussion-heavy tracks have a crest factor that keeps them ~2 dB quieter than a
    sustained pad once peaks are aligned; this evens the three tracks out. Running the
    pass twice means the gain at sample 0 is the gain the loop actually ended on.
    """
    # Threshold is relative to this track's own RMS: an absolute value either does
    # nothing on a quiet pad or squashes a drum loop that was never normalised yet.
    rms = math.sqrt(float(np.mean(x ** 2)))
    thresh = max(1e-4, rms * thresh_ratio)
    a_att = math.exp(-1.0 / (attack * SR))
    a_rel = math.exp(-1.0 / (release * SR))
    env = 0.0
    out = np.empty_like(x)
    for _pass in range(2):
        for i in range(len(x)):
            level = abs(x[i])
            coeff = a_att if level > env else a_rel
            env = coeff * env + (1.0 - coeff) * level
            if env > thresh:
                over = env / thresh
                gain = over ** (1.0 / ratio - 1.0)
            else:
                gain = 1.0
            out[i] = x[i] * gain
    return out


def tilt_eq(x: np.ndarray) -> np.ndarray:
    """Three-band tilt: pull the sub/bass down, push the mids and air up.

    The raw mix measured 63-84% of its energy below 250 Hz and under 3% in the 800 Hz-2 kHz
    band, which reads as muffled rumble rather than music. Splitting into bass / mid / air
    with two one-pole splits and re-weighting fixes the balance without a filter design.
    """
    # Phone speakers cannot reproduce anything under ~100 Hz, so low rumble only eats
    # headroom. High-pass at 70 Hz, then tilt: -6 dB bass, +5 dB mid, +4 dB air.
    hp = x - lowpass(x, 70.0)
    bass = lowpass(hp, 180.0)
    rest = hp - bass
    mid = lowpass(rest, 4200.0)
    air = rest - mid
    return bass * 0.50 + mid * 1.90 + air * 1.60


def soft_clip(x: np.ndarray, knee: float = 0.30) -> np.ndarray:
    """Bus soft-clipper: everything above `knee` is bent toward 1.0 instead of chopped.

    Kick and tom transients decide the peak, and a peak-limited mix ends up 4 dB quieter
    than a pad at the same ceiling. Bending the top few dB buys back that loudness and
    adds punch, without the hard edges of a real clipper.
    """
    a = np.abs(x)
    out = x.copy()
    over = a > knee
    out[over] = np.sign(x[over]) * (knee + (1.0 - knee) * np.tanh((a[over] - knee) / (1.0 - knee)))
    return out


class Loop:
    """Render buffer whose tail is folded back onto the head, so the loop is seamless."""

    def __init__(self, bars: int, bpm: float):
        self.samples_per_beat = int(round(SR * 60.0 / bpm))
        self.beat = self.samples_per_beat
        self.bar = self.samples_per_beat * 4
        self.length = self.bar * bars
        self.tail = int(SR * TAIL_SEC)
        self.left = np.zeros(self.length + self.tail)
        self.right = np.zeros(self.length + self.tail)

    def add(self, voice: np.ndarray, start_sample: int, gain: float, pan: float = 0.0) -> None:
        """pan in [-1, 1]; wraps past the loop point into the tail automatically."""
        n = len(voice)
        start = start_sample % self.length
        end = start + n
        if end > len(self.left):
            voice = voice[: len(self.left) - start]
            n = len(voice)
            end = start + n
        l = math.sqrt(0.5 * (1.0 - pan))
        r = math.sqrt(0.5 * (1.0 + pan))
        self.left[start:end] += voice * gain * l
        self.right[start:end] += voice * gain * r

    def finish(self, peak_db: float = -2.5, rms_db: float = -22.5) -> tuple[np.ndarray, np.ndarray]:
        left = reverb(self.left)
        right = reverb(self.right)
        # fold the decaying tail onto the head: this is what makes the loop gapless
        left[: self.tail] += left[self.length :]
        right[: self.tail] += right[self.length :]
        left = lowpass(left[: self.length], 15000.0)
        right = lowpass(right[: self.length], 15000.0)
        left = tilt_eq(left)
        right = tilt_eq(right)

        # Normalise to the ceiling first so the compressor's threshold means something,
        # then compress (channels linked so the stereo image never shifts), then match
        # loudness. Peak-aligning alone leaves a drum track ~2 dB quieter than a pad.
        peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
        ceiling = 10.0 ** (peak_db / 20.0)
        if peak > 0:
            left *= ceiling / peak
            right *= ceiling / peak

        peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
        if peak > 0:
            left /= peak
            right /= peak
        left = soft_clip(left)
        right = soft_clip(right)

        mono_env = (left + right) * 0.5
        compressed = compress_loop(mono_env)
        gain = np.divide(compressed, mono_env, out=np.ones_like(mono_env), where=np.abs(mono_env) > 1e-6)
        left *= gain
        right *= gain

        rms = math.sqrt(float(np.mean(left ** 2 + right ** 2) / 2.0))
        if rms > 1e-9:
            rms_gain = (10.0 ** (rms_db / 20.0)) / rms
            left *= rms_gain
            right *= rms_gain
        peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
        if peak > ceiling:
            left *= ceiling / peak
            right *= ceiling / peak
        return left, right


# ------------------------------------------------------------------------ the tracks


def track_menu() -> tuple[np.ndarray, np.ndarray]:
    """Calm, slightly mysterious: slow pad, soft bass, sparse bell. 8 bars @ 72 BPM."""
    rng = np.random.default_rng(7)
    loop = Loop(bars=8, bpm=72)
    bar = loop.bar

    # Am - F - C - G, two bars each. Roots are semitones from A4.
    chords = [
        (-12, [-12, 0, 3, 7]),
        (-16, [-16, -4, 0, 3]),
        (-9, [-9, 3, 7, 10]),
        (-14, [-14, 0, 3, 5]),
    ]
    for i, (root, notes) in enumerate(chords):
        start = i * 2 * bar
        dur = int(2.0 * bar * 0.98)
        for k, semi in enumerate(notes):
            v = pad_voice(dur, hz(semi))
            env = adsr(dur, 0.85, 0.4, 0.72, 1.4)
            loop.add(v * env, start, 0.16, pan=(-0.28 if k % 2 else 0.28))
        b = bass_voice(dur, hz(root - 12))
        loop.add(b * adsr(dur, 0.25, 0.3, 0.65, 1.0), start, 0.15)

    # Bell melody, A minor pentatonic, one phrase per two bars.
    melody = [12, 15, 19, 17, 15, 12, 10, 12]
    for i, semi in enumerate(melody):
        start = int((i * 1.0 + 0.35) * bar)
        v = bell_voice(int(1.6 * bar), hz(semi), index=1.7)
        loop.add(v * adsr(len(v), 0.01, 0.2, 0.35, 0.6), start, 0.30, pan=0.18)

    # A heartbeat every second bar keeps time without turning into a drum loop.
    for b in range(0, 8, 2):
        loop.add(kick_voice(int(0.28 * SR)) * adsr(int(0.28 * SR), 0.004, 0.05, 0.5, 0.1), b * bar, 0.3)

    return loop.finish(-2.5, -22.5)


def track_run() -> tuple[np.ndarray, np.ndarray]:
    """Driving exploration loop: 16 bars @ 100 BPM, kick/hat/clap, arpeggio, bass pulse."""
    rng = np.random.default_rng(11)
    loop = Loop(bars=16, bpm=100)
    beat, bar = loop.beat, loop.bar

    # Am - F - C - G, four bars each, twice.
    progression = [
        (-12, [-12, 0, 3, 7]),
        (-16, [-16, -4, 0, 3]),
        (-9, [-9, 3, 7, 10]),
        (-14, [-14, 0, 3, 5]),
    ]
    for rep in range(2):
        for ci, (root, notes) in enumerate(progression):
            start = (rep * 4 + ci) * bar
            dur = int(bar * 0.98)
            for k, semi in enumerate(notes[1:]):
                v = pad_voice(dur, hz(semi))
                loop.add(v * adsr(dur, 0.12, 0.2, 0.55, 0.35), start, 0.085, pan=(-0.35 if k % 2 else 0.35))
            # bass pulse on every 8th
            for e in range(8):
                s = start + e * (beat // 2)
                b = bass_voice(int(beat * 0.55), hz(root - 12))
                loop.add(b * adsr(len(b), 0.006, 0.08, 0.55, 0.08), s, 0.17)
            # arpeggio 16ths through the chord
            arp = [notes[1] + 12, notes[2] + 12, notes[3] + 12, notes[2] + 12]
            for e in range(16):
                s = start + e * (beat // 4)
                semi = arp[e % len(arp)]
                v = bell_voice(int(beat * 0.8), hz(semi), index=1.3)
                gain = 0.17 if rep == 0 else 0.21
                loop.add(v * adsr(len(v), 0.004, 0.06, 0.2, 0.1), s, gain, pan=0.3 if e % 2 else -0.3)

    for b in range(16):
        start = b * bar
        # kick on 1 and 3, extra push on the last beat of every second bar
        for e in (0, 2):
            loop.add(kick_voice(int(0.3 * SR)) * adsr(int(0.3 * SR), 0.003, 0.05, 0.4, 0.12), start + e * beat, 0.5)
        if b % 2 == 1:
            loop.add(kick_voice(int(0.3 * SR)) * adsr(int(0.3 * SR), 0.003, 0.04, 0.3, 0.1), start + int(3.5 * beat), 0.34)
        # clap on 2 and 4
        for e in (1, 3):
            loop.add(clap_voice(int(0.25 * SR), rng) * adsr(int(0.25 * SR), 0.002, 0.05, 0.3, 0.1), start + e * beat, 0.3, pan=0.05)
        # hats on 8ths, accents on the off-beat
        for e in range(8):
            acc = 0.26 if e % 2 else 0.15
            loop.add(hat_voice(int(0.09 * SR), rng) * adsr(int(0.09 * SR), 0.001, 0.02, 0.25, 0.03),
                     start + e * (beat // 2), acc, pan=0.22 if e % 2 else -0.22)

    return loop.finish(-2.5, -22.5)


def track_boss() -> tuple[np.ndarray, np.ndarray]:
    """Menacing boss loop: 16 bars @ 126 BPM, D harmonic minor, ostinato and toms."""
    rng = np.random.default_rng(23)
    loop = Loop(bars=16, bpm=126)
    beat, bar = loop.beat, loop.bar

    # D harmonic minor: D E F G A Bb C#. Drone on D with a tritone for dread.
    drone = [-17, -11, -5]  # D3, A3, E4 relative to A4
    for b in range(16):
        start = b * bar
        dur = int(bar * 0.98)
        for k, semi in enumerate(drone):
            v = pad_voice(dur, hz(semi), detune_cents=11.0)
            loop.add(v * adsr(dur, 0.1, 0.2, 0.6, 0.3), start, 0.10, pan=(-0.3 if k % 2 else 0.3))
        # tritone stab (D + Ab) on the second half of every other bar
        if b % 2 == 1:
            stab = stab_voice(int(beat * 0.9), [hz(-5), hz(0), hz(3)])
            loop.add(stab * adsr(len(stab), 0.004, 0.1, 0.2, 0.2), start + int(2.0 * beat), 0.26)

    # Ostinato bass in 16ths: D D D F | D D Ab D
    pattern = [-29, -29, -29, -24, -29, -29, -23, -29]
    for b in range(16):
        for e in range(16):
            semi = pattern[e % len(pattern)]
            s = b * bar + e * (beat // 4)
            v = bass_voice(int(beat * 0.42), hz(semi))
            gain = 0.15 if e % 4 == 0 else 0.095
            loop.add(v * adsr(len(v), 0.003, 0.05, 0.45, 0.06), s, gain)

    # Percussion: toms on the pulse, kick on 1 and 3, snare roll into the loop point.
    for b in range(16):
        start = b * bar
        loop.add(kick_voice(int(0.32 * SR)) * adsr(int(0.32 * SR), 0.002, 0.05, 0.4, 0.12), start, 0.55)
        loop.add(kick_voice(int(0.32 * SR)) * adsr(int(0.32 * SR), 0.002, 0.05, 0.4, 0.12), start + 2 * beat, 0.5)
        for e in (1, 3):
            loop.add(clap_voice(int(0.25 * SR), rng) * adsr(int(0.25 * SR), 0.002, 0.04, 0.3, 0.08),
                     start + e * beat, 0.34, pan=0.0)
        if b % 4 == 3:
            loop.add(tom_voice(int(0.5 * SR), 150.0) * adsr(int(0.5 * SR), 0.003, 0.08, 0.3, 0.2), start + 3 * beat, 0.35)
        for e in range(8):
            loop.add(hat_voice(int(0.08 * SR), rng) * adsr(int(0.08 * SR), 0.001, 0.015, 0.2, 0.03),
                     start + e * (beat // 2), 0.19, pan=0.2 if e % 2 else -0.2)

    # Snare roll over the last two bars, accelerating into the loop point.
    roll_start = 14 * bar
    pos = 0.0
    step = 0.5
    while pos < 2 * bar:
        s = roll_start + int(pos)
        if s < loop.length:
            loop.add(clap_voice(int(0.18 * SR), rng) * adsr(int(0.18 * SR), 0.002, 0.03, 0.2, 0.05), s, 0.16)
        step = max(0.125, step * 0.93)
        pos += beat * step

    return loop.finish(-2.5, -22.5)


# ---------------------------------------------------------------------------- output


def track_zen() -> tuple[np.ndarray, np.ndarray]:
    """Beatless contemplative bed for the zen mode: 8 bars @ 60 BPM (~32 s).

    No drums, no bass pulse, and no voice that lands on a beat. Everything is either
    a pad that is already sounding or a bell placed off the bar line, so the loop has
    no "one" for the ear to count from - which is what separates ambient from merely
    slow music.

    The harmony is Cmaj7 - Am7 - Fmaj7 - G6, two bars each. Every chord is a plain
    diatonic seventh with no leading tone, so any voice can be held indefinitely
    without needing to resolve. That is also why it sits under the run soundtrack's
    Am-F-C-G: it is the same key, so a crossfade between the two never clashes.
    """
    rng = np.random.default_rng(23)
    loop = Loop(bars=8, bpm=60)
    bar = loop.bar

    chords = [
        [-12, 0, 4, 7, 11],   # Cmaj7
        [-15, 0, 3, 7, 10],   # Am7
        [-17, -1, 4, 7, 9],   # Fmaj7
        [-14, 2, 7, 11, 14],  # G6
    ]
    for ci, notes in enumerate(chords):
        start = ci * 2 * bar
        # Longer than the chord's two bars on purpose: the pads overlap, so there is
        # never a moment where the bed is silent and the loop point could be heard.
        dur = int(bar * 2.35)
        for k, semi in enumerate(notes):
            v = pad_voice(dur, hz(semi), detune_cents=9.0)
            env = adsr(dur, 1.8, 0.9, 0.74, 2.4)
            loop.add(v * env, start, 0.060 + 0.010 * (k % 2), pan=(-0.45 + 0.22 * k))

    # Sparse bells, all pentatonic, deliberately off the bar line so nothing marks a
    # beat. Nine across 32 s is roughly one every 3.5 s - present, but never a melody
    # the player has to follow.
    pent = [0, 2, 4, 7, 9, 12, 14, 16, 19]
    for i in range(9):
        semi = pent[int(rng.integers(0, len(pent)))] + 12
        pos = int((i + float(rng.uniform(0.15, 0.85))) * (loop.length / 9.0))
        v = bell_voice(int(SR * 1.6), hz(semi), index=1.1)
        loop.add(v * adsr(len(v), 0.01, 0.30, 0.25, 1.10), pos, 0.075,
                 pan=float(rng.uniform(-0.6, 0.6)))

    # Forest leaves. The noise is generated at exactly one loop length and then
    # tiled, so the buffer is periodic and the loop point stays inaudible; a random
    # buffer cut to length would step at the seam. The breathing envelope uses an
    # integer number of cycles per loop for the same reason.
    n = loop.length + loop.tail
    for ch, seed_shift in (("left", 0), ("right", 977)):
        sub = np.random.default_rng(23 + seed_shift)
        base = lowpass(sub.standard_normal(loop.length), 2600.0)
        tiled = np.tile(base, 3)[:n]
        cycles = 3.0
        phase = np.arange(n, dtype=np.float64) / float(loop.length)
        breathe = 0.5 + 0.5 * np.sin(2.0 * math.pi * cycles * phase)
        shaped = tiled * breathe * 0.020
        if ch == "left":
            loop.left += shaped
        else:
            loop.right += shaped

    return loop.finish(-3.0, -24.0)


def write_wav(path: Path, left: np.ndarray, right: np.ndarray) -> None:
    import wave

    interleaved = np.empty(left.size * 2, dtype=np.int16)
    interleaved[0::2] = np.clip(left * 32767.0, -32768, 32767).astype(np.int16)
    interleaved[1::2] = np.clip(right * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(interleaved.tobytes())


def report(name: str, left: np.ndarray, right: np.ndarray) -> None:
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    rms = math.sqrt(float(np.mean(left ** 2 + right ** 2) / 2.0))
    # A loop is seamless when the step across the seam looks like any other sample
    # step in the track. Comparing it to the 99th percentile of |diff| catches a real
    # click instead of flagging the normal slope of a bass note.
    mono = (left + right) * 0.5
    diffs = np.abs(np.diff(mono))
    seam = abs(float(mono[0] - mono[-1]))
    typical = float(np.percentile(diffs, 99.0)) if diffs.size else 1.0
    flag = "OK " if seam <= typical * 1.5 else "CHECK"
    print(
        f"  [{flag}] {name:<14} {len(left) / SR:5.1f}s  peak {20 * math.log10(peak):6.2f} dBFS"
        f"  rms {20 * math.log10(rms):6.2f} dBFS  seam {seam:.4f} (p99 step {typical:.4f})"
    )


def decode_peak(ffmpeg: str, path: Path) -> float:
    """Peak of the *decoded* file, measured per channel.

    Vorbis is a lossy transform codec: the waveform it reconstructs is not the one it
    was given, and on dense material it can overshoot the float buffer slightly, so the
    decoded file is the only honest source. The decode is kept stereo on purpose —
    downmixing to mono sums the channels and reports a peak up to 3 dB too high.
    """
    out = subprocess.run(
        [ffmpeg, "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-"],
        check=True,
        capture_output=True,
    ).stdout
    samples = np.frombuffer(out, dtype="<f4")
    return float(np.max(np.abs(samples))) if samples.size else 0.0


def measure_loudness(ffmpeg: str, path: Path) -> tuple[float, float] | tuple[None, None]:
    """EBU R128 integrated loudness (LUFS) and true peak (dBTP) of the decoded file."""
    res = subprocess.run(
        [ffmpeg, "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
        check=True,
        capture_output=True,
        text=True,
    )
    loud = re.findall(r"I:\s*(-?\d+\.\d+) LUFS", res.stderr)
    peak = re.findall(r"Peak:\s*(-?\d+\.\d+) dBFS", res.stderr)
    if not loud or not peak:
        return None, None
    return float(loud[-1]), float(peak[-1])


def encode_ogg(
    ffmpeg: str,
    wav: Path,
    ogg: Path,
    target_lufs: float = -20.0,
    peak_ceiling_dbtp: float = -1.2,
) -> tuple[float, float]:
    """Encode, then trim to a common loudness without letting the true peak clip.

    Peak-normalising three different arrangements does not level-match them: a kick-heavy
    track ends up 2-3 LU below a pad at the same ceiling, so the boss theme would play
    quieter than the menu. Each encode is therefore measured with EBU R128 and re-encoded
    with a corrective gain, capped by the remaining headroom to the true-peak ceiling.
    """
    gain_db = 0.0
    lufs, peak = 0.0, 0.0
    for _attempt in range(3):
        cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", str(wav)]
        if abs(gain_db) > 1e-3:
            cmd += ["-af", f"volume={gain_db:.2f}dB"]
        cmd += ["-c:a", "libvorbis", "-q:a", "5", str(ogg)]
        subprocess.run(cmd, check=True)

        lufs_m, peak_m = measure_loudness(ffmpeg, ogg)
        if lufs_m is None or peak_m is None:
            break
        lufs, peak = lufs_m, peak_m

        trim = min(target_lufs - lufs, peak_ceiling_dbtp - peak)
        if abs(trim) < 0.3:
            break
        gain_db += trim
        print(f"  ! {lufs:+.1f} LUFS / {peak:+.1f} dBTP — re-encoding at {gain_db:+.2f} dB")
    return lufs, peak


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", nargs="?", default="audio/music")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    ffmpeg = shutil.which("ffmpeg") or "/Users/turpal/.local/bin/ffmpeg"
    if not Path(ffmpeg).exists():
        print("ffmpeg not found — writing WAV only")
        ffmpeg = ""

    # Per-track loudness targets. Zen sits 2.5 LU under the rest: it is a background
    # bed for a mode with no combat, and matching the run theme would make a
    # contemplative mode as loud as a fight.
    tracks = {
        "theme_menu": (track_menu, -20.0),
        "theme_run": (track_run, -20.0),
        "theme_boss": (track_boss, -20.0),
        "theme_zen": (track_zen, -22.5),
    }
    with tempfile.TemporaryDirectory() as tmp:
        for name, (fn, target_lufs) in tracks.items():
            left, right = fn()
            wav = Path(tmp) / f"{name}.wav"
            write_wav(wav, left, right)
            report(name, left, right)
            if ffmpeg:
                ogg = out_dir / f"{name}.ogg"
                lufs, dbtp = encode_ogg(ffmpeg, wav, ogg, target_lufs=target_lufs)
                print(f"  -> {ogg}  {ogg.stat().st_size // 1024} KB  "
                      f"{lufs:.1f} LUFS  true peak {dbtp:+.1f} dBTP")
            else:
                write_wav(out_dir / f"{name}.wav", left, right)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
