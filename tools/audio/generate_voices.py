#!/usr/bin/env python3
"""One voice per creature in the bestiary: alert / attack / hurt / death for
every id in data/enemies, synthesised so each reads differently from the next
(a possessed villager growls, a shade whispers, a zealot chimes, the Ophanim
rings). Placeholders by design — drop a real <id>_<kind>.ogg beside the .wav
and Audio takes the real one.

Plus what the sword sounds like landing on each of them: three takes of
<id>_impact_1..3, built from the enemy's "material" in data/enemies (flesh,
cloth, mail, plate, bone, feather, spirit, gold) and seeded by its id, so two
bodies of the same material still do not hit identically. The generic
hit_<material> set is the fallback for an enemy with no clips of its own.

    python3 tools/audio/generate_voices.py
"""
import glob, json, math, os, random, struct, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
RATE = 22050
random.seed(7)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack=0.02, release=0.5):
    x = np.linspace(0, 1, n)
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    r = np.clip((1 - x) / max(release, 1e-4), 0, 1)
    return a * r


def saw(freq, seconds, glide=1.0):
    tt = t(seconds)
    f = freq * (1 + (glide - 1) * tt / max(tt[-1], 1e-6))
    phase = np.cumsum(f) / RATE
    return 2 * (phase % 1) - 1


def sine(freq, seconds, glide=1.0, vibrato=0.0, vib_rate=6.0):
    tt = t(seconds)
    f = freq * (1 + (glide - 1) * tt / max(tt[-1], 1e-6)) * (1 + vibrato * np.sin(2 * math.pi * vib_rate * tt))
    return np.sin(2 * math.pi * np.cumsum(f) / RATE)


def noise(seconds):
    return np.random.uniform(-1, 1, int(seconds * RATE))


def lowpass(x, cutoff):
    rc = 1 / (2 * math.pi * cutoff); dt = 1 / RATE; a = dt / (rc + dt)
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc); y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def am(x, rate, depth=0.6):
    return x * (1 - depth + depth * (0.5 + 0.5 * np.sin(2 * math.pi * rate * t(len(x) / RATE))))


def norm(x, peak=0.6):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(name, x):
    x = np.clip(x, -1, 1)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE)
        f.writeframes(struct.pack("<%dh" % len(x), *(int(v * 32767) for v in x)))


# ------------------------------------------------------------ timbres ---
# Each returns {kind: buffer}; recipes are deliberately unlike each other.

def growl(base=85, rough=28, cutoff=1100, size=1.0):
    g = lambda s, gl: lowpass(am(saw(base, s, gl) + 0.35 * noise(s), rough), cutoff)
    return {
        "alert": norm(g(0.28, 1.3) * env(int(0.28 * RATE), 0.05, 0.4)),
        "attack": norm(g(0.4, 0.8) * env(int(0.4 * RATE), 0.02, 0.5)),
        "hurt": norm(lowpass(saw(base * 2.6, 0.16, 0.6) + 0.5 * noise(0.16), 2500) * env(int(0.16 * RATE), 0.01, 0.6)),
        "death": norm(g(0.75 * size, 0.55) * env(int(0.75 * size * RATE), 0.02, 0.85)),
    }


def whisper(lo=500, hi=2400):
    w = lambda s, a, b: bandpass(noise(s), a, b)
    return {
        "alert": norm(w(0.3, lo, hi) * env(int(0.3 * RATE), 0.3, 0.6), 0.35),
        "attack": norm(w(0.35, lo * 2, hi * 2) * env(int(0.35 * RATE), 0.05, 0.7), 0.4),
        "hurt": norm(bandpass(noise(0.14), 1500, 4000) * env(int(0.14 * RATE), 0.01, 0.8), 0.35),
        "death": norm(w(0.9, lo, hi) * env(int(0.9 * RATE), 0.5, 0.5), 0.4),
    }


def whistle(freq=620):
    return {
        "alert": norm(sine(freq, 0.35, 1.5, 0.02) * env(int(0.35 * RATE), 0.1, 0.5), 0.4),
        "attack": norm((sine(freq, 0.4, 0.7, 0.04) + 0.3 * bandpass(noise(0.4), 800, 3000)) * env(int(0.4 * RATE), 0.05, 0.6), 0.45),
        "hurt": norm(sine(freq * 1.8, 0.15, 0.5) * env(int(0.15 * RATE), 0.01, 0.7), 0.4),
        "death": norm(sine(freq, 1.0, 0.25, 0.06, 4) * env(int(1.0 * RATE), 0.05, 0.9), 0.45),
    }


def grunt(base=140, cutoff=900):
    g = lambda s, gl: lowpass(saw(base, s, gl) + 0.15 * noise(s), cutoff)
    return {
        "alert": norm(g(0.18, 1.4) * env(int(0.18 * RATE), 0.02, 0.5)),
        "attack": norm(g(0.3, 1.1) * env(int(0.3 * RATE), 0.02, 0.4)),
        "hurt": norm(g(0.2, 0.7) * env(int(0.2 * RATE), 0.01, 0.7)),
        "death": norm(g(0.7, 0.6) * env(int(0.7 * RATE), 0.05, 0.9)),
    }


def chime(freq=880):
    bell = lambda s, f: (sine(f, s) + 0.5 * sine(f * 1.5, s) + 0.25 * sine(f * 2.01, s)) * env(int(s * RATE), 0.005, 0.95)
    return {
        "alert": norm(bell(0.5, freq), 0.45),
        "attack": norm(bell(0.6, freq * 0.75) + 0.3 * bandpass(noise(0.6), 3000, 8000) * env(int(0.6 * RATE), 0.02, 0.4), 0.5),
        "hurt": norm(bell(0.25, freq * 1.19) + bell(0.25, freq * 1.26), 0.45),
        "death": norm(bell(1.4, freq * 0.5), 0.5),
    }


def metal(base=95):
    clank = lambda s: bandpass(noise(s), 1800, 4200) * env(int(s * RATE), 0.002, 0.3)
    thud = lambda s: lowpass(sine(55, s, 0.6), 200) * env(int(s * RATE), 0.005, 0.6)
    g = lambda s, gl: lowpass(saw(base, s, gl) + 0.2 * noise(s), 700)
    return {
        "alert": norm(clank(0.25) + g(0.25, 1.2) * env(int(0.25 * RATE), 0.03, 0.5)),
        "attack": norm(g(0.35, 0.9) * env(int(0.35 * RATE), 0.02, 0.5) + 0.6 * clank(0.35)),
        "hurt": norm(clank(0.18) + 0.5 * thud(0.18)),
        "death": norm(g(0.8, 0.5) * env(int(0.8 * RATE), 0.02, 0.9) + thud(0.8) + 0.5 * clank(0.8)),
    }


def choir(root=220):
    pad = lambda s, m: sum(sine(root * r * m, s, 1.0, 0.004, 5) for r in (1, 1.26, 1.5, 2)) * env(int(s * RATE), 0.35, 0.6)
    return {
        "alert": norm(pad(0.8, 1.0), 0.4),
        "attack": norm(pad(0.6, 1.5) + 0.5 * bandpass(noise(0.6), 600, 2500) * env(int(0.6 * RATE), 0.2, 0.5), 0.45),
        "hurt": norm(pad(0.3, 1.19) * env(int(0.3 * RATE), 0.02, 0.8), 0.4),
        "death": norm(pad(1.8, 0.5), 0.45),
    }


def seraph(root=55):
    drone = lambda s, gl: (sine(root, s, gl) + 0.7 * sine(root * 2, s, gl) + 0.3 * sine(root * 4.02, s, gl) + 0.08 * sine(root * 56, s, gl, 0.01, 7)) * env(int(s * RATE), 0.2, 0.6)
    return {
        "alert": norm(drone(1.0, 1.0), 0.5),
        "attack": norm(sine(400, 0.7, 4.0) * env(int(0.7 * RATE), 0.6, 0.3) + 0.4 * drone(0.7, 1.0), 0.5),
        "hurt": norm(bandpass(noise(0.2), 2000, 6000) * env(int(0.2 * RATE), 0.005, 0.5) + 0.6 * drone(0.2, 1.0), 0.5),
        "death": norm(drone(2.2, 0.35) + 0.4 * lowpass(noise(2.2), 800) * env(int(2.2 * RATE), 0.3, 0.9), 0.55),
    }


def caw():
    pulse = lambda s, f: am(saw(f, s, 0.8) + 0.5 * bandpass(noise(s), 1500, 4000), 45, 0.8) * env(int(s * RATE), 0.02, 0.6)
    return {
        "alert": norm(np.concatenate([pulse(0.14, 720), np.zeros(int(0.05 * RATE)), pulse(0.14, 680)]), 0.45),
        "attack": norm(bandpass(noise(0.25), 1200, 5000) * env(int(0.25 * RATE), 0.1, 0.5), 0.35),  # wings
        "hurt": norm(pulse(0.1, 900), 0.45),
        "death": norm(np.concatenate([pulse(0.12, 700), pulse(0.2, 500), pulse(0.3, 380)]) , 0.45),
    }


# ------------------------------------------------------------- impacts ---
# What a blade landing on this material sounds like. Each takes a Random so a
# take is reproducible and two enemies of the same stuff still differ.
# (thump low, thump decay, clank band, clank gain, ring freq, ring gain, length)
MATERIALS = {
	"flesh":   dict(low=(95, 58), body=0.9, band=(180, 900), clank=0.35, ring=None, wet=0.5, length=0.20),
	"cloth":   dict(low=(120, 70), body=0.7, band=(250, 1600), clank=0.45, ring=None, wet=0.3, length=0.18),
	"mail":    dict(low=(140, 90), body=0.5, band=(1400, 5200), clank=0.9, ring=(1850, 0.18), wet=0.1, length=0.26),
	"plate":   dict(low=(110, 70), body=0.6, band=(900, 3600), clank=1.0, ring=(1180, 0.3), wet=0.0, length=0.34),
	"bone":    dict(low=(210, 120), body=0.6, band=(900, 4800), clank=0.8, ring=(2400, 0.12), wet=0.1, length=0.16),
	"feather": dict(low=(260, 150), body=0.35, band=(700, 4200), clank=0.5, ring=None, wet=0.2, length=0.14),
	"spirit":  dict(low=(70, 40), body=0.4, band=(300, 2600), clank=0.3, ring=(620, 0.25), wet=0.0, length=0.42),
	"gold":    dict(low=(90, 60), body=0.5, band=(1200, 4000), clank=0.7, ring=(880, 0.4), wet=0.0, length=0.5),
}


def impact(material, rng):
    """One blow on one body. The blade is the same every time; what it lands
    on is what changes — a wet thump on flesh, a clang with a tail on plate,
    a swallowed shiver on something that has no body at all."""
    spec = MATERIALS.get(material, MATERIALS["flesh"])
    wobble = rng.uniform(0.92, 1.09)
    seconds = spec["length"] * rng.uniform(0.9, 1.15)
    n = int(seconds * RATE)
    body = lowpass(sine(spec["low"][0] * wobble, seconds, spec["low"][1] / spec["low"][0]), 900)
    body = body * env(n, 0.004, 0.45) * spec["body"]
    lo, hi = spec["band"]
    clank = bandpass(noise(seconds), lo * wobble, hi * wobble) * env(n, 0.002, 0.25) * spec["clank"]
    layers = body + clank
    if spec["wet"]:
        squelch = lowpass(noise(seconds * 0.6), 420) * env(int(seconds * 0.6 * RATE), 0.01, 0.5) * spec["wet"]
        layers = layers + np.concatenate([squelch, np.zeros(n - len(squelch))])
    if spec["ring"]:
        freq, gain = spec["ring"]
        f = freq * wobble
        tail = (sine(f, seconds) + 0.5 * sine(f * 2.04, seconds) + 0.3 * sine(f * 3.11, seconds))
        layers = layers + tail * env(n, 0.002, 0.95) * gain
    return norm(layers, 0.62)


RECIPES = {
    "possessed_villager": lambda: growl(85),
    "elite_possessed": lambda: growl(62, 20, 800, 1.3),
    "shade": lambda: whisper(500, 2400),
    "wraith": lambda: whistle(620),
    "cultist": lambda: grunt(140),
    "zealot": lambda: chime(880),
    "fallen_guard": lambda: metal(95),
    "knight_of_ash": lambda: metal(70),
    "fallen_champion": lambda: metal(120),
    "blind_preacher": lambda: choir(220),
    "ophanim": lambda: seraph(55),
    "raven": lambda: caw(),
}


def thunder():
    rumble = lowpass(noise(2.6), 140) * env(int(2.6 * RATE), 0.03, 0.9)
    crack = bandpass(noise(0.25), 800, 3500) * env(int(0.25 * RATE), 0.002, 0.5)
    return norm(rumble * 1.4 + np.concatenate([crack, np.zeros(len(rumble) - len(crack))]), 0.6)


## An enemy that only overrides another (elite_possessed) inherits its material.
def materials():
    out = {}
    entries = [json.load(open(p)) for p in glob.glob(os.path.join(ROOT, "data", "enemies", "*.json"))]
    by_id = {e["id"]: e for e in entries}
    for entry in entries:
        material = entry.get("material")
        base = entry.get("extends")
        while material is None and base in by_id:
            material = by_id[base].get("material")
            base = by_id[base].get("extends")
        out[entry["id"]] = material or "flesh"
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    write("thunder", thunder())
    material_of = materials()
    made = 0
    for enemy_id, material in sorted(material_of.items()):
        recipe = RECIPES.get(enemy_id)
        if recipe is None:
            print("no recipe for", enemy_id, "- it will use the generic cues")
        else:
            for kind, buf in recipe().items():
                write(f"{enemy_id}_{kind}", buf)
                made += 1
        rng = random.Random("impact:" + enemy_id)
        for take in (1, 2, 3):
            write(f"{enemy_id}_impact_{take}", impact(material, rng))
            made += 1
    # the fallback set, for an enemy (or a mod) with no clips of its own
    for material in sorted(MATERIALS):
        rng = random.Random("material:" + material)
        for take in (1, 2, 3):
            write(f"hit_{material}_{take}", impact(material, rng))
            made += 1
    print(made, "voice and impact clips written to", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
