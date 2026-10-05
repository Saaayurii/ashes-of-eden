#!/usr/bin/env python3
"""The Chinese glyphs the game actually uses, and not one more.

The two faces the game is set in — Forum and EB Garamond — have no CJK at
all. On a desktop that goes unnoticed: Godot falls back to a system font and
the Chinese reads fine. A Web export has no system fonts, so the same build
in a browser shows tofu where the Chinese should be, which is the whole
zh_CN translation invisible.

Shipping a whole CJK face would fix it and cost 18 MB in a build already too
heavy for a browser. Chapter I uses 947 distinct characters. So this subsets
one down to exactly what `localization/strings.csv` needs — a couple of
hundred kilobytes — and `assets/ui/theme.tres` puts the result in the
fallback chain ahead of the system font.

The face is **Noto Serif SC**, not Sans. The game is set in EB Garamond and
Forum — an old-style serif and Roman capitals — and a grotesque beside them
reads as a different project's text pasted in. Serif SC is Song, which is
what a Chinese reader expects where a Western reader expects a serif. It is
also instanced to a regular weight: the variable original defaults to Thin,
which is what the first version of this shipped and why the Chinese looked
faint next to the Cyrillic.

The catch is the obvious one: add a line of Chinese with a character not in
the subset and it renders as tofu. `validate_data.gd` checks for that and
fails, so the rule is simple — change the Chinese text, run this again.

    python3 tools/art/make_cjk_font.py

Noto Sans SC is SIL OFL 1.1 (assets/CREDITS.md). The downloaded original
lives in tools/art/.cache/ and is git-ignored; the subset is committed.
"""
import csv, os, subprocess, sys, unicodedata
from urllib.request import urlopen

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STRINGS = os.path.join(ROOT, "localization", "strings.csv")
CACHE = os.path.join(ROOT, "tools", "art", ".cache")
SOURCE = os.path.join(CACHE, "NotoSerifSC.ttf")
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSerifSC-Subset.ttf")
LICENCE = os.path.join(ROOT, "assets", "fonts", "OFL-NotoSerifSC.txt")
URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
## Regular. EB Garamond next to it is a book weight; anything lighter reads as
## a different voice rather than the same one in another script.
WEIGHT = 400
LICENCE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/OFL.txt"

## Everything the Latin faces already cover is left to them — this font is
## only ever reached as a fallback. What it must carry is anything above
## ASCII that appears in the Chinese column: the characters themselves, and
## the full-width punctuation that comes with them.
def wanted():
    chars = set()
    with open(STRINGS, encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            for ch in (row.get("zh_CN") or ""):
                if ord(ch) > 0x2000:
                    chars.add(ch)
    # A few that the UI composes itself rather than reading out of the CSV.
    chars.update("0123456789%·—…()（）：:")
    # ...and the marks the UI draws in every language, which neither Latin
    # face has: the bestiary's tree and deeds, resonances, the map's legend,
    # the move list's done and new. A Web build has no system font to find
    # them in, and validate_data.gd fails on a mark that is in no shipped font.
    chars.update("●○◆◇└×✚†✓★")
    return chars


def fetch(url, path, what):
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("  downloading %s" % what)
    with urlopen(url) as response, open(path, "wb") as out:
        out.write(response.read())


## fontTools stamps head.modified with the moment it ran, and the checksum it
## writes afterwards covers that stamp, so two runs of the same script produce
## files that differ in a handful of bytes. The font is identical to read and
## different to git, which is the worst of both: a regeneration looks like a
## change and a real change hides among the noise. Pin the timestamps to the
## epoch the rest of the toolchain uses and the output becomes byte-stable.
## (tools/check_generators.py is what noticed.)
def _make_reproducible(path):
    from fontTools.ttLib import TTFont
    # recalcTimestamp defaults to True, which puts the current time back into
    # head.modified on save — undoing the very thing this function is for, and
    # leaving three bytes of checksum different between runs.
    font = TTFont(path, recalcTimestamp=False)
    head = font["head"]
    head.created = 0
    head.modified = 0
    font.save(path)


def main():
    try:
        import fontTools  # noqa: F401
    except ImportError:
        sys.exit("make_cjk_font: pip install fonttools")

    fetch(URL, SOURCE, "Noto Serif SC (once)")
    fetch(LICENCE_URL, LICENCE, "its OFL licence")

    chars = wanted()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # Pin the weight first. Left variable, the axis defaults to its minimum —
    # Thin — and the Chinese comes out visibly lighter than the Latin beside
    # it, which is exactly what happened the first time.
    subprocess.run([
        sys.executable, "-m", "fontTools.varLib.instancer", SOURCE,
        "wght=%d" % WEIGHT, "--output=" + SOURCE + ".static.ttf",
    ], check=True)
    subprocess.run([
        sys.executable, "-m", "fontTools.subset", SOURCE + ".static.ttf",
        "--text=" + "".join(sorted(chars)),
        "--output-file=" + OUT,
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
        "--name-IDs=0,1,2,3,4,5,6,13,14",  # keep the OFL notice inside the file
        "--drop-tables+=DSIG",
    ], check=True)

    os.remove(SOURCE + ".static.ttf")
    _make_reproducible(OUT)
    size = os.path.getsize(OUT)
    print("%d characters -> %s (%.0f KB, from %.0f MB)"
          % (len(chars), os.path.relpath(OUT, ROOT), size / 1024,
             os.path.getsize(SOURCE) / 1e6))


if __name__ == "__main__":
    main()
