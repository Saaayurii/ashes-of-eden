#!/usr/bin/env python3
"""The Chinese glyphs the game actually uses, and not one more.

The two faces the game is set in — Forum and EB Garamond — have no CJK at
all. On a desktop that goes unnoticed: Godot falls back to a system font and
the Chinese reads fine. A Web export has no system fonts, so the same build
in a browser shows tofu where the Chinese should be, which is the whole
zh_CN translation invisible.

Shipping Noto Sans SC whole would fix it and cost 18 MB in a build that is
already too heavy for a browser. Chapter I uses 947 distinct characters. So
this subsets the font down to exactly what `localization/strings.csv` needs
— a couple of hundred kilobytes — and `assets/ui/theme.tres` puts the result
in the fallback chain ahead of the system font.

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
SOURCE = os.path.join(CACHE, "NotoSansSC.ttf")
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Subset.ttf")
LICENCE = os.path.join(ROOT, "assets", "fonts", "OFL-NotoSansSC.txt")
URL = "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
LICENCE_URL = "https://github.com/google/fonts/raw/main/ofl/notosanssc/OFL.txt"

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
    return chars


def fetch(url, path, what):
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("  downloading %s" % what)
    with urlopen(url) as response, open(path, "wb") as out:
        out.write(response.read())


def main():
    try:
        import fontTools  # noqa: F401
    except ImportError:
        sys.exit("make_cjk_font: pip install fonttools")

    fetch(URL, SOURCE, "Noto Sans SC (18 MB, once)")
    fetch(LICENCE_URL, LICENCE, "its OFL licence")

    chars = wanted()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subprocess.run([
        sys.executable, "-m", "fontTools.subset", SOURCE,
        "--text=" + "".join(sorted(chars)),
        "--output-file=" + OUT,
        # Keep the variable axis: the theme asks for a weight, and a static
        # instance would ignore it. Drop everything else that is not drawing.
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
        "--name-IDs=0,1,2,3,4,5,6,13,14",  # keep the OFL notice inside the file
        "--drop-tables+=DSIG",
    ], check=True)

    size = os.path.getsize(OUT)
    print("%d characters -> %s (%.0f KB, from %.0f MB)"
          % (len(chars), os.path.relpath(OUT, ROOT), size / 1024,
             os.path.getsize(SOURCE) / 1e6))


if __name__ == "__main__":
    main()
