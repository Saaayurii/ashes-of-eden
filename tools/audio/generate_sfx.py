#!/usr/bin/env python3
"""Generates the placeholder half of the sound set in assets/audio/.

The real clips are built by build_audio.py from CC0 sources; these stand in
where no real clip has been chosen yet, so every moment in scripts/autoload/audio.gd
makes *some* noise. Synthesised with the standard library, so the repository
owns them outright and anyone can re-roll them. A name that has both a real and
a generated clip takes the real one (see Audio._load_clips), which is what makes
replacing a placeholder a matter of dropping an .ogg beside it.

    python3 tools/audio/generate_sfx.py
"""
import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
SFX_RATE = 44100
MUSIC_RATE = 22050


# ----------------------------------------------------------------- helpers ---

def silence(seconds, rate):
    return [0.0] * int(seconds * rate)


def env(buf, attack, decay, curve=2.0):
    """Attack/decay shape over the whole buffer, in fractions of its length."""
    n = len(buf)
    a = max(1, int(n * attack))
    out = []
    for i, v in enumerate(buf):
        if i < a:
            g = i / a
        else:
            t = (i - a) / max(1, n - a)
            g = max(0.0, 1.0 - t) ** (curve / max(decay, 0.01))
        out.append(v * g)
    return out


def noise(seconds, rate):
    return [random.uniform(-1.0, 1.0) for _ in range(int(seconds * rate))]


def tone(seconds, rate, f0, f1=None, shape="sine"):
    """A sine (or triangle) sweeping from f0 to f1 over its length."""
    f1 = f0 if f1 is None else f1
    n = int(seconds * rate)
    out = []
    phase = 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / max(1, n - 1))
        phase += 2.0 * math.pi * f / rate
        if shape == "tri":
            out.append(2.0 / math.pi * math.asin(math.sin(phase)))
        else:
            out.append(math.sin(phase))
    return out


def lowpass(buf, cutoff, rate):
    """One-pole lowpass: enough to turn white noise into air, wood or rumble."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / rate)
    out, last = [], 0.0
    for v in buf:
        last += a * (v - last)
        out.append(last)
    return out


def highpass(buf, cutoff, rate):
    return [v - lp for v, lp in zip(buf, lowpass(buf, cutoff, rate))]


def lowpass_loop(buf, cutoff, rate):
    """lowpass() for a buffer that will be looped. The filter carries state, so
    starting it at zero leaves the head of the loop filtered differently from
    the tail and the seam clicks. Run it once to settle, then again for real."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / rate)
    last = 0.0
    for v in buf:
        last += a * (v - last)
    out = []
    for v in buf:
        last += a * (v - last)
        out.append(last)
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def normalize(buf, peak=0.7):
    top = max((abs(v) for v in buf), default=0.0)
    if top < 1e-6:
        return buf
    return [v * peak / top for v in buf]


def write(path, buf, rate):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf))
    print("wrote", os.path.relpath(path, ROOT), "%.1f KiB" % (os.path.getsize(path) / 1024))


# -------------------------------------------------------------------- sfx ---

def swing():
    air = highpass(lowpass(noise(0.2, SFX_RATE), 4200, SFX_RATE), 700, SFX_RATE)
    return normalize(env(air, 0.12, 1.0, 2.6), 0.45)


def hit(crit=False):
    body = env(tone(0.16, SFX_RATE, 190 if crit else 150, 60, "tri"), 0.004, 1.0, 3.0)
    crack = env(lowpass(noise(0.09, SFX_RATE), 3000 if crit else 1800, SFX_RATE), 0.002, 1.0, 4.0)
    layers = [body, [v * 0.8 for v in crack]]
    if crit:
        ring = env(mix(tone(0.32, SFX_RATE, 1180), [v * 0.6 for v in tone(0.32, SFX_RATE, 1790)]),
                   0.01, 1.0, 2.0)
        layers.append([v * 0.35 for v in ring])
    return normalize(mix(*layers), 0.82 if crit else 0.7)


def enemy_death():
    fall = env(tone(0.45, SFX_RATE, 380, 70, "tri"), 0.01, 1.0, 1.6)
    ash = env(lowpass(noise(0.5, SFX_RATE), 2400, SFX_RATE), 0.05, 1.0, 1.3)
    return normalize(mix(fall, [v * 0.55 for v in ash]), 0.72)


def player_hurt():
    thud = env(tone(0.26, SFX_RATE, 260, 90, "tri"), 0.004, 1.0, 2.2)
    grit = env(lowpass(noise(0.2, SFX_RATE), 1300, SFX_RATE), 0.01, 1.0, 2.4)
    return normalize(mix(thud, [v * 0.5 for v in grit]), 0.8)


def dash():
    air = highpass(lowpass(noise(0.3, SFX_RATE), 3000, SFX_RATE), 400, SFX_RATE)
    return normalize(env(air, 0.35, 1.0, 1.8), 0.5)


def prop_break():
    cracks = silence(0.34, SFX_RATE)
    for start in (0.0, 0.035, 0.08, 0.15):
        piece = env(lowpass(noise(0.12, SFX_RATE), random.uniform(1600, 3400), SFX_RATE),
                    0.002, 1.0, 5.0)
        offset = int(start * SFX_RATE)
        for i, v in enumerate(piece):
            if offset + i < len(cracks):
                cracks[offset + i] += v * random.uniform(0.5, 1.0)
    return normalize(cracks, 0.7)


def block():
    """The blade held: a dull steel thud, most of the ring swallowed."""
    thud = env(tone(0.14, SFX_RATE, 210, 120, "tri"), 0.003, 1.0, 3.2)
    clank = env(lowpass(noise(0.08, SFX_RATE), 2200, SFX_RATE), 0.002, 1.0, 4.5)
    ring = env(mix(tone(0.18, SFX_RATE, 640), [v * 0.5 for v in tone(0.18, SFX_RATE, 1010)]), 0.004, 1.0, 3.5)
    return normalize(mix(thud, [v * 0.7 for v in clank], [v * 0.18 for v in ring]), 0.7)


def parry():
    """The parry: a bright crack of steel and a long, clean ring after it."""
    crack = env(highpass(noise(0.05, SFX_RATE), 1800, SFX_RATE), 0.001, 1.0, 5.0)
    ring = env(mix(tone(0.7, SFX_RATE, 1318.5), [v * 0.55 for v in tone(0.7, SFX_RATE, 1975.5)],
                   [v * 0.3 for v in tone(0.7, SFX_RATE, 2637.0)]), 0.002, 1.0, 1.6)
    body = env(tone(0.12, SFX_RATE, 330, 180, "tri"), 0.002, 1.0, 3.0)
    return normalize(mix([v * 0.8 for v in crack], [v * 0.45 for v in ring], [v * 0.6 for v in body]), 0.8)


def gift():
    first = env(mix(tone(0.5, SFX_RATE, 587.33), [v * 0.4 for v in tone(0.5, SFX_RATE, 1174.66)]),
                0.02, 1.0, 1.0)
    second = silence(0.09, SFX_RATE) + env(
        mix(tone(0.6, SFX_RATE, 880.0), [v * 0.4 for v in tone(0.6, SFX_RATE, 1760.0)]),
        0.02, 1.0, 1.0)
    return normalize(mix(first, second), 0.55)


def level_up():
    out = silence(0.66, SFX_RATE)
    for i, f in enumerate((440.0, 659.25, 880.0)):
        step = env(mix(tone(0.42, SFX_RATE, f), [v * 0.35 for v in tone(0.42, SFX_RATE, f * 2)]),
                   0.015, 1.0, 1.1)
        offset = int(i * 0.1 * SFX_RATE)
        for j, v in enumerate(step):
            if offset + j < len(out):
                out[offset + j] += v
    return normalize(out, 0.6)


def door_open():
    stone = env(lowpass(noise(0.9, SFX_RATE), 700, SFX_RATE), 0.08, 1.0, 1.0)
    swell = env(tone(0.9, SFX_RATE, 70, 140, "tri"), 0.25, 1.0, 1.0)
    return normalize(mix(stone, [v * 0.6 for v in swell]), 0.62)


def ui_click():
    tick = env(highpass(noise(0.05, SFX_RATE), 1800, SFX_RATE), 0.01, 1.0, 5.0)
    body = env(tone(0.07, SFX_RATE, 660, 520), 0.02, 1.0, 3.0)
    return normalize(mix(tick, [v * 0.5 for v in body]), 0.4)


def enemy_special(seed, low, high, seconds=0.62):
    """A reproducible magical signature: shared loudness, unique contour."""
    rng = random.Random(seed)
    rumble = env(tone(seconds, SFX_RATE, low, low * 0.55, "tri"), 0.03, 1.0, 1.8)
    spark = env(highpass(noise(seconds, SFX_RATE), high, SFX_RATE), 0.25, 1.0, 2.4)
    bell_layer = env(tone(seconds, SFX_RATE, high * rng.uniform(0.55, 0.9), high * 0.35), 0.02, 1.0, 1.5)
    return normalize(mix(rumble, [v * 0.22 for v in spark], [v * 0.28 for v in bell_layer]), 0.68)


# ------------------------------------------------------------------ music ---

def ambient_night(seconds=24.0):
    """A slow drone that has to loop without a seam: every partial and every
    swell completes a whole number of cycles inside the loop, so the last
    sample runs straight back into the first."""
    n = int(seconds * MUSIC_RATE)
    out = [0.0] * n
    for freq, gain in ((55.0, 1.0), (82.5, 0.55), (110.0, 0.4), (164.81, 0.18), (220.0, 0.1)):
        cycles = round(freq * seconds)
        for i in range(n):
            out[i] += gain * math.sin(2.0 * math.pi * cycles * i / n)
    for i in range(n):
        slow = 0.62 + 0.38 * (0.5 - 0.5 * math.cos(2.0 * math.pi * 2 * i / n))
        shimmer = 0.5 - 0.5 * math.cos(2.0 * math.pi * 3 * i / n)
        out[i] *= slow
        out[i] += 0.05 * shimmer * math.sin(2.0 * math.pi * round(329.63 * seconds) * i / n)
    return normalize(lowpass_loop(out, 1800, MUSIC_RATE), 0.5)


def bell():
    """A church bell: inharmonic partials of a low strike, ringing out slowly."""
    seconds = 3.2
    out = silence(seconds, SFX_RATE)
    for ratio, gain, decay in ((1.0, 1.0, 1.0), (2.0, 0.55, 0.7), (2.4, 0.35, 0.5), (3.0, 0.25, 0.4), (4.5, 0.12, 0.25)):
        partial = env(tone(seconds, SFX_RATE, 196.0 * ratio), 0.004, decay, 1.4)
        for i, v in enumerate(partial):
            out[i] += v * gain
    strike = env(highpass(noise(0.03, SFX_RATE), 2500, SFX_RATE), 0.002, 1.0, 6.0)
    for i, v in enumerate(strike):
        out[i] += v * 0.5
    return normalize(out, 0.7)


SFX = {
    "bell": bell,
    "swing": swing,
    "hit": lambda: hit(False),
    "hit_crit": lambda: hit(True),
    "enemy_death": enemy_death,
    "player_hurt": player_hurt,
    "dash": dash,
    "prop_break": prop_break,
    "block": block,
    "parry": parry,
    "gift": gift,
    "level_up": level_up,
    "door_open": door_open,
    "ui_click": ui_click,
}

SPECIALS = {
    "possessed_villager_special": (11, 92, 780),
    "elite_possessed_special": (12, 62, 520),
    "cultist_special": (13, 105, 1250),
    "zealot_special": (14, 145, 1850),
    "fallen_guard_special": (15, 70, 640),
    "fallen_champion_special": (16, 58, 980),
    "knight_of_ash_special": (17, 48, 1180),
    "raven_special": (18, 210, 2300),
    "shade_special": (19, 125, 1600),
    "wraith_special": (20, 115, 1420),
    "blind_preacher_special": (21, 135, 1750),
    "ophanim_special": (22, 165, 2400),
}

if __name__ == "__main__":
    random.seed(7)  # the same set every run, so a regeneration is not a diff
    for name, make in SFX.items():
        write(os.path.join(SFX_DIR, name + ".wav"), make(), SFX_RATE)
    for name, spec in SPECIALS.items():
        write(os.path.join(SFX_DIR, name + ".wav"), enemy_special(*spec), SFX_RATE)
    write(os.path.join(MUSIC_DIR, "ambient_night.wav"), ambient_night(), MUSIC_RATE)
