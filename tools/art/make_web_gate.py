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
self-contained file cannot be half-deployed. The cost is roughly 160 KB of
base64, paid before a download two orders of magnitude larger.

## Two phases, and why

    python3 tools/art/make_web_gate.py          # inline; run by anyone
    python3 tools/art/make_web_gate.py --art     # re-encode; run when art changes

Encoding is not reproducible and inlining is. Pillow's PNG writer hands the
pixels to whatever zlib it was built against, so the same picture comes out
41,201 bytes on macOS and 41,471 on Linux — identical art, different file,
and once that file is base64 inside an HTML document there is no way for a
checker to tell it is the same picture. CI failed on exactly this.

So the encoded images are committed, in `tools/web/art/`, and the ordinary
run does nothing but base64 what is already there: same bytes in, same bytes
out, on every machine. `--art` re-encodes them from `assets/`, and is run by
hand when the art it is made of changes. A plain run notices when that has
happened — `sources.json` records what the images were made from — and says
so without failing, because a stale loading screen is not a broken build.
"""
import argparse, base64, hashlib, io, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATE = os.path.join(ROOT, "tools", "web", "shell.template.html")
OUT = os.path.join(ROOT, "tools", "web", "shell.html")
ART = os.path.join(ROOT, "tools", "web", "art")

BACKDROP_SRC = os.path.join(ROOT, "assets", "levels", "graveyard_moon_wide.png")
BACKDROP_OUT = os.path.join(ART, "backdrop.webp")
SPRITE_OUT = os.path.join(ART, "elian.webp")
SOURCES = os.path.join(ART, "sources.json")

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


def sprite_source(name):
    return os.path.join(ROOT, "assets", "sprites", name + ".png")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def current_sources():
    """What the committed images should have been made from."""
    art = {os.path.relpath(BACKDROP_SRC, ROOT): digest(BACKDROP_SRC)}
    for _, src, _ in ANIMS:
        art[os.path.relpath(sprite_source(src), ROOT)] = digest(sprite_source(src))
    return {"art": art, "backdrop_width": BACKDROP_WIDTH,
            "backdrop_quality": BACKDROP_QUALITY, "sprite_scale": SPRITE_SCALE,
            "anims": [[name, src, count] for name, src, count in ANIMS]}


def encode_art():
    """Re-encode both images from the game's art. Not reproducible; see above."""
    from PIL import Image

    os.makedirs(ART, exist_ok=True)

    panel = Image.open(BACKDROP_SRC).convert("RGB")
    height = round(panel.height * BACKDROP_WIDTH / panel.width)
    panel = panel.resize((BACKDROP_WIDTH, height), Image.LANCZOS)
    panel.save(BACKDROP_OUT, "WEBP", quality=BACKDROP_QUALITY, method=6)

    strips = []
    for _, src, count in ANIMS:
        sheet = Image.open(sprite_source(src))
        strips.append([sheet.crop((i * 128, 0, (i + 1) * 128, 64))
                       for i in range(count)])

    # One rectangle for every frame of every animation. Cropping each frame to
    # its own bounding box would centre each one separately, and the figure
    # would jitter half a pixel per frame and jump when the animation changed.
    boxes = [f.getbbox() for strip in strips for f in strip]
    cell = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    w, h = cell[2] - cell[0], cell[3] - cell[1]
    wide = max(len(s) for s in strips)

    sheet = Image.new("RGBA", (wide * w, len(strips) * h), (0, 0, 0, 0))
    for row, strip in enumerate(strips):
        for col, frame in enumerate(strip):
            sheet.paste(frame.crop(cell), (col * w, row * h))
    sheet = sheet.resize((sheet.width * SPRITE_SCALE, sheet.height * SPRITE_SCALE),
                         Image.NEAREST)
    # Lossless: this is pixel art with a hard alpha edge, and a lossy pass
    # puts a halo on the cloak. Lossless WebP is about half of the PNG.
    sheet.save(SPRITE_OUT, "WEBP", lossless=True, quality=100, method=6)

    with open(SOURCES, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(current_sources(), handle, indent=2, sort_keys=True)
        handle.write("\n")

    print("re-encoded: backdrop %d KB, sprite %d KB (cell %dx%d)" %
          (os.path.getsize(BACKDROP_OUT) // 1024,
           os.path.getsize(SPRITE_OUT) // 1024,
           w * SPRITE_SCALE, h * SPRITE_SCALE))


def cell_size():
    """The sprite sheet's frame size, read back off the committed image."""
    from PIL import Image

    with Image.open(SPRITE_OUT) as sheet:
        wide = max(count for _, _, count in ANIMS)
        return sheet.width // wide, sheet.height // len(ANIMS)


def data_uri(path, mime="image/webp"):
    with open(path, "rb") as handle:
        return "data:%s;base64,%s" % (mime, base64.b64encode(handle.read()).decode("ascii"))


def warn_if_stale():
    """The committed images were made from art that has since changed."""
    if not os.path.exists(SOURCES):
        return
    with open(SOURCES, encoding="utf-8") as handle:
        recorded = json.load(handle)
    now = current_sources()
    if recorded == now:
        return
    moved = [name for name, sha in now["art"].items()
             if recorded.get("art", {}).get(name) != sha]
    what = ", ".join(moved) if moved else "the encoding settings"
    print("note: %s changed since tools/web/art was made — "
          "run with --art to refresh the loading page" % what, file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--art", action="store_true",
                        help="re-encode tools/web/art from assets/ first")
    args = parser.parse_args()

    if args.art:
        encode_art()
    for path in (TEMPLATE, BACKDROP_OUT, SPRITE_OUT):
        if not os.path.exists(path):
            sys.exit("missing %s — run with --art" % os.path.relpath(path, ROOT))
    warn_if_stale()

    cell_w, cell_h = cell_size()
    with open(TEMPLATE, "r", encoding="utf-8") as handle:
        html = handle.read()

    for marker, value in [
        ("__BACKDROP__", data_uri(BACKDROP_OUT)),
        ("__SPRITE__", data_uri(SPRITE_OUT)),
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

    print("wrote %s — %d KB, cell %dx%d" %
          (os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024, cell_w, cell_h))


if __name__ == "__main__":
    main()
