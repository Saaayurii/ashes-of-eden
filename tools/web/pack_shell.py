#!/usr/bin/env python3
"""The loading page of a game pack (docs/GAME_PACKS.md).

tools/web/shell.html is Ashes' page: its name, its story in the description,
its graveyard behind the hero, its links, og image and screenshots. A pack laid
over the engine gets its own from the same template:

    python3 tools/web/pack_shell.py --repo owner/name [--url https://owner.github.io/name/]

  * the name is game.json "name";
  * "web": {"tagline", "description"} in game.json say what the page says
    (absent: the name alone, and a line naming the engine);
  * the picture behind the hero is the game's menu background (game.json
    "menu": {"background"}), encoded like make_web_gate.py --art does;
  * the head keeps only what the pack's Pages actually serve: no og image, no
    screenshots, no manifest (they are Ashes' files, tools/web/site/).

The hero standing on it is the engine's (the same sheet the game animates).
game.yml runs it before the Web export; apply_pack.py --restore checks
shell.html out again, so a local run never leaves Ashes with another game's page.
"""
from __future__ import annotations

import argparse
import html
import io
import json
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import make_web_gate as gate  # noqa: E402

GAME = os.path.join(ROOT, "content", "data", "game.json")


def res_path(res: str) -> str:
    return os.path.join(ROOT, res.replace("res://", "", 1))


def backdrop(game: dict) -> str:
    """The menu's picture as a data URI, or the engine's when there is none."""
    picture = str((game.get("menu") or {}).get("background", ""))
    if not picture or not os.path.exists(res_path(picture)):
        return gate.data_uri(gate.BACKDROP_OUT)
    from PIL import Image

    panel = Image.open(res_path(picture)).convert("RGB")
    width = min(gate.BACKDROP_WIDTH, panel.width)
    panel = panel.resize((width, round(panel.height * width / panel.width)), Image.LANCZOS)
    with tempfile.NamedTemporaryFile(suffix=".webp", delete=False) as out:
        panel.save(out, "WEBP", quality=gate.BACKDROP_QUALITY, method=6)
    try:
        return gate.data_uri(out.name)
    finally:
        os.unlink(out.name)


def head(name: str, tagline: str, description: str, url: str, repo_url: str) -> str:
    e = lambda s: html.escape(s, quote=True)  # noqa: E731
    ld = {"@context": "https://schema.org", "@type": "VideoGame", "name": name, "description": description,
          "genre": ["Action", "Roguelite", "Platformer"], "gamePlatform": ["Web browser"],
          "applicationCategory": "Game", "isAccessibleForFree": True}
    if url:
        ld["url"] = url
    if repo_url:
        ld["sameAs"] = [repo_url]
    lines = [
        f"<title>{e(name)}{' — ' + e(tagline) if tagline else ''}</title>",
        f'<meta name="description" content="{e(description)}">',
        '<meta name="robots" content="index, follow">',
    ]
    if url:
        lines.append(f'<link rel="canonical" href="{e(url)}">')
    lines += [
        '<meta name="theme-color" content="#0d0c0b">',
        '<meta name="color-scheme" content="dark">',
        '<meta name="mobile-web-app-capable" content="yes">',
        '<meta name="apple-mobile-web-app-capable" content="yes">',
        '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">',
        f'<meta name="apple-mobile-web-app-title" content="{e(name)}">',
        f'<meta property="og:site_name" content="{e(name)}">',
        f'<meta property="og:title" content="{e(name)}">',
        f'<meta property="og:description" content="{e(tagline or description)}">',
        '<meta property="og:type" content="website">',
    ]
    if url:
        lines.append(f'<meta property="og:url" content="{e(url)}">')
    lines += [
        '<link id="-gd-engine-icon" rel="icon" type="image/png" href="$GODOT_PROJECT_NAME.icon.png">',
        '<script type="application/ld+json">',
        json.dumps(ld, ensure_ascii=False, indent="\t"),
        "</script>",
    ]
    return "\n\t".join(lines)


def build(game: dict, repo: str, url: str) -> str:
    name = str(game.get("name") or game.get("id") or "Game")
    web = game.get("web") or {}
    tagline = str(web.get("tagline", ""))
    description = str(web.get("description") or f"{name} — a 2D pixel action game on the Ashes of Eden engine.")
    repo_url = f"https://github.com/{repo}" if repo else ""
    e = lambda s: html.escape(s, quote=False)  # noqa: E731

    with open(gate.TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    swaps = [
        # the head: from the title to the end of the JSON-LD
        (r"<title>.*?<script type=\"application/ld\+json\">.*?</script>", head(name, tagline, description, url, repo_url)),
        (r"<h1>.*?</h1>", f"<h1>{e(name)}</h1>"),
        (r'<p class="sub">.*?</p>', f'<p class="sub">{e(tagline)}</p>' if tagline else ""),
        (r'aria-label="Elian, standing in the graveyard"', f'aria-label="{html.escape(name)}"'),
        (r'<section id="about">.*?</section>',
         '<section id="about">\n\t\t\t<p>' + e(description) + "</p>"
         + (f'\n\t\t\t<p><a href="{repo_url}">Source and credits on GitHub</a></p>' if repo_url else "")
         + "\n\t\t</section>"),
    ]
    for pattern, value in swaps:
        page, n = re.subn(pattern, lambda _m, v=value: v, page, count=1, flags=re.S)
        if n != 1:
            sys.exit(f"pack_shell: the template no longer has {pattern!r}")

    cell_w, cell_h = gate.cell_size()
    for marker, value in [
        ("__BACKDROP__", backdrop(game)),
        ("__SPRITE__", gate.data_uri(gate.SPRITE_OUT)),
        ("__CELL_W__", str(cell_w)),
        ("__CELL_H__", str(cell_h)),
        ("__IDLE_FRAMES__", str(gate.ANIMS[0][2])),
        ("__WALK_FRAMES__", str(gate.ANIMS[1][2])),
        ("__SHEET_W__", str(max(count for _, _, count in gate.ANIMS) * cell_w)),
    ]:
        if marker not in page:
            sys.exit("pack_shell: the template no longer uses " + marker)
        page = page.replace(marker, value)
    return page


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", default="", help="the pack's repository, owner/name (its source link)")
    parser.add_argument("--url", default="", help="where the page is served (canonical, og:url)")
    args = parser.parse_args()
    if not os.path.exists(GAME):
        sys.exit("pack_shell: no game pack laid over the engine (tools/packs/apply_pack.py)")
    with open(GAME, encoding="utf-8") as handle:
        game = json.load(handle)
    page = build(game, args.repo, args.url)
    with open(gate.OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    print(f"wrote {os.path.relpath(gate.OUT, ROOT)} for {game.get('name')} — {len(page.encode()) // 1024} KB")


if __name__ == "__main__":
    main()
