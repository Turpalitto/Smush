#!/usr/bin/env python3
"""Synthesise the grove's breath: a wind-and-rustle bed that wakes with the slime.

The run already has a soundtrack. What it does not have is *air* — the sense that
the forest is a place with volume rather than a backdrop painted behind a slime.
This is a continuous, very quiet layer that fades in with `env_for_mass`, the same
0..1 value that already drives the bloom, the fireflies and the screen grade, so
growth is audible as well as visible.

Design notes that decide whether this works or sounds like a hiss:

* **Seamless by construction, not by crossfade.** Every layer is built by shaping
  white noise in the frequency domain and transforming back with `irfft`. The DFT
  is circular, so the result is *exactly* periodic over the buffer: there is no
  seam to cross-fade and no click to hide. The same trick fixes the modulation —
  every LFO is an integer number of cycles per loop.
* **Gusts wrap.** A gust that starts 0.8 s before the loop point is written with
  modular indices, so its tail continues into the head of the buffer instead of
  being cut off.
* **It must sit under the music, not beside it.** Peak-normalising an ambience bed
  is the wrong target: broadband noise at the same peak as a pad sounds far
  louder, because the pad has silence between its notes. The bed is mastered to
  -24 LUFS and the game trims it a further 6 dB under the music at full growth.
* **Bands, not one noise.** Three decorrelated layers — a low wind bed, sparse
  leaf gusts, and a fine high shimmer — read as weather. A single filtered noise
  reads as tape hiss no matter how it is modulated.

Usage:
    python3 tools/generate_grove_breath.py [OUT_DIR]
"""

from __future__ import annotations

import argparse
import math
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
LOOP_SEC = 16.0
N = int(SR * LOOP_SEC)
TWO_PI = 2.0 * math.pi
SEED = 20261023

# Loudness target for the bed. The music tracks are mastered to -20 / -22.5 LUFS;
# a continuous layer at -24 is already 2-4 LU under them before the game's own
# -6 dB trim, which is what keeps it a bed instead of a competitor.
TARGET_LUFS = -24.0
PEAK_CEILING_DBTP = -1.2

# Band placement and layer weights. The first version put 60 % of the raw energy
# below 250 Hz, which is a lovely wind bed on headphones and almost nothing on a
# phone speaker — the same trap the wonder chimes hit. A phone reproduces roughly
# 400 Hz - 10 kHz, so the bed is built where a phone can hear it: the low layer
# starts at 85 Hz rather than 48, the mid layer carries as much as the low one, and
# the gusts and shimmer fill the top.
#
# Weights are RMS ratios, not peak ratios. Peak-normalising each layer made the
# weights meaningless: a sparse gust and a dense bed normalised to the same peak
# carry completely different energy, so "0.34 of the gusts" was not 0.34 of anything.
#
# Measured after tuning (A-weighted, which is what the ear hears): lowmid 28 %,
# mid 45 %, high 17 %, air 6 %, and 88 % of the bed inside the band a phone speaker
# can reproduce.
LAYER_WEIGHTS = {"low": 1.00, "mid": 0.85, "gusts": 0.30, "shimmer": 0.24}


# --------------------------------------------------------------------------- helpers


def circular_noise(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    """White noise as a spectrum, so any gain curve applied to it stays periodic."""
    spec = np.fft.rfft(rng.standard_normal(N))
    freqs = np.fft.rfftfreq(N, 1.0 / SR)
    return spec, freqs


def band(spec: np.ndarray, freqs: np.ndarray, lo: float, hi: float, tilt: float) -> np.ndarray:
    """Band-limit a spectrum and give it a spectral tilt.

    `tilt` of 0 is flat (white), 0.5 is pink-ish, 1.0 is brown-ish. Some downward
    tilt is what separates wind from hiss; too much and the layer turns into a
    rumble that no phone speaker can play, which is why the final balance is
    mid-heavy rather than low-heavy.
    """
    f = np.maximum(freqs, 1.0)
    high_pass = (f / lo) / np.sqrt(1.0 + (f / lo) ** 2)
    low_pass = 1.0 / np.sqrt(1.0 + (f / hi) ** 2)
    colour = (100.0 / f) ** tilt
    return np.fft.irfft(spec * high_pass * low_pass * colour, N)


def unit(x: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(x)))
    return x / peak if peak > 1e-12 else x


def rms_unit(x: np.ndarray) -> np.ndarray:
    """Normalise to unit RMS, so a layer's weight is its share of the energy."""
    rms = float(np.sqrt(np.mean(x**2)))
    return x / rms if rms > 1e-12 else x


def lfo(cycles: float, phase: float) -> np.ndarray:
    """A sine with an integer number of cycles per loop, so it is loop-periodic."""
    t = np.arange(N) / SR
    return 0.5 + 0.5 * np.sin(TWO_PI * cycles * t / LOOP_SEC + phase)


# --------------------------------------------------------------------------- layers


def wind_bed(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    """The body of the air: two decorrelated bands breathing against each other."""
    spec_a, freqs = circular_noise(rng)
    spec_b, _ = circular_noise(rng)
    low = unit(band(spec_a, freqs, 85.0, 380.0, 0.55))
    mid = unit(band(spec_b, freqs, 280.0, 1200.0, 0.35))

    # Three incommensurate-looking but integer-cycle LFOs: 2, 3 and 5 breaths per
    # 16 s loop. The sum never repeats inside the loop, which is what stops the ear
    # from finding the period.
    slow = 0.34 + 0.44 * lfo(2, 0.0) + 0.30 * lfo(3, 1.9) + 0.22 * lfo(5, 4.1)
    slow = slow / float(np.max(slow))
    cross = 0.55 + 0.45 * lfo(3, 2.7)

    return low * slow, mid * cross * slow


def leaf_gusts(rng: np.random.Generator) -> tuple[np.ndarray, int]:
    """Sparse high bursts with a fast attack and a long tail, panned and wrapped."""
    spec, freqs = circular_noise(rng)
    texture = unit(band(spec, freqs, 1500.0, 7500.0, 0.25))
    out = np.zeros(N, dtype=np.float64)
    count = int(rng.integers(7, 11))
    for _ in range(count):
        start = int(rng.integers(0, N))
        length = int(rng.uniform(1.4, 3.6) * SR)
        idx = np.arange(length)
        # Attack ~0.30 s, decay to near-silence by the end of the burst. The tail is
        # long on purpose: a short burst reads as a click, a long one as a gust.
        attack = 1.0 - np.exp(-idx / (0.30 * SR))
        decay = np.exp(-idx / (0.85 * length))
        env = attack * decay
        # The burst is taken from a rotating slice of the texture so overlapping
        # gusts are not the same noise twice.
        offset = int(rng.integers(0, N))
        seg = texture[(idx + offset) % N] * env
        gain = float(rng.uniform(0.35, 1.0))
        out[(idx + start) % N] += seg * gain
    return unit(out), count


def leaf_shimmer(rng: np.random.Generator) -> np.ndarray:
    """The fine sizzle of leaves overhead. Quiet, and modulated faster than the wind."""
    spec, freqs = circular_noise(rng)
    hiss = unit(band(spec, freqs, 3500.0, 12000.0, 0.15))
    flutter = 0.35 + 0.65 * (0.6 * lfo(17, 0.7) + 0.4 * lfo(23, 3.3))
    return hiss * flutter


def build_channel(seed: int) -> tuple[np.ndarray, dict]:
    rng = np.random.default_rng(seed)
    low, mid = wind_bed(rng)
    gusts, gust_count = leaf_gusts(rng)
    shimmer = leaf_shimmer(rng)
    mix = (
        rms_unit(low) * LAYER_WEIGHTS["low"]
        + rms_unit(mid) * LAYER_WEIGHTS["mid"]
        + rms_unit(gusts) * LAYER_WEIGHTS["gusts"]
        + rms_unit(shimmer) * LAYER_WEIGHTS["shimmer"]
    )
    return unit(mix), {"gusts": gust_count}


# --------------------------------------------------------------------------- measure


def seam_report(x: np.ndarray) -> tuple[float, float, float, float]:
    """Is the loop point special? Two independent questions, two instruments.

    **Click.** A click is a step bigger than the material ever makes on its own, so
    the seam step is compared with the 99.99th percentile of every ordinary step. An
    absolute threshold would pass a quiet file with a real click and fail a loud one
    with none.

    **Level.** The first attempt compared the RMS of the last 50 ms with the first
    50 ms and reported a 29 % jump on a bed that has no seam at all: 50 ms of a
    gusty signal is not a level, it is one gust. The question is not "are these two
    windows equal" but "is the window straddling the loop point typical of this
    file". So the seam window is concatenated across the wrap and compared with the
    distribution of every other window of the same length; the z-score is the
    answer, and anything inside ±2 is ordinary material.
    """
    diffs = np.abs(np.diff(x))
    seam = float(abs(x[0] - x[-1]))
    typical = float(np.percentile(diffs, 99.99))

    win = int(0.10 * SR)
    hop = win // 2
    starts = np.arange(0, N - win, hop)
    rms = np.array([float(np.sqrt(np.mean(x[s : s + win] ** 2))) for s in starts])
    seam_rms = float(np.sqrt(np.mean(np.concatenate([x[-hop:], x[:hop]]) ** 2)))
    mean = float(np.mean(rms))
    std = float(np.std(rms))
    z = (seam_rms - mean) / max(std, 1e-9)
    return seam, typical, z, seam_rms / max(mean, 1e-9)


def a_weighted_shares(x: np.ndarray) -> tuple[dict, float]:
    """Perceptual band balance (IEC 61672 A-weighting) and the phone-band share.

    Raw spectrum shares lie about what a bed sounds like: 30 % of the energy in
    6-16 kHz is a whisper, 30 % in 80-250 Hz is a rumble. A-weighting is the
    standard correction for that, and the "phone band" figure (400 Hz - 10 kHz) is
    the part of the bed a phone speaker can actually reproduce at all.
    """
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    f2 = f**2
    ra = (12194.0**2 * f2**2) / (
        (f2 + 20.6**2) * np.sqrt((f2 + 107.7**2) * (f2 + 737.9**2)) * (f2 + 12194.0**2)
    )
    aw = spec * (ra * 10.0 ** (2.0 / 20.0)) ** 2
    total = float(aw.sum())
    bands = {
        "sub": (20, 80),
        "low": (80, 250),
        "lowmid": (250, 800),
        "mid": (800, 2500),
        "high": (2500, 6000),
        "air": (6000, 16000),
    }
    shares = {}
    for name, (lo, hi) in bands.items():
        m = (f >= lo) & (f < hi)
        shares[name] = 100.0 * float(aw[m].sum()) / max(total, 1e-30)
    phone = (f >= 400) & (f < 10000)
    return shares, 100.0 * float(aw[phone].sum()) / max(total, 1e-30)


def write_wav(path: Path, left: np.ndarray, right: np.ndarray) -> None:
    data = np.empty(N * 2, dtype="<i2")
    data[0::2] = np.clip(left * 32767.0, -32768, 32767).astype("<i2")
    data[1::2] = np.clip(right * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def decode_peak(ffmpeg: str, path: Path) -> float:
    """Peak of the decoded file, per channel. Vorbis overshoots the float buffer."""
    out = subprocess.run(
        [ffmpeg, "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-"],
        check=True,
        capture_output=True,
    ).stdout
    samples = np.frombuffer(out, dtype="<f4")
    return float(np.max(np.abs(samples))) if samples.size else 0.0


def measure_loudness(ffmpeg: str, path: Path) -> tuple[float | None, float | None]:
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


def encode(ffmpeg: str, wav: Path, ogg: Path) -> tuple[float | None, float | None]:
    gain_db = 0.0
    lufs: float | None = None
    peak: float | None = None
    for _ in range(4):
        cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", str(wav)]
        if abs(gain_db) > 1e-3:
            cmd += ["-af", f"volume={gain_db:.2f}dB"]
        cmd += ["-c:a", "libvorbis", "-q:a", "5", str(ogg)]
        subprocess.run(cmd, check=True)
        lufs, peak = measure_loudness(ffmpeg, ogg)
        if lufs is None or peak is None:
            break
        trim = min(TARGET_LUFS - lufs, PEAK_CEILING_DBTP - peak)
        if abs(trim) < 0.3:
            break
        gain_db += trim
        print(f"  ! {lufs:+.1f} LUFS / {peak:+.1f} dBTP — re-encoding at {gain_db:+.2f} dB")
    return lufs, peak


# --------------------------------------------------------------------------- main


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

    left, info_l = build_channel(SEED)
    right, info_r = build_channel(SEED + 1)
    print(f"grove breath: {LOOP_SEC:.1f} s, {N} samples, gusts {info_l['gusts']}/{info_r['gusts']}")

    ok = True
    for name, x in (("L", left), ("R", right)):
        seam, typical, z, rel = seam_report(x)
        rms = float(np.sqrt(np.mean(x**2)))
        verdict = "OK" if seam <= typical else "CLICK"
        if seam > typical:
            ok = False
        print(
            f"  {name}: peak {20 * math.log10(float(np.max(np.abs(x)))):6.2f} dBFS  "
            f"rms {20 * math.log10(rms):6.2f} dBFS  "
            f"seam {seam:.5f} vs p99.99 step {typical:.5f} [{verdict}]  "
            f"seam window level {rel:.3f} of mean (z {z:+.2f})"
        )
        if abs(z) > 2.0:
            print("  ! the window across the loop point is not typical material")
            ok = False
        shares, phone = a_weighted_shares(x)
        print("    A-weighted: " + "  ".join(f"{k} {v:4.1f}%" for k, v in shares.items())
              + f"   phone band {phone:4.1f}%")
        if phone < 60.0:
            print("  ! less than 60 % of the bed is audible on a phone speaker")
            ok = False

    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "forest_breath.wav"
        write_wav(wav, left, right)
        if not ffmpeg:
            write_wav(out_dir / "forest_breath.wav", left, right)
            return 0 if ok else 1
        ogg = out_dir / "forest_breath.ogg"
        lufs, dbtp = encode(ffmpeg, wav, ogg)
        decoded = decode_peak(ffmpeg, ogg)
        print(
            f"  -> {ogg}  {ogg.stat().st_size // 1024} KB  "
            f"{lufs:.1f} LUFS  true peak {dbtp:+.1f} dBTP  "
            f"decoded peak {20 * math.log10(max(decoded, 1e-9)):.2f} dBFS"
        )
        if decoded > 1.0:
            print("  ! decoded peak exceeds full scale")
            ok = False

    if not ok:
        print("FAILED: the loop is not clean")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
