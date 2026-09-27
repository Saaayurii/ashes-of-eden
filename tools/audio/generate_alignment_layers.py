#!/usr/bin/env python3
"""Three quiet loops, one per path, to sit under whatever the room is playing.

The run already shows which way it leans — an aura on the body, a tint in his
light — but only if you are looking at him. This is the same information for
the ears: a layer that fades in under the music as the lead grows and is not
there at all while the counters are close (Player._update_aura decides; Audio
plays).

  grace       a choir held on an open fifth, high and unmoving. Not warm:
              certainty, which is a different thing.
  temptation  a low pulse under the floor, slow enough to be felt rather than
              heard, with a tritone that never resolves.
  will        wind through ash. No pitch at all — the path that refuses both
              answers does not get a chord.

Sixteen seconds each, looped seamlessly: the tail is crossfaded into the head
so there is no seam to hear at the join, and every partial is given a whole
number of cycles in the loop so nothing clicks. Deterministic, like every
generator here — the same script writes byte-identical files.

    python3 tools/audio/generate_alignment_layers.py
"""
import math, os, struct, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "music")
RATE = 22050
SECONDS = 16.0
## Quiet on purpose. This is meant to be noticed on the way out, not on the
## way in; Audio scales it further by how far the run leans.
PEAK = 0.24
## How much of the end is folded back over the start to hide the loop point.
CROSSFADE = 1.5


def t(seconds=SECONDS):
    return np.arange(int(seconds * RATE)) / RATE


## A partial only loops cleanly if it fits a whole number of times into the
## loop, so every frequency is nudged to the nearest one that does.
def snap(freq, seconds=SECONDS):
    cycles = max(1, round(freq * seconds))
    return cycles / seconds


def sine(freq, amp=1.0, phase=0.0, seconds=SECONDS):
    return amp * np.sin(2 * math.pi * snap(freq, seconds) * t(seconds) + phase)


def lowpass(x, cutoff):
    rc = 1 / (2 * math.pi * cutoff)
    dt = 1 / RATE
    a = dt / (rc + dt)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(seed, seconds=SECONDS):
    return np.random.default_rng(seed).uniform(-1, 1, int(seconds * RATE))


## Fold the tail over the head so the loop has no seam.
def seamless(x):
    n = int(CROSSFADE * RATE)
    if n * 2 >= len(x):
        return x
    fade = np.linspace(0.0, 1.0, n)
    head = x[:n] * fade + x[-n:] * (1.0 - fade)
    return np.concatenate([head, x[n:-n]])


def norm(x, peak=PEAK):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(name, x):
    x = np.clip(x, -1, 1)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(struct.pack("<%dh" % len(x), *(int(v * 32767) for v in x)))
    return path


# --------------------------------------------------------------- the three ---

def grace():
    """An open fifth held by a choir that does not breathe. The beating comes
    from partials a fraction apart, not from anything moving."""
    root = 196.0  # G3
    layers = np.zeros(len(t()))
    for freq, amp in [(root, 0.5), (root * 1.5, 0.42), (root * 2, 0.3),
                      (root * 3, 0.14), (root * 4, 0.08)]:
        # Two voices a hair apart: the slow beat between them is the choir.
        layers += sine(freq, amp) + sine(freq * 1.004, amp * 0.8, phase=1.1)
    breath = 0.5 + 0.5 * np.sin(2 * math.pi * snap(0.125) * t())
    return norm(layers * (0.75 + 0.25 * breath) + 0.03 * lowpass(noise(11), 900))


def temptation():
    """Felt through the floor. A tritone that never goes anywhere, and a pulse
    at walking pace."""
    root = 55.0  # A1
    layers = sine(root, 0.6) + sine(root * 2, 0.3) + sine(root * 1.414, 0.22)
    layers += sine(root * 2.83, 0.1)  # the tritone again, an octave up
    pulse = 0.55 + 0.45 * np.sin(2 * math.pi * snap(1.25) * t() - math.pi / 2)
    return norm(lowpass(layers * pulse, 420) + 0.05 * lowpass(noise(23), 200))


def will():
    """No pitch: moving air and grit. The path that answers neither side is
    not given a chord to sit on."""
    air = highpass(lowpass(noise(37), 2200), 300)
    grit = highpass(lowpass(noise(41), 5200), 1800) * 0.25
    # Gusts, slow and uneven, from two rates that do not line up.
    gust = (0.55
            + 0.28 * np.sin(2 * math.pi * snap(0.1875) * t())
            + 0.17 * np.sin(2 * math.pi * snap(0.3125) * t() + 2.2))
    return norm((air + grit) * gust)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in [("layer_grace", grace),
                       ("layer_temptation", temptation),
                       ("layer_will", will)]:
        path = write(name, seamless(make()))
        print("  %-20s %5.0f KB" % (name, os.path.getsize(path) / 1024))
    print("three alignment layers written to", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
