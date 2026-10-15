#!/usr/bin/env python3
"""Generates the placeholder half of the sound set in assets/audio/.

The real clips are built by build_audio.py from CC0 sources; these stand in
where no real clip has been chosen yet, so every moment in scripts/autoload/audio.gd
makes *some* noise. Synthesised with the standard library, so the repository
owns them outright and anyone can re-roll them. A name that has both a real and
a generated clip takes the real one (see Audio._load_clips), which is what makes
replacing a placeholder a matter of dropping an .ogg beside it.

    python3 tools/audio/generate_sfx.py
    python3 tools/audio/generate_sfx.py liquids   # only the pools' sounds (LIQUID_SFX)
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


# ---------------------------------------------------------------- liquids ---
# The pools of data/liquids.json (scripts/rooms/hazard.gd): what a body makes
# going into water, lava and bog, and the low loops a pool breathes near it.
# water_bubble and bog_squelch are real CC0 takes (tools/audio/sfx_manifest.json);
# the rest stand in here. Each take reseeds from its own name (liquid_sfx), so
# adding one never re-rolls another.

def place(out, piece, at=0.0, gain=1.0):
    """Lays `piece` into `out` from `at` seconds, cutting what runs past the end."""
    offset = int(at * SFX_RATE)
    for i, v in enumerate(piece):
        if 0 <= offset + i < len(out):
            out[offset + i] += v * gain
    return out


def bloop(seconds, f0, f1, decay=2.5):
    """A drop's plink or a bubble's bloop: a sine sweeping up, gone at once."""
    return env(tone(seconds, SFX_RATE, f0, f1), 0.02, 1.0, decay)


def splash():
    out = silence(0.55, SFX_RATE)
    body = highpass(lowpass(noise(0.32, SFX_RATE), random.uniform(2200, 3200), SFX_RATE), 300, SFX_RATE)
    place(out, env(body, 0.03, 1.0, 2.6))
    place(out, env(tone(0.14, SFX_RATE, random.uniform(260, 330), 110, "tri"), 0.01, 1.0, 2.5), 0.0, 0.6)
    for _ in range(random.randint(3, 5)):
        f = random.uniform(700, 1300)
        place(out, bloop(0.05, f, f * 1.6), random.uniform(0.08, 0.42), random.uniform(0.12, 0.3))
    return normalize(out, 0.72)


def splash_big():
    out = silence(1.0, SFX_RATE)
    body = lowpass(noise(0.75, SFX_RATE), random.uniform(1300, 1800), SFX_RATE)
    place(out, env(body, 0.02, 1.0, 1.6))
    spray = highpass(noise(0.5, SFX_RATE), 2500, SFX_RATE)
    place(out, env(spray, 0.05, 1.0, 2.0), 0.03, 0.35)
    place(out, env(tone(0.35, SFX_RATE, random.uniform(130, 160), 45, "tri"), 0.005, 1.0, 2.0), 0.0, 0.9)
    for _ in range(random.randint(7, 10)):  # the water coming back down
        f = random.uniform(500, 1200)
        place(out, bloop(0.06, f, f * 1.5), random.uniform(0.25, 0.85), random.uniform(0.1, 0.25))
    return normalize(out, 0.8)


def splash_out():
    out = silence(0.7, SFX_RATE)
    slosh = lowpass(noise(0.35, SFX_RATE), random.uniform(900, 1400), SFX_RATE)
    place(out, env(slosh, 0.3, 1.0, 1.8))
    for _ in range(random.randint(4, 6)):  # what runs off him
        f = random.uniform(1100, 1900)
        place(out, bloop(0.035, f, f * 1.4, 3.0), random.uniform(0.2, 0.62), random.uniform(0.15, 0.35))
    return normalize(out, 0.6)


def wade():
    out = silence(0.32, SFX_RATE)
    slosh = lowpass(noise(0.26, SFX_RATE), random.uniform(700, 1100), SFX_RATE)
    place(out, env(slosh, 0.18, 1.0, 2.0))
    place(out, env(highpass(noise(0.14, SFX_RATE), 1800, SFX_RATE), 0.2, 1.0, 2.5), 0.03, 0.25)
    f = random.uniform(380, 560)
    place(out, bloop(0.06, f, f * 1.5), random.uniform(0.05, 0.12), 0.3)
    return normalize(out, 0.55)


def crackle(seconds, density, cutoff=3500):
    """Sparse clicks: the spit of a burning surface."""
    out = silence(seconds, SFX_RATE)
    for _ in range(int(seconds * density)):
        click = env(highpass(noise(0.006, SFX_RATE), cutoff, SFX_RATE), 0.01, 1.0, 4.0)
        place(out, click, random.uniform(0.0, seconds), random.uniform(0.2, 1.0))
    return out


def sizzle():
    seconds = 0.8
    out = silence(seconds, SFX_RATE)
    hiss = highpass(lowpass(noise(seconds, SFX_RATE), 7000, SFX_RATE), random.uniform(2600, 3400), SFX_RATE)
    place(out, env(hiss, 0.02, 1.0, 1.3), 0.0, 0.8)
    place(out, env(crackle(seconds, 70), 0.01, 1.0, 1.2), 0.0, 0.7)
    place(out, env(tone(0.1, SFX_RATE, 140, 70, "tri"), 0.01, 1.0, 3.0), 0.0, 0.5)
    return normalize(out, 0.62)


def lava_splash():
    seconds = 1.2
    out = silence(seconds, SFX_RATE)
    gloop = lowpass(noise(0.6, SFX_RATE), random.uniform(380, 520), SFX_RATE)
    place(out, env(gloop, 0.03, 1.0, 1.6), 0.0, 1.2)
    place(out, env(tone(0.5, SFX_RATE, random.uniform(85, 105), 38, "tri"), 0.01, 1.0, 1.8), 0.0, 1.0)
    for _ in range(3):  # thick blobs landing back
        f = random.uniform(70, 110)
        place(out, bloop(0.12, f, f * 2.2, 2.0), random.uniform(0.25, 0.7), 0.5)
    hiss = highpass(noise(1.0, SFX_RATE), 3000, SFX_RATE)
    place(out, env(hiss, 0.15, 1.0, 1.0), 0.1, 0.22)
    place(out, env(crackle(1.0, 40), 0.1, 1.0, 1.0), 0.1, 0.4)
    return normalize(out, 0.8)


def lava_bubble():
    out = silence(0.4, SFX_RATE)
    f = random.uniform(55, 80)
    place(out, env(tone(0.22, SFX_RATE, f, f * 2.8), 0.25, 1.0, 1.6), 0.0, 1.0)  # the dome swelling
    pop = lowpass(noise(0.05, SFX_RATE), 900, SFX_RATE)
    at = random.uniform(0.17, 0.21)
    place(out, env(pop, 0.01, 1.0, 3.5), at, 0.9)
    place(out, env(crackle(0.15, 60, 4000), 0.01, 1.0, 2.0), at, 0.25)
    return normalize(out, 0.66)


def bog_bubble():
    out = silence(0.45, SFX_RATE)
    f = random.uniform(120, 170)
    n = int(0.25 * SFX_RATE)
    wob = []
    phase = 0.0
    for i in range(n):  # a gassy, wobbling rise
        t = i / n
        freq = f * (1 + 1.2 * t) * (1 + 0.08 * math.sin(2 * math.pi * 22 * t))
        phase += 2 * math.pi * freq / SFX_RATE
        wob.append(math.sin(phase))
    place(out, env(wob, 0.15, 1.0, 1.8))
    at = random.uniform(0.2, 0.25)
    place(out, env(lowpass(noise(0.08, SFX_RATE), 650, SFX_RATE), 0.02, 1.0, 2.5), at, 1.1)
    place(out, env(lowpass(noise(0.15, SFX_RATE), 300, SFX_RATE), 0.2, 1.0, 1.5), at + 0.03, 0.6)
    return normalize(out, 0.6)


def seamless(buf, seconds, fade):
    """The loop's own tail laid over its head, equal-power: generate `seconds` + `fade`
    and fold the extra back, so the last sample runs straight into the first."""
    n, x = int(seconds * SFX_RATE), int(fade * SFX_RATE)
    out = buf[:n]
    for i in range(x):
        t = i / x
        out[i] = buf[i] * math.sin(t * math.pi / 2) + buf[n + i] * math.cos(t * math.pi / 2)
    return out


def swell(n, rate_hz, depth, phase=0.0):
    return [1.0 - depth + depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate_hz * i / SFX_RATE + phase)) for i in range(n)]


def loop_base(seconds, cutoff, wobble):
    total = seconds + 1.0
    n = int(total * SFX_RATE)
    bed = lowpass(lowpass(noise(total, SFX_RATE), cutoff, SFX_RATE), cutoff, SFX_RATE)
    a, b = swell(n, wobble, 0.5), swell(n, wobble * 2.37, 0.3, 1.3)
    return [v * x * y for v, x, y in zip(bed, a, b)], total


def water_loop(seconds=6.0):
    bed, total = loop_base(seconds, 520, 0.31)
    trickle = highpass(lowpass(noise(total, SFX_RATE), 4000, SFX_RATE), 1500, SFX_RATE)
    bed = mix(bed, [v * 0.06 * w for v, w in zip(trickle, swell(len(trickle), 0.53, 0.8))])
    for _ in range(int(seconds * 1.6)):  # lapping and the odd bloop
        f = random.uniform(380, 900)
        place(bed, bloop(0.07, f, f * 1.5), random.uniform(0.0, total - 0.1), random.uniform(0.05, 0.14))
    return normalize(seamless(bed, seconds, 1.0), 0.5)


def lava_loop(seconds=7.0):
    bed, total = loop_base(seconds, 160, 0.17)
    bed = mix(bed, [v * 0.12 for v in crackle(total, 18, 3000)])
    for _ in range(int(seconds * 0.9)):  # thick gloops rising through it
        f = random.uniform(50, 80)
        place(bed, env(tone(0.22, SFX_RATE, f, f * 2.6), 0.3, 1.0, 1.6), random.uniform(0.0, total - 0.3), 0.35)
    return normalize(seamless(bed, seconds, 1.0), 0.5)


def bog_loop(seconds=7.0):
    bed, total = loop_base(seconds, 300, 0.13)
    for _ in range(int(seconds * 0.7)):  # gas finding its way up
        f = random.uniform(110, 170)
        place(bed, bloop(0.18, f, f * 2.0, 1.8), random.uniform(0.0, total - 0.2), random.uniform(0.18, 0.3))
    return normalize(seamless(bed, seconds, 1.0), 0.48)


def blood_loop(seconds=6.0):
    bed, total = loop_base(seconds, 240, 0.21)
    beat = 0.0
    while beat < total - 0.3:  # a slow, thick pulse under it, felt more than heard
        place(bed, env(tone(0.16, SFX_RATE, 58, 40, "tri"), 0.08, 1.0, 2.2), beat, 0.22)
        place(bed, env(tone(0.14, SFX_RATE, 52, 38, "tri"), 0.08, 1.0, 2.2), beat + 0.28, 0.14)
        beat += 1.5
    for _ in range(int(seconds * 0.8)):  # viscous drips
        f = random.uniform(260, 420)
        place(bed, bloop(0.08, f, f * 1.3, 2.0), random.uniform(0.0, total - 0.1), 0.08)
    return normalize(seamless(bed, seconds, 1.0), 0.48)


## name -> (maker, takes). Takes are <name>_1..n; a loop (takes 0) is the bare name.
LIQUID_SFX = {
    "splash": (splash, 4),
    "splash_big": (splash_big, 3),
    "splash_out": (splash_out, 3),
    "wade": (wade, 4),
    "sizzle": (sizzle, 3),
    "lava_splash": (lava_splash, 3),
    "lava_bubble": (lava_bubble, 4),
    "bog_bubble": (bog_bubble, 3),
    "water_loop": (water_loop, 0),
    "lava_loop": (lava_loop, 0),
    "bog_loop": (bog_loop, 0),
    "blood_loop": (blood_loop, 0),
}


def liquid_sfx():
    import zlib
    for name, (make, takes) in LIQUID_SFX.items():
        for take in range(1, takes + 1) if takes else [0]:
            file_name = "%s_%d" % (name, take) if takes else name
            random.seed(zlib.crc32(file_name.encode()))
            write(os.path.join(SFX_DIR, file_name + ".wav"), make(), SFX_RATE)


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


def rustle(seed):
    """Leaves shaken on a branch: a soft bed of air and a scatter of tiny
    clicks, each take its own (a private generator, so adding a take does not
    re-roll every clip after it)."""
    rng = random.Random(seed)
    n = int(rng.uniform(0.45, 0.6) * SFX_RATE)
    air = env(highpass(lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], rng.uniform(5200, 6800), SFX_RATE), 900, SFX_RATE),
              0.08, 1.0, 1.6)
    out = [v * 0.5 for v in air]
    for _ in range(rng.randint(24, 34)):
        start = int(rng.uniform(0.0, 0.8) * n)
        length = int(rng.uniform(0.004, 0.012) * SFX_RATE)
        gain = rng.uniform(0.3, 1.0) * (1.0 - start / n)
        click = env(highpass([rng.uniform(-1.0, 1.0) for _ in range(length)], 2200, SFX_RATE), 0.05, 1.0, 3.0)
        for i, v in enumerate(click):
            if start + i < n:
                out[start + i] += v * gain
    return normalize(out, 0.5)


def rustle_sfx():
    """The leaves of a struck or brushed tree (scripts/rooms/foliage.gd), three takes."""
    for take in (1, 2, 3):
        write(os.path.join(SFX_DIR, "rustle_%d.wav" % take), rustle(30 + take), SFX_RATE)


def wingbeat(seed):
    """A bird taking off: a few quick beats of air, each a whump of low noise
    over a feathery hiss, slowing and thinning as it climbs away. Several
    birds of a flock overlap a little, so a take holds two or three wings."""
    rng = random.Random(seed)
    seconds = rng.uniform(0.75, 0.95)
    n = int(seconds * SFX_RATE)
    out = [0.0] * n
    for bird in range(rng.randint(2, 3)):
        t = rng.uniform(0.0, 0.12) * bird
        gap = rng.uniform(0.075, 0.095)
        gain = 1.0 - 0.25 * bird
        beat = 0
        while t < seconds - 0.08:
            length = int(rng.uniform(0.05, 0.07) * SFX_RATE)
            whump = env(lowpass([rng.uniform(-1.0, 1.0) for _ in range(length)], rng.uniform(380, 520), SFX_RATE), 0.25, 1.0, 2.2)
            hiss = env(highpass([rng.uniform(-1.0, 1.0) for _ in range(length)], 2600, SFX_RATE), 0.35, 1.0, 2.6)
            fade = gain * max(0.15, 1.0 - beat * 0.11) * rng.uniform(0.8, 1.0)
            start = int(t * SFX_RATE)
            for i in range(length):
                if start + i < n:
                    out[start + i] += (whump[i] * 2.2 + hiss[i] * 0.22) * fade
            beat += 1
            t += gap * (1.0 + beat * 0.06)
    return normalize(out, 0.55)


def wingbeat_sfx():
    """Ravens leaving a painted tree (scripts/rooms/foliage.gd), three takes."""
    for take in (1, 2, 3):
        write(os.path.join(SFX_DIR, "wingbeat_%d.wav" % take), wingbeat(60 + take), SFX_RATE)


def links(rng, seconds, count, cutoff):
    """A run of iron links knocking together: short bright ticks, unevenly spaced."""
    out = silence(seconds, SFX_RATE)
    for _ in range(count):
        tick = env(mix(highpass(noise(0.05, SFX_RATE), cutoff, SFX_RATE),
                       [v * 0.4 for v in tone(0.05, SFX_RATE, rng.uniform(1900, 3100))]), 0.001, 1.0, 6.0)
        place(out, tick, rng.uniform(0.0, seconds - 0.06), rng.uniform(0.25, 0.8))
    return out


def chain_strain(rng):
    """A chain pulled to its end (scripts/combat/tether.gd): links rattle, then a dull iron groan."""
    out = links(rng, 0.55, 9, 2400)
    groan = env(tone(0.45, SFX_RATE, rng.uniform(95, 120), rng.uniform(70, 85), "tri"), 0.04, 1.0, 1.8)
    place(out, groan, 0.08, 0.7)
    return normalize(out, 0.6)


def chain_snap(rng):
    """A chain caught short: one hard clank and the links ringing after it."""
    out = links(rng, 0.42, 6, 3000)
    clank = env(mix(lowpass(noise(0.07, SFX_RATE), 2600, SFX_RATE),
                    [v * 0.5 for v in tone(0.25, SFX_RATE, rng.uniform(560, 720))]), 0.001, 1.0, 3.2)
    place(out, clank, 0.0, 1.0)
    return normalize(out, 0.7)


def chain_unlock(rng):
    """The abbot's key in a ring (scripts/rooms/chain_ring.gd): a turn, a click, the chain falling."""
    out = silence(0.9, SFX_RATE)
    turn = env(lowpass(noise(0.16, SFX_RATE), 1400, SFX_RATE), 0.03, 1.0, 1.5)
    click = env(mix(highpass(noise(0.03, SFX_RATE), 2500, SFX_RATE),
                    [v * 0.6 for v in tone(0.12, SFX_RATE, rng.uniform(1300, 1500))]), 0.001, 1.0, 4.0)
    place(out, turn, 0.0, 0.5)
    place(out, click, 0.17, 0.9)
    place(out, links(rng, 0.6, 10, 2000), 0.28, 0.8)
    return normalize(out, 0.65)


def censer_swing(rng):
    """A censer on its chain: a soft whoosh through the air and the links ticking."""
    whoosh = env(lowpass(noise(0.5, SFX_RATE), rng.uniform(900, 1300), SFX_RATE), 0.18, 1.0, 1.6)
    return normalize(mix([v * 0.8 for v in whoosh], links(rng, 0.5, 4, 2800)), 0.5)


def chain_sfx():
    """Chapter VI's chains, three takes each, from their own seeds."""
    for name, make, base in (("chain_strain", chain_strain, 80), ("chain_snap", chain_snap, 90),
                             ("chain_unlock", chain_unlock, 100), ("censer_swing", censer_swing, 110)):
        for take in (1, 2, 3):
            write(os.path.join(SFX_DIR, "%s_%d.wav" % (name, take)), make(random.Random(base + take)), SFX_RATE)


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

def lamp_light(seed):
    """A lamp of Tyre bought (scripts/rooms/lamp.gd): the flint's tick, the oil
    catching in a soft breath of air, a few spits of the wick after it."""
    rng = random.Random(seed)
    seconds = rng.uniform(0.7, 0.85)
    out = silence(seconds, SFX_RATE)
    tick = env(highpass([rng.uniform(-1.0, 1.0) for _ in range(int(0.012 * SFX_RATE))], 3000, SFX_RATE), 0.02, 1.0, 4.0)
    place(out, tick, 0.0, 0.9)
    n = int(0.5 * SFX_RATE)
    breath = env(lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], rng.uniform(900, 1300), SFX_RATE), 0.25, 1.0, 1.8)
    place(out, breath, 0.03, 0.8)
    glow = env(tone(0.45, SFX_RATE, rng.uniform(150, 175), rng.uniform(190, 215), "tri"), 0.3, 1.0, 2.0)
    place(out, glow, 0.05, 0.12)
    for _ in range(rng.randint(4, 7)):
        spit = env(highpass([rng.uniform(-1.0, 1.0) for _ in range(int(0.006 * SFX_RATE))], 2400, SFX_RATE), 0.05, 1.0, 3.0)
        place(out, spit, rng.uniform(0.15, seconds - 0.05), rng.uniform(0.15, 0.4))
    return normalize(out, 0.55)


def lamp_sfx():
    """A lamp of Tyre lit (scripts/rooms/lamp.gd), three takes."""
    for take in (1, 2, 3):
        write(os.path.join(SFX_DIR, "lamp_light_%d.wav" % take), lamp_light(90 + take), SFX_RATE)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["liquids"]:  # only the pools' sounds: python3 tools/audio/generate_sfx.py liquids
        liquid_sfx()
        sys.exit(0)
    if sys.argv[1:] == ["rustle"]:  # only the trees' leaves: python3 tools/audio/generate_sfx.py rustle
        rustle_sfx()
        sys.exit(0)
    if sys.argv[1:] == ["lamp"]:  # only the lamps of Tyre: python3 tools/audio/generate_sfx.py lamp
        lamp_sfx()
        sys.exit(0)
    if sys.argv[1:] == ["chains"]:  # only chapter VI's chains: python3 tools/audio/generate_sfx.py chains
        chain_sfx()
        sys.exit(0)
    if sys.argv[1:] == ["wingbeat"]:  # only the ravens' wings: python3 tools/audio/generate_sfx.py wingbeat
        wingbeat_sfx()
        sys.exit(0)
    random.seed(7)  # the same set every run, so a regeneration is not a diff
    for name, make in SFX.items():
        write(os.path.join(SFX_DIR, name + ".wav"), make(), SFX_RATE)
    for name, spec in SPECIALS.items():
        write(os.path.join(SFX_DIR, name + ".wav"), enemy_special(*spec), SFX_RATE)
    write(os.path.join(MUSIC_DIR, "ambient_night.wav"), ambient_night(), MUSIC_RATE)
    liquid_sfx()
    rustle_sfx()
    wingbeat_sfx()
    lamp_sfx()
    chain_sfx()
