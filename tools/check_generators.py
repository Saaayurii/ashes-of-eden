#!/usr/bin/env python3
"""Do the generators still write what is committed?

Half this repository is produced by scripts rather than by hand — the sound
effects, the creature voices, the spoken lines, the alignment layers, the
rooms, the secret walls, the CJK subset — and every one of them claims, in its
own docstring, to be deterministic: same inputs, byte-identical output, so
regenerating is not a diff.

Nothing checked that. A generator that quietly stopped being reproducible
would only show up as an unexplained pile of modified files in somebody's
working tree, months later, with no way to tell which change caused it.

So: run a generator, ask git whether anything moved, report, put it back.

    python3 tools/check_generators.py            # the quick ones
    python3 tools/check_generators.py --all      # including the slow ones
    python3 tools/check_generators.py --list

Exit code 1 if any generator's output differs from what is committed, which
is either a broken generator or a file somebody edited by hand instead of
regenerating.
"""
import argparse, io, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## (name, argv, paths it owns, slow?). "Slow" means minutes, usually because
## it renders audio or downloads a font; those are skipped unless asked for.
GENERATORS = [
    ("sfx", ["tools/audio/generate_sfx.py"], ["assets/audio/sfx"], True),
    ("voices", ["tools/audio/generate_voices.py"], ["assets/audio/sfx"], True),
    ("alignment layers", ["tools/audio/generate_alignment_layers.py"],
     ["assets/audio/music/layer_grace.wav",
      "assets/audio/music/layer_temptation.wav",
      "assets/audio/music/layer_will.wav"], False),
    ("secret walls", ["tools/art/make_secret_walls.py"],
     ["assets/props"], False),
    ("web gate", ["tools/art/make_web_gate.py"],
     ["tools/web/shell.html"], False),
    ("store art", ["tools/art/make_store_art.py"],
     ["docs/store"], False),
    ("cjk subset", ["tools/art/make_cjk_font.py"],
     ["assets/fonts/NotoSerifSC-Subset.ttf"], True),
]


## Two ways a regenerated picture can differ without the art having changed,
## and neither is worth failing over. The promise worth keeping is
## "regenerating does not change the art", and holding every contributor's
## Pillow to the same build is not a promise this project can make.
##
##   zlib      — the pixels are identical, the bytes are not. A different
##               zlib build, nothing more.
##   rounding  — a pixel or two off by one. Pillow 12.1 and 12.3 resample a
##               1600 px panel one unit apart in one dark pixel out of half a
##               million; an actual edit to the art does not move a pixel by
##               one, it moves many by a lot. A whole image off by one is
##               still rounding; a single pixel off by two is not.
##
## Reported either way, so a drift that turns out to matter is still visible.
def same_picture(path):
    """None when the picture really changed, else why it only looks changed.

    Says *why* it could not tell, too. A check that can only answer "differs"
    sends whoever reads the log to reproduce it by hand; one that answers
    "no pixel is more than 1 apart" or "PIL is not installed" or "37 apart
    over 4,000 pixels" has already done that work.
    """
    if not path.lower().endswith(".png"):
        return None
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return "!no PIL to compare pixels with"
    committed = subprocess.run(["git", "show", "HEAD:" + path], cwd=ROOT,
                               capture_output=True)
    if committed.returncode != 0:
        return "!not in HEAD to compare against"
    try:
        before = Image.open(io.BytesIO(committed.stdout)).convert("RGBA")
        after = Image.open(os.path.join(ROOT, path)).convert("RGBA")
    except Exception as err:
        return "!will not decode: %s" % err
    if before.size != after.size:
        return "!%dx%d, was %dx%d" % (after.size + before.size)
    a = np.asarray(before).astype(np.int16)
    b = np.asarray(after).astype(np.int16)
    delta = np.abs(a - b)
    worst = int(delta.max())
    if worst == 0:
        return "zlib"
    if worst <= 1:
        return "rounding"
    return "!%d pixel(s) differ, worst by %d" % (int((delta.sum(2) > 0).sum()), worst)


def dirty(paths):
    """What git sees, split into two piles that mean different things.

    A *changed* file is a generator that no longer writes what is committed —
    the thing this script exists to catch. An *extra* file is a generator
    writing something the repository deliberately does not keep: the SFX
    generators still produce block.wav and parry.wav, which were dropped when
    real CC0 takes (block_1…block_11) replaced them, and which Audio would
    never reach anyway because numbered takes win. Worth knowing, not worth
    failing over.
    """
    out = subprocess.run(["git", "status", "--porcelain", "--"] + paths,
                         cwd=ROOT, capture_output=True, text=True, check=True)
    changed, extra = [], []
    for line in out.stdout.splitlines():
        if not line.strip():
            continue
        (extra if line.startswith("??") else changed).append(line[3:])
    return changed, extra


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="include the slow generators")
    parser.add_argument("--list", action="store_true", help="name them and stop")
    parser.add_argument("--keep", action="store_true",
                        help="leave any differences in the working tree to look at")
    args = parser.parse_args()

    if args.list:
        for name, argv, paths, slow in GENERATORS:
            print("  %-18s %-46s %s" % (name, " ".join(argv), "(slow)" if slow else ""))
        return

    chosen = [g for g in GENERATORS if args.all or not g[3]]
    skipped = len(GENERATORS) - len(chosen)

    # Refuse to run against a dirty tree: the whole check is "did git notice
    # anything", and it cannot tell our changes from somebody else's.
    already, _ = dirty(sorted({p for _, _, paths, _ in chosen for p in paths}))
    if already:
        sys.exit("check_generators: these are already modified, commit or stash first:\n  "
                 + "\n  ".join(already))

    failures = []
    for name, argv, paths, _slow in chosen:
        print("==> %s" % name, flush=True)
        result = subprocess.run([sys.executable] + argv, cwd=ROOT,
                                capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout[-2000:])
            print(result.stderr[-2000:], file=sys.stderr)
            failures.append("%s: exited %d" % (name, result.returncode))
            continue
        moved, extra = dirty(paths)
        # A reason starting with "!" is not an excuse, it is a diagnosis.
        excused = {m: same_picture(m) for m in moved}
        recompressed = [m for m, why in excused.items() if why == "zlib"]
        rounded = [m for m, why in excused.items() if why == "rounding"]
        real = ["%s%s" % (m, "  (%s)" % why[1:] if why else "")
                for m, why in excused.items() if why is None or why.startswith("!")]
        if real:
            failures.append("%s: %d file(s) differ from what is committed:\n      %s"
                            % (name, len(real), "\n      ".join(real[:10])))
        elif not moved:
            print("    reproduced exactly")
        if recompressed:
            print("    (%d PNG(s) identical in pixels, different in bytes — another "
                  "zlib: %s)" % (len(recompressed),
                                 ", ".join(os.path.basename(r) for r in recompressed[:3])))
        if rounded:
            print("    (%d PNG(s) off by one somewhere — another Pillow's "
                  "resampling: %s)" % (len(rounded),
                                       ", ".join(os.path.basename(r) for r in rounded[:3])))
        if extra:
            print("    (writes %d file(s) the repository does not keep: %s)"
                  % (len(extra), ", ".join(os.path.basename(e) for e in extra[:4])))
        if not args.keep:
            if moved:
                subprocess.run(["git", "checkout", "--"] + paths, cwd=ROOT, check=False)
            for path in extra:
                os.remove(os.path.join(ROOT, path))

    if skipped:
        print("\n%d slow generator(s) skipped; --all runs them too" % skipped)
    if failures:
        print("\nFAILED")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print("\nevery generator reproduced its committed output")


if __name__ == "__main__":
    main()
