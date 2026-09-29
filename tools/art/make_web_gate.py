#!/usr/bin/env python3
"""Build the web loading page from the game's own art.

The browser build opens on a page that is not the game yet: the engine has
not started, the 100 MB pack has not arrived, and the person is looking at
whatever HTML we put in front of them. Godot's default there is a grey box
with a bar. The first version of this shell was the menu's colours and no
picture, which is better but still a page about nothing.

So this puts the game on it. Not new art — the panel behind the loading
screen is `graveyard_moon_wide`, the same painted graveyard a player reaches
in chapter one, and the figure standing on it is Elian's own idle sheet, the
same frames the game animates. The loading page and the first screen of the
game are the same place, drawn by the same hand.

Both are inlined into the HTML as data URIs. That is deliberate: the shell is
the one file Godot's exporter copies, so anything referenced by a path beside
it would have to be copied by every packaging route separately (Pages, the
itch.io upload, a plain unzip) and would 404 the day one of them forgot. One
self-contained file cannot be half-deployed. The cost is roughly 200 KB of
base64, paid before a download two orders of magnitude larger.

    python3 tools/art/make_web_gate.py

Deterministic: same art in, byte-identical `tools/web/shell.html` out, which
is what tools/check_generators.py verifies. Edit the template, not the HTML.
"""
import base64, io, os, sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATE = os.path.join(ROOT, "tools", "web", "shell.template.html")
OUT = os.path.join(ROOT, "tools", "web", "shell.html")

BACKDROP = os.path.join(ROOT, "assets", "levels", "graveyard_moon_wide.png")

## Two states, and the page uses both: standing while it waits for the click,
## walking while the pack downloads. Same sheet, same cell, one image.
ANIMS = [("idle", "elian_idle", 4), ("walk", "elian_walk", 8)]

## Wide enough to look painted rather than upscaled on a laptop, small enough
## that the page it is embedded in still arrives in one breath. The panel is
## 1600 px; going under half of that starts to lose the far headstones.
BACKDROP_WIDTH = 1100
BACKDROP_QUALITY = 72

## Pixel art is enlarged by whole numbers or not at all. Six puts a 44 px
## figure at 264 px, which reads at arm's length without swallowing a phone.
SPRITE_SCALE = 6


def frames(name, count):
    """The frames of one 128x64 strip, as images."""
    sheet = Image.open(os.path.join(ROOT, "assets", "sprites", name + ".png"))
    return [sheet.crop((i * 128, 0, (i + 1) * 128, 64)) for i in range(count)]


def shared_cell(strips):
    """One rectangle that holds every frame of every animation.

    Cropping each frame to its own bounding box would centre each one
    separately, and the figure would jitter half a pixel per frame and jump
    when the animation changed. A single rectangle, used for all of them,
    keeps his feet where they are.
    """
    boxes = [f.getbbox() for strip in strips for f in strip]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def sprite_sheet():
    """Every animation as rows of one PNG, plus the numbers CSS needs."""
    strips = [frames(src, count) for _, src, count in ANIMS]
    cell = shared_cell(strips)
    w, h = cell[2] - cell[0], cell[3] - cell[1]
    wide = max(len(s) for s in strips)

    sheet = Image.new("RGBA", (wide * w, len(strips) * h), (0, 0, 0, 0))
    for row, strip in enumerate(strips):
        for col, frame in enumerate(strip):
            sheet.paste(frame.crop(cell), (col * w, row * h))

    sheet = sheet.resize((sheet.width * SPRITE_SCALE, sheet.height * SPRITE_SCALE),
                         Image.NEAREST)
    buf = io.BytesIO()
    # optimize, and no ancillary chunks: Pillow writes no timestamp here, so
    # the bytes depend on the pixels alone.
    sheet.save(buf, "PNG", optimize=True)
    return buf.getvalue(), w * SPRITE_SCALE, h * SPRITE_SCALE


def backdrop():
    """The painted panel, web-sized, as WebP."""
    art = Image.open(BACKDROP).convert("RGB")
    height = round(art.height * BACKDROP_WIDTH / art.width)
    art = art.resize((BACKDROP_WIDTH, height), Image.LANCZOS)
    buf = io.BytesIO()
    art.save(buf, "WEBP", quality=BACKDROP_QUALITY, method=6)
    return buf.getvalue()


def data_uri(mime, payload):
    return "data:%s;base64,%s" % (mime, base64.b64encode(payload).decode("ascii"))


def main():
    if not os.path.exists(TEMPLATE):
        sys.exit("missing template: " + TEMPLATE)

    sheet, cell_w, cell_h = sprite_sheet()
    panel = backdrop()

    with open(TEMPLATE, "r", encoding="utf-8") as handle:
        html = handle.read()

    for marker, value in [
        ("__BACKDROP__", data_uri("image/webp", panel)),
        ("__SPRITE__", data_uri("image/png", sheet)),
        ("__CELL_W__", str(cell_w)),
        ("__CELL_H__", str(cell_h)),
        ("__IDLE_FRAMES__", str(ANIMS[0][2])),
        ("__WALK_FRAMES__", str(ANIMS[1][2])),
        ("__SHEET_W__", str(max(count for _, _, count in ANIMS) * cell_w)),
    ]:
        if marker not in html:
            sys.exit("template no longer uses " + marker)
        html = html.replace(marker, value)

    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(html)

    print("wrote %s — backdrop %d KB, sprite %d KB, cell %dx%d" %
          (os.path.relpath(OUT, ROOT), len(panel) // 1024, len(sheet) // 1024,
           cell_w, cell_h))


if __name__ == "__main__":
    main()
