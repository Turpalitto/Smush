#!/usr/bin/env python3
"""Generate eight collection chimes: audio/sfx/orb_chime_01.wav .. orb_chime_08.wav.

Why eight files and not one pitched up
--------------------------------------
Same reason as the evolution bells: `AudioManager.play_sfx` clamps `pitch_scale` to
[0.55, 1.75], so a pitch-driven ladder stops being audible once it hits the clamp.
Eight separate notes also let each one keep a real attack transient and a real tail,
which a pitched sample loses.

Why this ladder
---------------
C major pentatonic from C5 to E6 (523 -> 1319 Hz). Two things follow from that:

1. It is consonant over the run soundtrack (Am-F-C-G), so a chime never clashes with
   whatever bar happens to be playing underneath it.
2. It is *ordered*: playing notes 1..8 in sequence is a rising line, and wrapping back
   to 1 still sounds like a resolution because the top note (E6) and the bottom (C5)
   are a major third plus an octave apart, not a semitone.

The instrument is a kalimba/harp hybrid rather than a bell: a strong fundamental with
a quiet, inharmonic tine partial (x5.4, the kalimba's characteristic "click" pitch),
short decay, and a very small upward drift across the tail so it reads as water
rather than as metal. Bells are the reward for a stage; this is the sound of picking
something up, and it plays dozens of times a minute, so it has to be soft and short.

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

# C major pentatonic, C5 -> E6. Eight notes, one per chime file.
PENTATONIC = [
    523.25, 587.33, 659.25, 783.99,
    880.00, 1046.50, 1174.66, 1318.51,
]

# Fundamental, the kalimba tine partial, a soft octave and a whisper of the twelfth.
# The 5.4 ratio is what makes it read as a plucked tine; a purely harmonic stack
# sounds like a synth lead and gets fatiguing when it fires every second.
PARTIALS = [1.0, 5.4, 2.0, 3.0]
BASE_AMPS = [1.00, 0.16, 0.11, 0.05]

# Peak, not RMS: see generate_evolution_bells.py. 0.50 is deliberately under the
# bells' 0.58 - this event fires far more often, and at -9.5 dB on the bus it has to
# stay under a boss theme without the limiter doing the work.
PEAK = 0.50


def chime(f0: float, index: int) -> np.ndarray:
    dur = 0.62
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR

    # A 4-cent rise across the whole tail. A real kalimba sags; a rise is what makes
    # the note feel like a drop of water instead. It is small enough to stay in tune.
    drift = 1.0 + 0.0023 * (t / dur)
    phase_t = np.cumsum(drift) / SR

    out = np.zeros(n, dtype=np.float64)
    for k, ratio in enumerate(PARTIALS):
        # Higher partials die faster, so the attack is bright and the tail is pure.
        tau = 0.34 / (1.0 + 0.75 * k)
        env = np.exp(-t / tau)
        out += BASE_AMPS[k] * env * np.sin(TWO_PI * f0 * ratio * phase_t)

    # A breath of the note an octave down, only for the first two notes: it gives the
    # bottom of the ladder a little body without muddying the top.
    if index < 2:
        out += 0.10 * np.exp(-t / 0.26) * np.sin(TWO_PI * f0 * 0.5 * phase_t)

    # 3 ms raised-cosine attack: enough to avoid a click, short enough that the note
    # feels immediate when a spore is swallowed.
    a = max(2, int(0.003 * SR))
    out[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, a))

    # 45 ms fade so the file does not end on a step.
    f = max(2, int(0.045 * SR))
    out[-f:] *= np.linspace(1.0, 0.0, f) ** 1.4

    return out


def loudness_match(x: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(x)))
    if peak <= 1e-9:
        return x
    return x * (PEAK / peak)


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def measure_fundamental(x: np.ndarray) -> float:
    """Dominant spectral peak, to prove each file really is its own note."""
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    # Ignore everything below 300 Hz: that is DC and envelope, not the note.
    mask = freqs >= 300.0
    return float(freqs[mask][np.argmax(spec[mask])])


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    lengths = []
    for i, f0 in enumerate(PENTATONIC):
        x = loudness_match(chime(f0, i))
        path = OUT_DIR / ("orb_chime_%02d.wav" % (i + 1))
        write_wav(path, x)
        size = path.stat().st_size
        total += size
        lengths.append(len(x) / SR)
        measured = measure_fundamental(x)
        err = abs(measured - f0) / f0 * 100.0
        print(
            "chime %d  f0=%7.2f Hz  measured=%7.2f (%+.2f%%)  %.2f s  %5.1f KB"
            % (i + 1, f0, measured, (measured - f0) / f0 * 100.0, len(x) / SR, size / 1024.0)
        )
        if err > 2.0:
            raise SystemExit("chime %d fundamental is off by %.1f%%" % (i + 1, err))
    print("total %.2f MB in %s" % (total / (1024.0 * 1024.0), OUT_DIR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
