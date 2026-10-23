#!/usr/bin/env python3
"""Generate one bell per growth stage: audio/sfx/evo_01.wav .. evo_15.wav.

Why fifteen files and not one pitched up
----------------------------------------
The game used a single `evolution.wav` (a C major arpeggio) played at
`0.82 * 2^(semis/12)` with `semis = (stage-1) * 1.5`. That has two problems:

1. It only ever worked for the first half of the ladder. `play_sfx` clamps
   pitch_scale to 1.75, which is reached at stage 10, so stages 10-15 all played
   the *same* pitch while the code looked like it was rising. Nobody noticed
   because the clamp is silent.
2. Even unclamped, +21 semitones on a 5-note arpeggio puts the top notes at
   3-4 kHz. That is a squeal, not a reward, and the whole point of the growth
   ladder is that each stage feels like a gift.

So each stage gets its own bell. The pitch ladder is the C major pentatonic from
C3 to A5 - fifteen notes exactly - because the run soundtrack is Am-F-C-G, so a
C pentatonic bell is consonant over every bar of it. The timbre opens up as the
stage rises: more high partials, a longer tail, and detuned doubles that start
appearing at stage 6 (one) and stage 11 (two), which turns a single strike into
a small ensemble. Same instrument, bigger and brighter, like the slime.

Output format matches the rest of audio/sfx: 22050 Hz, mono, 16-bit PCM.
"""

from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "audio" / "sfx"
SR = 22050
TWO_PI = 2.0 * math.pi

# C major pentatonic, C3 -> A5. Fifteen notes for fifteen stages, and the note
# index is the stage index, so the ladder is audible as a rising line.
PENTATONIC = [
    130.81, 146.83, 164.81, 196.00, 220.00,
    261.63, 293.66, 329.63, 392.00, 440.00,
    523.25, 587.33, 659.25, 783.99, 880.00,
]

# Inharmonic partials of a struck metal bell. 2.4 and 3.9 are what make it read
# as metal instead of as an organ; a harmonic stack sounds like a synth pad.
PARTIALS = [1.0, 2.0, 2.4, 3.0, 3.9, 5.4]
BASE_AMPS = [1.00, 0.44, 0.26, 0.15, 0.08, 0.04]


def bell(f0: float, g: float, seed: int) -> np.ndarray:
    """One bell. `g` is 0..1 across the ladder: brightness and tail grow with it."""
    dur = 0.85 + 0.55 * g
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR

    # Tiny downward glide, the way a real bell settles after the strike.
    glide = 1.0 - 0.0018 * (t / dur)
    phase_t = np.cumsum(glide) / SR

    out = np.zeros(n, dtype=np.float64)
    for k, ratio in enumerate(PARTIALS):
        # Higher partials gain with the stage: the same bell, opened up.
        #
        # The ramp deliberately starts at k=2. Letting it touch k=1 (the octave)
        # made that partial as loud as the fundamental from stage 12 up, so the
        # bell was heard an octave above its note and the pentatonic line jumped
        # 525 -> 1175 between stages 11 and 12 instead of stepping. The octave
        # stays put; only the metal above it opens.
        open_up = min(1.0, max(0.0, (k - 1) / 2.0))
        amp = BASE_AMPS[k] * (1.0 + 0.95 * g * open_up)
        # ...and they die faster than the fundamental, as they do in metal.
        tau = 0.62 / (1.0 + 0.42 * k) * (0.85 + 0.75 * g)
        env = np.exp(-t / tau)
        out += amp * env * np.sin(TWO_PI * f0 * ratio * phase_t)

    # A soft body an octave down, only while the slime is still small: it gives
    # stages 1-5 weight so the early rewards are not thin.
    sub = max(0.0, 1.0 - g * 2.6) * 0.22
    if sub > 0.001:
        out += sub * np.exp(-t / (0.75 + 0.5 * g)) * np.sin(TWO_PI * f0 * 0.5 * phase_t)

    # Detuned doubles. Two is a shimmer; one is a slight thickening. They enter
    # gradually so the ladder never steps from "one bell" to "choir" in a jump.
    rng = np.random.default_rng(seed)
    for start_g, cents, amp in ((0.36, 6.0, 0.55), (0.70, -5.0, 0.45)):
        w = max(0.0, min(1.0, (g - start_g) / 0.25))
        if w <= 0.001:
            continue
        fd = f0 * (2.0 ** (cents / 1200.0))
        tau = 0.62 * (0.85 + 0.75 * g)
        out += (amp * w) * np.exp(-t / tau) * np.sin(TWO_PI * fd * phase_t + rng.uniform(0, TWO_PI))

    # 2 ms raised-cosine attack: no click, no perceived delay.
    a = max(2, int(0.002 * SR))
    out[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, a))

    # Fade the last 40 ms so the file does not end on a step.
    f = max(2, int(0.040 * SR))
    out[-f:] *= np.linspace(1.0, 0.0, f) ** 1.5

    return out


def loudness_match(x: np.ndarray) -> np.ndarray:
    """Same peak for every stage.

    Peak, not RMS: a long tail has less RMS than a short one, and matching RMS
    would make the later (longer) bells noticeably louder at the moment of the
    strike, which is the part the player hears.

    The target is the peak of the old shared bell (0.56), rounded to 0.58, so the
    new sound is not simply louder than the one it replaces. The sense of a bigger
    reward comes from the longer tail and the opened-up partials; a level jump on
    top of that would unbalance a mix that is already measured against the limiter.
    """
    peak = float(np.max(np.abs(x)))
    if peak <= 1e-9:
        return x
    return x * (0.58 / peak)


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    for i, f0 in enumerate(PENTATONIC):
        stage = i + 1
        g = i / 14.0
        x = loudness_match(bell(f0, g, seed=1000 + i))
        path = OUT_DIR / ("evo_%02d.wav" % stage)
        write_wav(path, x)
        size = path.stat().st_size
        total += size
        rms = float(np.sqrt(np.mean(x ** 2)))
        print(
            "stage %2d  f0=%6.2f Hz  %.2f s  peak=0.58  rms=%.3f  %5.1f KB"
            % (stage, f0, len(x) / SR, rms, size / 1024.0)
        )
    print("total %.2f MB in %s" % (total / (1024.0 * 1024.0), OUT_DIR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
