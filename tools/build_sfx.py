"""
build_sfx.py: synthesises the game's sound effects (ASSETS-8) into art/audio/<name>.ogg.

Pure Python (no numpy) + ffmpeg (libvorbis) for the OGG encode. Deterministic: a fixed seed
per sound, so a rebuild gives the same files. Every sound is peak-normalised to -1 dBFS; the
in-game loudness is SoundConfig.volume. Loops (charge, ambient) are built seamless: whole
cycles for tones, an equal-power crossfade of the tail into the head for noise.

Usage (repo root):  python tools/build_sfx.py [--only hop,land] [--ffmpeg PATH]
Then upload the OGGs (tools/roblox_upload.py audio) and the ids land in
src/shared/Config/SoundConfig.luau.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

SR = 44100
OUT_DIR = os.path.join("art", "audio")
TAU = 2 * math.pi


# ------------------------------------------------------------------------------ primitives
def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * SR)


def n(seconds: float) -> int:
    return int(seconds * SR)


def tone(seconds: float, f0: float, f1: float | None = None, partials=((1, 1.0),), curve: float = 1.0) -> list[float]:
    """A tone gliding f0 -> f1 (exponential glide), as a sum of (harmonic, gain) partials."""
    f1 = f0 if f1 is None else f1
    count = n(seconds)
    out = [0.0] * count
    phase = 0.0
    for i in range(count):
        t = i / max(1, count - 1)
        f = f0 * (f1 / f0) ** (t**curve)
        phase += TAU * f / SR
        s = 0.0
        for harmonic, gain in partials:
            s += gain * math.sin(phase * harmonic)
        out[i] = s
    return out


def white(seconds: float, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(n(seconds))]


def pink(seconds: float, rng: random.Random) -> list[float]:
    """Paul Kellet's economy pink-noise filter."""
    b0 = b1 = b2 = 0.0
    out = []
    for _ in range(n(seconds)):
        w = rng.uniform(-1.0, 1.0)
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        out.append((b0 + b1 + b2 + w * 0.1848) * 0.2)
    return out


def lowpass(x: list[float], cutoff: float) -> list[float]:
    a = 1 - math.exp(-TAU * cutoff / SR)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(x: list[float], cutoff: float) -> list[float]:
    low = lowpass(x, cutoff)
    return [s - l for s, l in zip(x, low)]


def bandpass(x: list[float], center, q: float = 1.0) -> list[float]:
    """RBJ band-pass (constant peak gain). `center` is a number or a function of 0..1."""
    count = len(x)
    out = [0.0] * count
    x1 = x2 = y1 = y2 = 0.0
    for i, s in enumerate(x):
        f = center(i / max(1, count - 1)) if callable(center) else center
        w0 = TAU * min(f, SR * 0.45) / SR
        alpha = math.sin(w0) / (2 * q)
        cos = math.cos(w0)
        a0 = 1 + alpha
        y = (alpha * s - alpha * x2 - (-2 * cos) * y1 - (1 - alpha) * y2) / a0
        x2, x1 = x1, s
        y2, y1 = y1, y
        out[i] = y
    return out


def env(x: list[float], attack: float, decay: float, hold: float = 0.0) -> list[float]:
    """Linear attack, optional hold, then exponential decay (time constant `decay`)."""
    a, h = n(attack), n(hold)
    out = []
    for i, s in enumerate(x):
        if i < a:
            g = i / max(1, a)
        elif i < a + h:
            g = 1.0
        else:
            g = math.exp(-((i - a - h) / SR) / max(1e-4, decay))
        out.append(s * g)
    return out


def gain(x: list[float], g: float) -> list[float]:
    return [s * g for s in x]


def mix(length: float, *layers: tuple[float, list[float]]) -> list[float]:
    """Sums (start_seconds, samples) layers into a buffer `length` seconds long."""
    out = silence(length)
    for start, samples in layers:
        offset = n(start)
        for i, s in enumerate(samples):
            j = offset + i
            if 0 <= j < len(out):
                out[j] += s
    return out


def fade_edges(x: list[float], fade_in: float = 0.002, fade_out: float = 0.01) -> list[float]:
    a, b = n(fade_in), n(fade_out)
    out = list(x)
    for i in range(min(a, len(out))):
        out[i] *= i / max(1, a)
    for i in range(min(b, len(out))):
        out[len(out) - 1 - i] *= i / max(1, b)
    return out


def loop_crossfade(x: list[float], loop_seconds: float, cross_seconds: float) -> list[float]:
    """x must be loop + cross long; the tail is crossfaded (equal power) into the head."""
    length, cross = n(loop_seconds), n(cross_seconds)
    out = x[:length]
    for i in range(cross):
        t = i / cross
        out[i] = x[i] * math.sin(t * math.pi / 2) + x[length + i] * math.cos(t * math.pi / 2)
    return out


def normalise(x: list[float], peak_db: float = -1.0) -> list[float]:
    peak = max((abs(s) for s in x), default=0.0)
    if peak <= 0:
        return x
    target = 10 ** (peak_db / 20)
    return [s * target / peak for s in x]


# ------------------------------------------------------------------------------ the sounds
def hop(rng):
    whoosh = env(bandpass(white(0.34, rng), lambda t: 500 + 1100 * t, 1.1), 0.07, 0.09)
    hum = env(lowpass(tone(0.34, 150, 195, ((1, 1), (2, 0.5), (3, 0.25))), 900), 0.05, 0.1)
    return mix(0.36, (0, whoosh), (0, gain(hum, 0.18)))


def land(rng):
    thump = env(tone(0.3, 115, 50), 0.003, 0.09)
    click = env(highpass(white(0.01, rng), 2500), 0.0005, 0.003)
    chirp = env(tone(0.16, 600, 1900, ((1, 1), (2, 0.2))), 0.01, 0.06)
    return mix(0.45, (0, thump), (0, gain(click, 0.5)), (0.04, gain(chirp, 0.22)))


def plant(rng):
    thud = env(lowpass(white(0.18, rng), 380), 0.002, 0.06)
    body = env(tone(0.16, 190, 85), 0.002, 0.05)
    pip = env(tone(0.04, 1400, 1250), 0.002, 0.012)
    return mix(0.25, (0, gain(thud, 1.6)), (0, gain(body, 0.6)), (0.0, gain(pip, 0.18)))


def water(rng):
    splash = env(highpass(white(0.35, rng), 1600), 0.004, 0.09)
    layers = [(0, gain(splash, 0.7))]
    for start, f in ((0.05, 1700), (0.13, 1450), (0.22, 1900)):
        drop = env(tone(0.05, f, f * 0.45, curve=0.6), 0.001, 0.02)
        layers.append((start, gain(drop, 0.35)))
    return mix(0.5, *layers)


def harvest(rng):
    pop = env(tone(0.05, 380, 950, curve=0.5), 0.001, 0.025)
    click = env(highpass(white(0.008, rng), 3000), 0.0005, 0.002)
    chime = env(tone(0.5, 1046.5, partials=((1, 1), (1.5, 0.45), (2, 0.25))), 0.003, 0.16)
    return mix(0.55, (0, pop), (0, gain(click, 0.4)), (0.03, gain(chime, 0.4)))


def unripe(rng):
    thunk = env(tone(0.2, 165, 95), 0.002, 0.07)
    dirt = env(lowpass(white(0.12, rng), 500), 0.002, 0.04)
    sad = env(tone(0.22, 520, 290, ((1, 1), (3, 0.18))), 0.01, 0.08)
    return mix(0.4, (0, thunk), (0, gain(dirt, 1.2)), (0.07, gain(sad, 0.3)))


def _scrape(rng, seconds):
    grains = []
    grain = n(0.014)
    level = 0.0
    for i in range(n(seconds)):
        if i % grain == 0:
            level = rng.uniform(0.25, 1.0)
        grains.append(level)
    noise = lowpass(white(seconds, rng), 1300)
    return env([s * g for s, g in zip(noise, grains)], 0.01, seconds * 0.4)


def dig(rng):
    thud = env(tone(0.15, 130, 70), 0.002, 0.05)
    return mix(0.45, (0, gain(_scrape(rng, 0.4), 2.2)), (0, gain(thud, 0.5)))


def fossil(rng):
    layers = [(0, gain(_scrape(rng, 0.28), 2.0))]
    for k, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        note = env(tone(0.3, f, partials=((1, 1), (2, 0.3))), 0.002, 0.09)
        layers.append((0.22 + k * 0.06, gain(note, 0.3)))
    return mix(0.85, *layers)


def deposit(rng):
    clunk = env(tone(0.16, 95, 70, ((1, 1), (3, 0.3), (5, 0.12))), 0.002, 0.05)
    hit = env(bandpass(white(0.08, rng), 900, 1.4), 0.001, 0.025)
    whoosh = env(bandpass(white(0.36, rng), lambda t: 2100 - 1600 * t, 1.3), 0.05, 0.1)
    tick = env(tone(0.03, 2400), 0.001, 0.008)
    return mix(0.6, (0, clunk), (0, gain(hit, 1.4)), (0.06, gain(whoosh, 0.9)), (0.44, gain(tick, 0.25)))


def unload(rng):
    layers = []
    for k in range(6):
        f = rng.uniform(2400, 3600)
        tick = env(tone(0.04, f, partials=((1, 1), (2.76, 0.3))), 0.0005, 0.012)
        layers.append((0.03 + k * 0.065 + rng.uniform(-0.015, 0.015), gain(tick, 0.4)))
    chime = env(tone(0.3, 1318.5, partials=((1, 1), (2, 0.2))), 0.003, 0.1)
    layers.append((0.42, gain(chime, 0.3)))
    return mix(0.75, *layers)


def refine(rng):
    hum = env(lowpass(tone(0.9, 70, partials=((1, 1), (2, 0.5), (3, 0.2))), 400), 0.12, 0.35)
    layers = [(0, gain(hum, 0.35))]
    for _ in range(11):
        f = rng.uniform(260, 620)
        blip = env(tone(0.05, f, f * 1.7, curve=0.7), 0.002, 0.018)
        layers.append((rng.uniform(0.02, 0.62), gain(blip, 0.3)))
    return mix(0.9, *layers)


def charge(rng):
    # 2.0 s loop: 120 Hz family (whole cycles), 4 Hz tremolo (8 cycles), crossfaded crackle.
    seconds = 2.0
    count = n(seconds)
    out = []
    for i in range(count):
        t = i / SR
        s = (
            math.sin(TAU * 120 * t)
            + 0.5 * math.sin(TAU * 240 * t)
            + 0.22 * math.sin(TAU * 360 * t)
            + 0.1 * math.sin(TAU * 480 * t)
        )
        trem = 0.8 + 0.2 * math.sin(TAU * 4 * t)
        out.append(s * trem * 0.5)
    out = lowpass(out, 1200)
    crackle = loop_crossfade(highpass(white(seconds + 0.25, rng), 3500), seconds, 0.25)
    return [a + 0.05 * c for a, c in zip(out, crackle)]


def research(rng):
    layers = []
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        last = k == 3
        note = env(tone(0.45 if last else 0.2, f, partials=((1, 1), (3, 0.25), (5, 0.08))), 0.004, 0.18 if last else 0.07)
        layers.append((k * 0.075, gain(note, 0.32)))
    return mix(0.75, *layers)


def purchase(rng):
    shimmer = env(highpass(white(0.12, rng), 4500), 0.002, 0.03)
    layers = [(0, gain(shimmer, 0.35)), (0.11, gain(shimmer, 0.3))]
    for start, f in ((0.09, 1568.0), (0.17, 2093.0)):
        bell = env(tone(0.6, f, partials=((1, 1), (2.76, 0.35), (5.4, 0.12))), 0.002, 0.17)
        layers.append((start, gain(bell, 0.32)))
    return mix(0.8, *layers)


def click(rng):
    tick = env(tone(0.03, 1900, 1500), 0.0005, 0.006)
    noise = env(highpass(white(0.006, rng), 3000), 0.0003, 0.0015)
    return mix(0.04, (0, tick), (0, gain(noise, 0.3)))


def hover(rng):
    return mix(0.03, (0, env(tone(0.025, 2700, 2900), 0.001, 0.005)))


def error(rng):
    a = env(tone(0.15, 220, partials=((1, 1), (3, 0.3), (5, 0.1))), 0.004, 0.06)
    b = env(tone(0.2, 174.6, partials=((1, 1), (3, 0.3), (5, 0.1))), 0.004, 0.08)
    return mix(0.42, (0, gain(a, 0.5)), (0.16, gain(b, 0.5)))


def ambient(rng):
    # 24 s calm field: wind (pink, LFO periods 12 s / 24 s / 8 s divide the loop) + 5 birds.
    loop, cross = 24.0, 3.0
    total = loop + cross
    wind = lowpass(pink(total, rng), 520)
    rustle = highpass(pink(total, rng), 2500)
    out = []
    for i in range(n(total)):
        t = i / SR
        swell = 0.6 + 0.25 * math.sin(TAU * t / 12) + 0.15 * math.sin(TAU * t / 24 + 1.3)
        leaves = 0.5 + 0.5 * math.sin(TAU * t / 8 + 0.4)
        out.append(wind[i] * swell * 2.2 + rustle[i] * leaves * 0.18)
    out = loop_crossfade(out, loop, cross)
    for start in (3.4, 7.9, 11.2, 15.6, 19.3):  # never in the crossfaded head (0..3 s)
        for k in range(rng.choice((2, 3))):
            f = rng.uniform(2600, 3400)
            chirp = env(tone(0.08, f, f * rng.uniform(1.15, 1.35), curve=0.5), 0.005, 0.03)
            offset = n(start + k * 0.12)
            for j, s in enumerate(chirp):
                if offset + j < len(out):
                    out[offset + j] += s * 0.05
    return out


SOUNDS = {
    "hop": (hop, False),
    "land": (land, False),
    "plant": (plant, False),
    "water": (water, False),
    "harvest": (harvest, False),
    "unripe": (unripe, False),
    "dig": (dig, False),
    "fossil": (fossil, False),
    "deposit": (deposit, False),
    "unload": (unload, False),
    "refine": (refine, False),
    "charge": (charge, True),
    "research": (research, False),
    "purchase": (purchase, False),
    "click": (click, False),
    "hover": (hover, False),
    "error": (error, False),
    "ambient": (ambient, True),
}


def write_wav(path: str, samples: list[float]):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated sound names")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or r"C:\ffmpeg\ffmpeg.exe")
    args = parser.parse_args()
    names = args.only.split(",") if args.only else list(SOUNDS)
    unknown = [name for name in names if name not in SOUNDS]
    if unknown:
        print("unknown sounds: " + ", ".join(unknown), file=sys.stderr)
        return 2
    os.makedirs(OUT_DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for index, name in enumerate(names):
            build, looped = SOUNDS[name]
            rng = random.Random(1000 + list(SOUNDS).index(name))
            samples = build(rng)
            if not looped:
                samples = fade_edges(samples)
            samples = normalise(samples)
            wav = os.path.join(tmp, name + ".wav")
            write_wav(wav, samples)
            ogg = os.path.join(OUT_DIR, name + ".ogg")
            subprocess.run(
                [args.ffmpeg, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg],
                check=True,
            )
            print(f"{name:9s} {len(samples) / SR:5.2f} s  {'loop' if looped else '    '}  {os.path.getsize(ogg) / 1024:6.1f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
