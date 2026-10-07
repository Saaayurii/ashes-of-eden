#!/usr/bin/env python3
"""The page that plays a studio pull request's build (pages.yml).

It is the game's own index.html with three changes:
  * its own data pack (preview/<n>.pck) on the main build's engine, so a
    preview costs one .pck, not another 40 MB of wasm;
  * nothing kept between visits (persistentPaths = []): a preview must not
    write into the profile and saves of the real game on the same site;
  * `--studio-preview` with `room=` or `practice=` from the address
    (?room=hell_gate, ?practice=archer), which run.gd honours only with that
    flag: a changed scene can be walked into, a new enemy fought at once.

    python3 tools/studio/make_preview_page.py build/web/index.html 12 build/web/preview/12.pck > build/web/preview-12.html

`--live` writes the studio's sandbox instead (studio-live.html): the main
build's own pack, nothing kept, `--studio-live` (scripts/run/studio_live.gd),
for the iframe of the studio's «Песочница».

    python3 tools/studio/make_preview_page.py --live build/web/index.html > build/web/studio-live.html
"""
import json
import re
import sys
from pathlib import Path

ENGINE = re.compile(r"new Engine\((\{.*?\})\)", re.S)
FULL = re.compile(r"const canFull = [^;]*;")


def preview_page(html: str, number: int, pack_size: int) -> str:
    m = ENGINE.search(html)
    if not m:
        raise ValueError("no `new Engine({...})` in the page")
    cfg = json.loads(m[1])
    pack = f"preview/{number}.pck"
    cfg["mainPack"] = pack
    cfg["persistentPaths"] = []
    sizes = cfg.get("fileSizes", {})
    sizes.pop(f"{cfg.get('executable', 'index')}.pck", None)
    sizes[pack] = pack_size
    cfg["fileSizes"] = sizes
    args = ("['--', '--studio-preview'].concat(['room', 'practice'].filter(k => new URLSearchParams(location.search).get(k))"
            ".map(k => k + '=' + new URLSearchParams(location.search).get(k)))")
    page = html[:m.start()] + f"new Engine(Object.assign({json.dumps(cfg)}, {{args: {args}}}))" + html[m.end():]
    banner = (f'<div style="position:fixed;top:0;left:0;right:0;z-index:99;padding:4px 10px;background:#5a4a1a;'
              f'color:#f0d68a;font:13px system-ui;text-align:center">Превью отправки #{number} из студии — '
              f'игра ничего не сохраняет. Сразу в комнату: <code>?room=hell_gate</code>, на тренировку с врагом: <code>?practice=cultist</code></div>')
    return page.replace("</body>", banner + "</body>", 1)


def live_page(html: str) -> str:
    m = ENGINE.search(html)
    if not m:
        raise ValueError("no `new Engine({...})` in the page")
    cfg = json.loads(m[1])
    cfg["persistentPaths"] = []
    cfg["args"] = ["--", "--studio-live"]
    page = html[:m.start()] + f"new Engine({json.dumps(cfg)})" + html[m.end():]
    # inside the studio's panel: Play starts it there, it does not take the screen
    return FULL.sub("const canFull = false;", page)


if __name__ == "__main__":
    if sys.argv[1] == "--live":
        sys.stdout.write(live_page(Path(sys.argv[2]).read_text(encoding="utf-8")))
        sys.exit(0)
    html, number, pack = sys.argv[1], int(sys.argv[2]), Path(sys.argv[3])
    sys.stdout.write(preview_page(Path(html).read_text(encoding="utf-8"), number, pack.stat().st_size))
