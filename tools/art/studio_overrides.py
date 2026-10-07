#!/usr/bin/env python3
"""The art studio's edits of pictures a generator owns (tools/studio/overrides).

A generator's output is not to be edited by hand: tools/check_generators.py
fails CI when a file is not what its generator writes. But the artist has to
be able to touch up an old enemy, a prop, a room's painting. So her edit is
kept beside the generator, as an input it honours, the way
tools/rooms/studio_rooms.json is for rooms:

    tools/studio/overrides/overrides.json          {path: {size, base, stale, by, at}}
    tools/studio/overrides/<path>                  her picture, whole
    tools/studio/overrides/<path minus .png>.mask.png   255 where she changed it

and every generator passes a picture through `patched(path, image)` just
before it saves it: the generator's own picture, with her pixels laid over it
where the mask says. Regenerating keeps her work, and check_generators stays
green with no list of exceptions.

`base` is a hash of the generator's own picture when she drew on it. When the
generator later draws something else under her edit (a new atlas, a fixed
cell), the edit still applies if the size is the same, the generator prints a
warning, and with STUDIO_OVERRIDES_RECORD=1 (the studio's robot, the local
studio server) the entry is marked `stale` — the studio says «база
изменилась — проверь». If the size changed, the edit cannot be laid over the
new picture and the generator fails, naming the override.

A file inside a generator's folder that no generator actually writes (the
hero's strips sit in assets/sprites beside the bestiary's) is brought in line
by `settle`, which lays every edit over the picture as it is.

    python3 tools/art/studio_overrides.py list        # what is overridden, by which generator
    python3 tools/art/studio_overrides.py settle      # lay every edit over its picture as it is now
    python3 tools/art/studio_overrides.py regenerate  # run the generators that own an edit, then settle
"""
import atexit, hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, "tools", "studio", "overrides")
MANIFEST = os.path.join(DIR, "overrides.json")

## The generators of tools/check_generators.py that pass what they write through `patched`,
## and so whose pictures the studio may edit (tools/studio/build_data.py lists them for it).
OVERRIDABLE = {"secret walls", "altar book", "blood altar", "bestiary strips", "ophanim seals",
               "rooms", "hero moves", "practice yard"}

_cache = None
_seen = {}   # rel -> ("new" | "stale", base hash), recorded at exit when asked


def load():
    global _cache
    if _cache is None:
        _cache = {}
        if os.path.exists(MANIFEST):
            with open(MANIFEST, encoding="utf-8") as f:
                _cache = json.load(f)
    return _cache


def save_manifest(data):
    os.makedirs(DIR, exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent=2) + "\n")


def rel_of(path):
    path = os.fspath(path)
    if os.path.isabs(path):
        path = os.path.relpath(path, ROOT)
    return path.replace(os.sep, "/")


def files_of(rel):
    """Her picture and its mask for an overridden path."""
    stem = rel[:-4] if rel.lower().endswith(".png") else rel
    return os.path.join(DIR, rel), os.path.join(DIR, stem + ".mask.png")


def pixel_hash(img):
    img = img.convert("RGBA")
    h = hashlib.sha1(("%dx%d:" % img.size).encode())
    h.update(img.tobytes())
    return h.hexdigest()[:16]


def _lay(rel, img, entry):
    from PIL import Image
    edit_path, mask_path = files_of(rel)
    edit = Image.open(edit_path).convert("RGBA")
    mask = Image.open(mask_path).convert("L")
    if edit.size != img.size or mask.size != img.size:
        raise SystemExit(
            "studio override %s: it was drawn on a %dx%d picture and the generator now makes %dx%d.\n"
            "  Open it in the studio and redo the edit on the new picture, or remove it from %s."
            % (rel, edit.size[0], edit.size[1], img.size[0], img.size[1], os.path.relpath(MANIFEST, ROOT)))
    out = img.convert("RGBA").copy()
    out.paste(edit, (0, 0), mask)
    return out if img.mode == "RGBA" else out.convert(img.mode)


def patched(path, img):
    """The generator's picture for `path`, with the studio's edit laid over it (or as it is)."""
    rel = rel_of(path)
    entry = load().get(rel)
    if not entry:
        return img
    base = pixel_hash(img)
    if entry.get("base") and entry["base"] != base:
        print("studio override %s: the picture under it changed since it was drawn — check it in the studio" % rel,
              file=sys.stderr)
        _seen[rel] = ("stale", base)
    elif not entry.get("base"):
        _seen[rel] = ("new", base)
    return _lay(rel, img, entry)


@atexit.register
def _record():
    """Writes what a run learned into the manifest — only when asked, so a plain
    regeneration (check_generators) never touches a file it does not own."""
    if not _seen or os.environ.get("STUDIO_OVERRIDES_RECORD") != "1":
        return
    data = load()
    for rel, (kind, base) in _seen.items():
        if rel not in data:
            continue
        if kind == "new":
            data[rel]["base"] = base
        else:
            data[rel]["stale"] = True
    save_manifest(data)


def owners():
    """{generator name: (script, [paths])} from tools/check_generators.py."""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import check_generators
    return {name: (argv[0], paths) for name, argv, paths, _slow in check_generators.GENERATORS}


def owner_of(rel):
    for name, (script, paths) in owners().items():
        if any(rel == p or rel.startswith(p.rstrip("/") + "/") for p in paths):
            return name, script
    return None, None


def settle():
    """Lays every edit over its picture as it is now. A generator already did it for what it writes;
    this brings in line a picture in a generator's folder that no generator writes."""
    from PIL import Image
    changed = []
    for rel, entry in load().items():
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print("studio override %s: no such picture any more" % rel, file=sys.stderr)
            continue
        img = Image.open(path)
        img.load()
        out = _lay(rel, img, entry)
        if pixel_hash(out) != pixel_hash(img):
            out.save(path, optimize=True)
            changed.append(rel)
    return changed


def regenerate():
    """What the studio's robot and the local studio server do with a new edit: run each
    generator that owns one (recording bases and stale marks), then settle."""
    env = dict(os.environ, STUDIO_OVERRIDES_RECORD="1")
    scripts = []
    for rel in load():
        _name, script = owner_of(rel)
        if script and script not in scripts:
            scripts.append(script)
    for script in scripts:
        print("==> %s" % script, flush=True)
        subprocess.run([sys.executable, script], cwd=ROOT, env=env, check=True)
    global _cache
    _cache = None
    return scripts, settle()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        for rel, entry in sorted(load().items()):
            name, _ = owner_of(rel)
            print("%-56s %-18s %s%s" % (rel, name or "(no generator)", "x".join(map(str, entry.get("size", []))),
                                        "  STALE" if entry.get("stale") else ""))
    elif cmd == "settle":
        for rel in settle():
            print("settled", rel)
    elif cmd == "regenerate":
        scripts, settled = regenerate()
        print("ran %d generator(s), settled %d picture(s)" % (len(scripts), len(settled)))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
