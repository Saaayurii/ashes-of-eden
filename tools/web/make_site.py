#!/usr/bin/env python3
"""What the Pages site serves beside the game: the files search engines and
phones ask for, which the Godot export does not write.

    python3 tools/web/make_site.py

Writes tools/web/site/ — committed, and copied into build/web by
.github/workflows/pages.yml after the export:

  - icon-192.png, icon-512.png, apple-touch-icon.png: icon.svg (a 16-cell
    pixel drawing) blown up cell by cell, never resampled;
  - og.jpg: the store's feature graphic (docs/store/play_feature.png), the
    picture a link to the game unfurls into on Telegram, VK, Discord, X;
  - screens/*.webp: the README's screenshots, named in the page's JSON-LD;
  - manifest.webmanifest: "Add to Home Screen" opens the game full screen and
    landscape — the only full screen an iPhone's Safari gives a page;
  - robots.txt and sitemap.xml (see docs/SEO.md for why robots.txt here is a
    courtesy: crawlers read it only at the root of saaayurii.github.io).

Search-console verification files (googleXXXX.html, yandex_XXXX.html) are
dropped into tools/web/site/ by hand and deployed as they are; this script
leaves any file it does not write alone.

Deterministic: no dates, no randomness, so a regeneration is not a diff.
"""
import json
import os
import re
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SITE = os.path.join(ROOT, "tools", "web", "site")
URL = "https://saaayurii.github.io/ashes-of-eden/"
SCREENS = ["graveyard", "boss-knight", "swamp", "hell-gate", "village"]
BACKGROUND = "#0d0c0b"


def pixel_icon(size):
    """icon.svg is plain <rect>s on a 16x16 viewBox: paint them cell by cell."""
    svg = open(os.path.join(ROOT, "icon.svg"), encoding="utf-8").read()
    grid = Image.new("RGB", (16, 16))
    for rect in re.finditer(r"<rect ([^>]*)/>", svg):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', rect.group(1)))
        x, y = int(attrs.get("x", 0)), int(attrs.get("y", 0))
        w, h = int(attrs["width"]), int(attrs["height"])
        colour = attrs["fill"]
        for py in range(y, y + h):
            for px in range(x, x + w):
                grid.putpixel((px, py), tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5)))
    return grid.resize((size, size), Image.NEAREST)


def main():
    os.makedirs(os.path.join(SITE, "screens"), exist_ok=True)
    # Godot imports any picture under res:// it can find; these are not its business.
    open(os.path.join(SITE, ".gdignore"), "w").close()

    for size, name in ((192, "icon-192.png"), (512, "icon-512.png"), (180, "apple-touch-icon.png")):
        pixel_icon(size).save(os.path.join(SITE, name), optimize=True)

    feature = Image.open(os.path.join(ROOT, "docs", "store", "play_feature.png")).convert("RGB")
    feature.save(os.path.join(SITE, "og.jpg"), "JPEG", quality=86, optimize=True, progressive=True)

    for name in SCREENS:
        shutil.copyfile(os.path.join(ROOT, "docs", "screenshots", name + ".webp"),
                        os.path.join(SITE, "screens", name + ".webp"))

    manifest = {
        "name": "Ashes of Eden",
        "short_name": "Ashes of Eden",
        "description": "A dark 2D pixel action roguelite about a soul neither Heaven nor the Abyss can claim.",
        "start_url": "./",
        "scope": "./",
        "display": "fullscreen",
        "display_override": ["fullscreen", "standalone"],
        "orientation": "landscape",
        "background_color": BACKGROUND,
        "theme_color": BACKGROUND,
        "lang": "en",
        "categories": ["games", "entertainment"],
        "icons": [
            {"src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
            {"src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
        ],
    }
    with open(os.path.join(SITE, "manifest.webmanifest"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent="\t", ensure_ascii=False)
        handle.write("\n")

    with open(os.path.join(SITE, "robots.txt"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("User-agent: *\nAllow: /\n\nSitemap: %ssitemap.xml\n" % URL)

    images = "".join(
        "\n\t\t<image:image><image:loc>%sscreens/%s.webp</image:loc></image:image>" % (URL, name)
        for name in SCREENS)
    with open(os.path.join(SITE, "sitemap.xml"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
            '\txmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n'
            "\t<url>\n\t\t<loc>%s</loc>\n\t\t<changefreq>weekly</changefreq>\n"
            "\t\t<priority>1.0</priority>\n"
            "\t\t<image:image><image:loc>%sog.jpg</image:loc></image:image>%s\n"
            "\t</url>\n</urlset>\n" % (URL, URL, images))

    total = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(SITE) for f in fs)
    print("wrote tools/web/site/ (%d KB)" % (total // 1024))


if __name__ == "__main__":
    main()
