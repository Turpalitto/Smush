#!/usr/bin/env python3
"""Generate the three Wonder chords: audio/sfx/wonder_chime_01..03.wav.

Why a chord and not the orb chime
---------------------------------
The collection ladder (tools/generate_orb_chimes.py) is a plucked kalimba tine:
short, dry, and deliberately forgettable because it fires dozens of times a
minute. A Wonder is the opposite event — the player walks up to a landmark they
have never seen before and it wakes. It needs a sound that is obviously a
different *class* of thing, so it is a struck bell triad with a two-second tail
instead of a 0.6-second pluck.

Why three files
---------------
Each landmark gets its own voice rather than one chord transposed through
`pitch_scale`: `AudioManager.play_sfx` clamps pitch to [0.55, 1.75], and a
transposed bell loses the partial spacing that makes it read as a bell at all
(the ratios are absolute, not relative, so a pitch shift moves the whole
inharmonic series by the same factor and the strike character changes).

The three chords are A minor, F major and C major, in that order of brightness.
All three are diatonic to the run soundtrack's Am-F-C-G, so a Wonder that fires
over a bar of anything underneath it is consonant.

Why a roll
----------
The notes are staggered by 55 ms low-to-high. A block chord on a bell stops
being a bell and starts being a synth pad; a roll reads as the object opening,
which is what the visual is doing at the same moment.

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

# A struck bell's inharmonic series. 0.5 is the hum (the note you hear after the
# strike has gone), 1.0 the prime, 1.19 the tierce that gives a bell its minor
# colour, 2.0 the nominal that carries the pitch at the moment of impact.
PARTIALS = [0.5, 1.0, 1.19, 1.5, 2.0, 2.5, 3.0, 4.0]
# The tierce is quiet on purpose: at full strength it turns the chord muddy,
# because each note already supplies its own third. The hum is kept under the
# prime — a real bell's hum is louder, but the hum of a 350 Hz note is 175 Hz and
# a phone speaker reproduces almost none of it, so a hum-heavy voicing loses the
# chord on the device it ships to.
AMPS = [0.30, 0.66, 0.20, 0.26, 0.50, 0.16, 0.12, 0.07]
# Seconds. The hum rings far longer than the strike, which is what makes the
# chord bloom instead of hitting and stopping.
TAUS = [2.10, 1.45, 0.85, 0.80, 1.10, 0.50, 0.38, 0.26]

# Low-to-high, so the roll opens upward. The bottom of every voicing is kept at or
# above F4 (349 Hz): the run bed is mixed on a phone, and a phone speaker gives up
# below roughly 400 Hz, so a chord rooted on C4 is a chord the player never hears.
CHORDS = {
    "wonder_chime_01": [440.00, 523.25, 659.25, 880.00],    # A minor  (crystal)
    "wonder_chime_02": [349.23, 440.00, 523.25, 698.46],    # F major  (fountain)
    "wonder_chime_03": [523.25, 659.25, 783.99, 1046.50],   # C major  (lantern)
}
# Amplitude of each note in the roll. The top note is a shimmer, not a voice.
NOTE_AMPS = [1.00, 0.82, 0.68, 0.30]
ROLL_SEC = 0.055
DUR = 2.05
# Higher than the orb chime's 0.50: this fires a handful of times per run.
PEAK = 0.62


def bell(f0: float, amp: float) -> np.ndarray:
    n = int(SR * DUR)
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    for k, ratio in enumerate(PARTIALS):
        # Slightly stretched partials (a real bell's are), and each one detuned by a
        # hair so the series beats slowly instead of sitting perfectly still.
        ratio_k = ratio * (1.0 + 0.0016 * k * k)
        env = np.exp(-t / TAUS[k])
        out += AMPS[k] * amp * env * np.sin(TWO_PI * f0 * ratio_k * t)
    return out


def build(freqs: list[float]) -> np.ndarray:
    total = np.zeros(int(SR * (DUR + ROLL_SEC * len(freqs))), dtype=np.float64)
    for i, f0 in enumerate(freqs):
        note = bell(f0, NOTE_AMPS[i])
        start = int(SR * ROLL_SEC * i)
        total[start:start + len(note)] += note
    # 4 ms raised-cosine attack on the whole mix so the first strike does not click.
    a = max(2, int(0.004 * SR))
    total[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, a))
    # 90 ms tail fade: a bell should decay, not be cut.
    f = max(2, int(0.090 * SR))
    total[-f:] *= np.linspace(1.0, 0.0, f) ** 1.5
    peak = float(np.max(np.abs(total)))
    if peak > 1e-9:
        total *= PEAK / peak
    return total


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def note_present(x: np.ndarray, f0: float) -> float:
    """How far the bin at `f0` stands above its neighbourhood, as a ratio.

    A global "top four peaks" check is useless here: a bell's hum and tierce are
    inharmonic, so the loudest bins are not the written notes and a note can be
    perfectly audible while ranking eighth. This asks the question the check is
    actually about — is there a peak at this frequency, or just the noise floor
    around it — by dividing the local maximum by the local median.
    """
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    # +-1.5 % catches the stretch applied to the partials without reaching the
    # neighbouring note (the closest pair in any voicing is 189 Hz apart at 440).
    band = (freqs > f0 * 0.985) & (freqs < f0 * 1.015)
    if not np.any(band):
        return 0.0
    peak = float(np.max(spec[band]))
    wide = (freqs > f0 - 150.0) & (freqs < f0 + 150.0) & ~band
    if not np.any(wide):
        return 0.0
    floor = float(np.median(spec[wide]))
    return peak / max(floor, 1e-9)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, freqs in CHORDS.items():
        x = build(freqs)
        path = OUT_DIR / f"{name}.wav"
        write_wav(path, x)
        size = path.stat().st_size
        total += size
        top = [(f0, note_present(x, f0)) for f0 in freqs]
        print(
            "%-16s notes=%s  %.2f s  %5.1f KB  peak=%.3f"
            % (name, [round(f, 1) for f in freqs], len(x) / SR, size / 1024.0,
               float(np.max(np.abs(x))))
        )
        print(
            "%18s prominence %s"
            % ("", " ".join("%.0fHz=%.1fx" % (f0, r) for f0, r in top))
        )
        # Every written note must stand clear of its own neighbourhood. If a note
        # got lost in the mix the chord is not the chord, and no later check in the
        # GDScript suite can hear the difference.
        for f0, ratio in top:
            if ratio < 3.0:
                raise SystemExit(
                    "%s: note %.1f Hz is buried (prominence %.2fx)" % (name, f0, ratio)
                )
    print("total %.1f KB in %s" % (total / 1024.0, OUT_DIR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
