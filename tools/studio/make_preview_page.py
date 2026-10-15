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

Both keep the engine and the pack in the browser's Cache Storage under the
hash of their bytes (keep_script): the 40 MB of wasm and the 100 MB pack are
fetched once and again only when they change. The browser's own HTTP cache does
not do it — Pages says max-age=600, and Chrome and Firefox will not keep one
file that large at all — so the artist waited for 150 MB every time she opened
the sandbox.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ENGINE = re.compile(r"new Engine\((\{.*?\})\)", re.S)
FULL = re.compile(r"const canFull = [^;]*;")


def file_hash(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()[:16]


# Godot's loader asks fetch() for the wasm and the pack by their names (index.js
# loadFetch); a name listed here is answered from Cache Storage when the copy
# kept there has the same hash, else fetched, kept, and the older copy dropped.
# Anything that fails falls back to the plain fetch.
KEEP = """<script>/* the game's big files, kept by their hash (tools/studio/make_preview_page.py) */
(() => {
  const KEEP = %s, plain = window.fetch.bind(window);
  if (!window.caches || !Object.keys(KEEP).length) return;
  const named = u => Object.keys(KEEP).find(k => new URL(k, location.href).href === u.split(/[?#]/)[0]);
  window.fetch = async (input, init) => {
    const name = named(new URL(typeof input === 'string' ? input : input.url, location.href).href);
    if (!name) return plain(input, init);
    let box, id;
    try {
      box = await caches.open('ashes-game-files');
      id = new URL(name, location.href).href + '?sha=' + KEEP[name];
      const kept = await box.match(id);
      if (kept) return kept;
    } catch { return plain(input, init); }
    const res = await plain(input, init);
    if (res.ok) box.put(id, res.clone()).then(async () => {
      for (const r of await box.keys()) if (r.url !== id && r.url.split('?')[0] === id.split('?')[0]) await box.delete(r);
    }).catch(() => {});
    return res;
  };
})();
</script>"""


def keep_script(files: dict) -> str:
    """files: {name the page fetches: Path} → the script that keeps them (those that exist)."""
    return KEEP % json.dumps({name: file_hash(p) for name, p in files.items() if p.is_file()})


def _with_keep(page: str, files: dict) -> str:
    return page.replace("<head>", "<head>\n" + keep_script(files), 1) if files else page


def preview_page(html: str, number: int, pack_size: int, keep: dict | None = None) -> str:
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
    # ?room=… opens a room, ?practice=… the yard, and ?composed=1 the room's composed draft (Run, --composed)
    args = ("['--', '--studio-preview'].concat(['room', 'practice'].filter(k => new URLSearchParams(location.search).get(k))"
            ".map(k => k + '=' + new URLSearchParams(location.search).get(k)))"
            ".concat(new URLSearchParams(location.search).has('composed') ? ['--composed'] : [])")
    page = html[:m.start()] + f"new Engine(Object.assign({json.dumps(cfg)}, {{args: {args}}}))" + html[m.end():]
    banner = (f'<div style="position:fixed;top:0;left:0;right:0;z-index:99;padding:4px 10px;background:#5a4a1a;'
              f'color:#f0d68a;font:13px system-ui;text-align:center">Превью отправки #{number} из студии — '
              f'игра ничего не сохраняет. Сразу в комнату: <code>?room=hell_gate</code>, в собранную в конструкторе: <code>&amp;composed=1</code>, на тренировку с врагом: <code>?practice=cultist</code></div>')
    return _with_keep(page.replace("</body>", banner + "</body>", 1), keep or {})


def live_page(html: str, keep: dict | None = None) -> str:
    m = ENGINE.search(html)
    if not m:
        raise ValueError("no `new Engine({...})` in the page")
    cfg = json.loads(m[1])
    cfg["persistentPaths"] = []
    cfg["args"] = ["--", "--studio-live"]
    page = html[:m.start()] + f"new Engine({json.dumps(cfg)})" + html[m.end():]
    # inside the studio's panel: Play starts it there, it does not take the screen
    return _with_keep(FULL.sub("const canFull = false;", page), keep or {})


def _engine_files(html: Path) -> tuple:
    exe = json.loads(ENGINE.search(html.read_text(encoding="utf-8"))[1]).get("executable", "index")
    return exe, html.parent


if __name__ == "__main__":
    if sys.argv[1] == "--live":
        html = Path(sys.argv[2])
        exe, web = _engine_files(html)
        sys.stdout.write(live_page(html.read_text(encoding="utf-8"),
                                   {f"{exe}.wasm": web / f"{exe}.wasm", f"{exe}.pck": web / f"{exe}.pck"}))
        sys.exit(0)
    html, number, pack = Path(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
    exe, web = _engine_files(html)
    sys.stdout.write(preview_page(html.read_text(encoding="utf-8"), number, pack.stat().st_size,
                                  {f"{exe}.wasm": web / f"{exe}.wasm", f"preview/{number}.pck": pack}))
