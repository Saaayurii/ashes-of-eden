#!/usr/bin/env python3
"""Builds what the art studio (tools/studio/index.html) reads about the game.

The studio is a static page: it cannot list res:// or parse a .tscn, so this
script turns the game into JSON once, into tools/studio/import/ (not tracked;
pages.yml runs it for the hosted copy):

    list.json, chars/*.sprite.json   characters: the hero's SpriteFrames and every
                                     bestiary strip, cut into frames
    rooms_list.json, rooms/*.bg.json each room's Parallax2D layers and decor
    library.json                     every picture a background can use
    audio.json                       sfx (grouped into takes), music, spoken lines
    cutscenes.json                   cutscenes, dialogues, strings, which room plays
                                     which scene, the room order
    meta.json                        repository, branch, where assets are fetched from

Projects people saved from the studio into tools/studio/projects/<kind>/ are
listed beside the game's own, so everybody opening the page sees them.

Everything that came out of a generator says so (`origin.generator`), and
meta.json lists every file a generator owns: the studio refuses to write those
back, because tools/check_generators.py would then fail CI. New characters,
takes, lines and scenes are plain files; the ones the studio created are listed
in tools/studio/projects/files.json and stay editable.

    python3 tools/studio/build_data.py
    python3 tools/studio/build_data.py --asset-base https://raw.githubusercontent.com/OWNER/REPO/main/
"""
import ast
import argparse
import base64
import csv
import hashlib
import importlib.util
import io
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
STUDIO = ROOT / "tools" / "studio"
REPO = "Saaayurii/ashes-of-eden"
LIB_DIRS = ("backgrounds", "levels", "decor", "environment", "cutscenes")
VIEW_ZOOM = 1.14  # scripts/player/player.gd: camera.zoom
HERO_GENERATOR = "tools/art/build_elian_frames.py"
BESTIARY_GENERATOR = "tools/art/build_bestiary_assets.py"
ROOM_GENERATOR = "tools/rooms/generate_rooms.py"


def res_to_path(root: Path, res: str) -> Path:
    return root / res.removeprefix("res://")


def asset_url(res: str) -> str:
    """res://assets/x.png -> assets/x.png; the page prefixes its asset base."""
    return res.removeprefix("res://")


def rev(root: Path, *res):
    """A short hash of the files a thing came from: the studio's sign that the game changed it."""
    h = hashlib.sha1()
    for r in res:
        p = res_to_path(root, r) if r.startswith("res://") else root / r
        h.update(p.read_bytes() if p.exists() else b"")
    return h.hexdigest()[:12]


def data_url(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


# ------------------------------------------------------------- characters ---

def _frame(fid, img):
    return {"id": fid, "pose": "", "src": data_url(img), "dx": 0, "dy": 0, "sc": 1, "off": False, "dur": 1}


def _anim(pid, name, fps, loop, imgs, res=None, durations=None, regions=None):
    """regions: where each frame lies in the game's files, [res, x, y, w, h] — the studio
    writes an edit of a generated picture back there, as an override (tools/art/studio_overrides.py)."""
    aid = f"{pid}_{name}"
    frames = [_frame(f"{aid}_{i}", im) for i, im in enumerate(imgs)]
    for f, d in zip(frames, durations or []):
        f["dur"] = d
    return {"id": aid, "name": name, "fps": fps, "loop": loop, "scale": 1, "notes": "",
            "frames": frames, "file": res, "regions": regions or [], "_imgs": imgs}


def _character(pid, cell, animations, description, origin):
    w, h = cell
    first = next((a for a in animations if a["name"] == "idle"), animations[0])
    bbox = first["_imgs"][0].getchannel("A").getbbox() or (0, 0, w, h)
    for a in animations:
        a.pop("_imgs")
    return {
        "id": pid, "name": pid, "description": description, "reference": first["frames"][0]["src"],
        "settings": {"cellW": w, "cellH": h, "contentH": bbox[3] - bbox[1], "bottomPad": h - bbox[3],
                     "palette": 0, "tolerance": 48, "pixelSize": 0, "bgMode": "alpha", "scaleMode": "none",
                     "anchor": "none", "downMode": "dominant", "resPath": "res://assets/sprites/",
                     "gridfitMigrated": True},
        "animations": animations, "current": first["id"], "origin": origin, "updated": 0,
    }


def slice_strip(path: Path, cw: int, ch: int):
    img = Image.open(path).convert("RGBA")
    out = []
    for x in range(0, img.width - cw + 1, cw):
        fr = img.crop((x, 0, x + cw, ch))
        if fr.getchannel("A").getbbox():  # trailing empty cells are padding
            out.append(fr)
    return out


def parse_sprite_frames(text):
    """A SpriteFrames .tres -> [(name, fps, loop, [(texture res, (x, y, w, h), duration)])]."""
    ext = {m[1]: m[0] for m in re.findall(r'\[ext_resource type="Texture2D"[^\]]*?path="([^"]+)"[^\]]*?id="([^"]+)"\]', text)}
    sub = {}
    for sid, atlas, x, y, w, h in re.findall(
            r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]\s*atlas = ExtResource\("([^"]+)"\)\s*'
            r'region = Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)', text):
        sub[sid] = (ext[atlas], tuple(int(float(v)) for v in (x, y, w, h)))
    out = []
    for body, loop, name, speed in re.findall(
            r'\{\s*"frames": \[(.*?)\],\s*"loop": (true|false),\s*"name": &"([^"]+)",\s*"speed": ([\d.]+)\s*\}', text, re.S):
        frames = [(sub[sid][0], sub[sid][1], float(dur)) for dur, sid in
                  re.findall(r'"duration": ([\d.]+),\s*"texture": SubResource\("([^"]+)"\)', body)]
        out.append((name, float(speed), loop == "true", frames))
    return out


def hero(root: Path):
    tres = "res://assets/sprites/elian_frames.tres"
    sheets, anims, cell = {}, [], None
    for name, fps, loop, frames in parse_sprite_frames(res_to_path(root, tres).read_text(encoding="utf-8")):
        imgs = []
        for res, (x, y, w, h), _ in frames:
            if res not in sheets:
                sheets[res] = Image.open(res_to_path(root, res)).convert("RGBA")
            imgs.append(sheets[res].crop((x, y, x + w, y + h)))
            cell = cell or (w, h)
        if imgs:
            anims.append(_anim("elian", name, fps, loop, imgs, frames[0][0], [f[2] for f in frames],
                               [[res, x, y, w, h] for res, (x, y, w, h), _ in frames]))
    c = _character("elian", cell, anims, "hero, imported from the game",
                   {"kind": "game", "generator": HERO_GENERATOR, "tres": tres})
    c["rev"] = rev(root, tres, *sorted(sheets))
    return c


def bestiary(root: Path, strings=None):
    """Every creature of data/enemies as a character from the game: the archetype tree's
    (build_bestiary_assets.py), then one per other set of strips an enemy is drawn with
    (an old strip a variant still wears, the ophanim's seal, the straw man). A variant drawn
    with another's strips and a tint is not a character of its own: `strip_owners` names
    whose it wears, and the studio's «Персонажи» opens that one."""
    strings = strings if strings is not None else load_strings(root)
    raw, resolved = game_enemies(root)
    tree = json.loads((root / "data/enemy_archetypes/tree.json").read_text(encoding="utf-8"))
    _owner, own = strip_owners(root, raw, resolved)
    sprites = [(e["id"], e["sprite"], BESTIARY_GENERATOR) for e in tree if e.get("sprite")]
    sprites += [(eid, enemy_sprite(resolved, resolved[eid].get("sprite", {})), None) for eid in own]
    out = []
    for eid, sp, generator in sprites:
        cw, ch = sp["cell"]
        anims = []
        for name, res in sp["animations"].items():
            path = res_to_path(root, res)
            if path.exists():
                imgs = slice_strip(path, cw, ch)
                if imgs:
                    anims.append(_anim(eid, name, float(sp.get("fps", 8)), name in ("idle", "walk"), imgs, res,
                                       regions=[[res, i * cw, 0, cw, ch] for i in range(len(imgs))]))
        if anims:
            family = next((e.get("family") for e in tree if e["id"] == eid), "")
            origin = {"kind": "game", "generator": generator or strip_generator(asset_url(anims[0]["file"])), "enemy": eid}
            c = _character(eid, (cw, ch), anims, f"{family or 'enemy'} enemy, imported from the game", origin)
            c["name"] = strings.get(raw.get(eid, {}).get("name", ""), {}).get("ru") or eid
            c["rev"] = rev(root, *sorted(a["file"] for a in anims))
            out.append(c)
    return out


def strip_owners(root: Path, raw, resolved):
    """Whose character holds the strips each enemy is drawn with (Enemy._setup_sprite, "like"
    and "extends" followed): {enemy id: character id | None}, and the enemies that need a
    character of their own (strips nobody in the archetype tree has, and no studio project
    of that id — ash_archer is one the studio made and keeps in tools/studio/projects)."""
    tree = json.loads((root / "data/enemy_archetypes/tree.json").read_text(encoding="utf-8"))
    projects = {json.loads(f.read_text(encoding="utf-8")).get("id") for f in (STUDIO / "projects" / "chars").glob("*.json")}
    files = lambda sp: frozenset(r for r in sp.get("animations", {}).values() if res_to_path(root, r).exists())
    held = [(files(e["sprite"]), e["id"]) for e in tree if e.get("sprite") and files(e["sprite"])]
    # the one others borrow from first, so a variant's old strips are named after the creature they were drawn for
    lent = {e.get("sprite", {}).get("like") for e in raw.values()} | {e.get("extends") for e in raw.values()}
    owner, own = {}, []
    for eid in sorted(raw, key=lambda i: (i not in lent, i)):
        sp = enemy_sprite(resolved, resolved[eid].get("sprite", {}))
        mine = files(sp)
        if not mine or "cell" not in sp:
            owner[eid] = None
            continue
        hit = next((cid for key, cid in held if mine <= key), None)
        if hit is None:
            hit = eid
            held.append((mine, eid))
            if eid not in projects:
                own.append(eid)
        owner[eid] = hit
    return owner, own


def strip_generator(rel):
    """The generator that owns a picture, the most particular first (tools/check_generators.py):
    the ophanim's seals have their own, inside the bestiary's folder."""
    sys.path.insert(0, str(STUDIO.parents[0] / "art"))
    from studio_overrides import owners
    best = max(((len(p), script) for script, paths in owners().values() for p in paths
                if rel == p or rel.startswith(p.rstrip("/") + "/")), default=(0, None))
    return best[1]


# ------------------------------------------------------------------ rooms ---

def _vec(v, default=(0.0, 0.0)):
    m = re.match(r"Vector2\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)", v or "")
    return [float(m[1]), float(m[2])] if m else list(default)


def _color(v):
    nums = [float(x) for x in re.findall(r"[-\d.e]+", v or "")]
    return (nums + [1, 1, 1, 1])[:4] if nums else [1, 1, 1, 1]


def parse_tscn(text):
    """-> ({ext id: res path}, [{name, type, parent, props}]) for the nodes of a scene."""
    ext = {m[1]: m[0] for m in re.findall(r'\[ext_resource type="Texture2D"[^\]]*?path="([^"]+)"[^\]]*?id="([^"]+)"\]', text)}
    nodes = []
    for block in re.split(r"\n(?=\[)", text):
        m = re.match(r'\[node name="([^"]+)"(?: type="([^"]+)")?(?: parent="([^"]+)")?', block)
        if m:
            nodes.append({"name": m[1], "type": m[2], "parent": m[3], "props": dict(re.findall(r"^(\w+) = (.*)$", block, re.M))})
    return ext, nodes


def _size(root, res, cache={}):
    if res not in cache:
        try:
            cache[res] = Image.open(res_to_path(root, res)).size
        except OSError:
            cache[res] = None
    return cache[res]


## the layer nodes tools/rooms/studio_textures.py lays her own pictures in
STUDIO_LAYERS = ("StudioBack", "StudioMid", "StudioFront", "StudioTop")


def room_project(root: Path, path: Path):
    text = path.read_text(encoding="utf-8")
    ext, nodes = parse_tscn(text)
    top = nodes[0]["props"]
    images, layers = {}, []
    ambient = next((_color(n["props"].get("color")) for n in nodes if n["type"] == "CanvasModulate" and n["parent"] == "."), None)

    def sprite(n):
        p = n["props"]
        tex = re.match(r'ExtResource\("([^"]+)"\)', p.get("texture", ""))
        if not tex or tex[1] not in ext:
            return None
        res = ext[tex[1]]
        size = _size(root, res)
        if not size:
            return None
        images.setdefault(res, {"url": asset_url(res), "res": res, "w": size[0], "h": size[1]})
        sx, sy = _vec(p.get("scale"), (1, 1))
        x, y = _vec(p.get("position"))
        region = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", p.get("region_rect", "").partition("(")[2])] if p.get("region_enabled") == "true" else None
        w, h = region[2:] if region else size
        if p.get("centered", "true") != "false":  # the studio keeps the top-left corner
            x -= w * abs(sx) / 2
            y -= h * abs(sy) / 2
        blend = re.match(r'SubResource\("studio_blend_(\w+)"\)', p.get("material", ""))
        return {"id": f"{path.stem}_{n['parent']}_{n['name']}", "kind": "sprite", "name": n["name"], "img": res,
                "x": round(x, 2), "y": round(y, 2), "sx": sx, "sy": sy, "flipH": p.get("flip_h") == "true",
                "modulate": _color(p.get("modulate")), "filter": int(p.get("texture_filter", 0)),
                # the node as the scene has it, for the «Текстуры» tab's retouch (tools/rooms/studio_textures.py)
                "node": {"path": n["name"] if n["parent"] == "." else f"{n['parent']}/{n['name']}",
                         "tex": res.removeprefix("res://assets/"), "pos": _vec(p.get("position")),
                         "centered": p.get("centered", "true") != "false",
                         "rot": round(math.degrees(float(p.get("rotation", 0))), 4), "flipV": p.get("flip_v") == "true",
                         "region": region, "z": int(p.get("z_index", 0)), "visible": p.get("visible", "true") != "false",
                         "repeat": int(p.get("texture_repeat", 0)), "blend": blend[1] if blend else "mix"}}

    def rect(n):
        p = n["props"]
        if "material" in p:  # shader fog is not a picture
            return None
        l, t = float(p.get("offset_left", 0)), float(p.get("offset_top", 0))
        return {"id": f"{path.stem}_{n['parent']}_{n['name']}", "kind": "rect", "name": n["name"], "x": l, "y": t,
                "w": float(p.get("offset_right", 0)) - l, "h": float(p.get("offset_bottom", 0)) - t, "color": _color(p.get("color"))}

    def layer(name, scroll, children, z=0):
        items = [i for i in ((sprite(c) if c["type"] == "Sprite2D" else rect(c) if c["type"] == "ColorRect" else None)
                             for c in children) if i]
        if items:
            layers.append({"id": f"{path.stem}_{name}", "name": name, "scroll": scroll, "visible": True, "opacity": 1,
                           "repeatX": False, "z": z, "items": items})

    loose = []
    for n in nodes[1:]:
        if n["parent"] != ".":
            continue
        kids = [c for c in nodes if c["parent"] == n["name"]]
        z = int(n["props"].get("z_index", 0))
        if n["type"] == "Parallax2D":
            layer(n["name"], _vec(n["props"].get("scroll_scale"), (1, 1)), kids, z)
        elif n["type"] == "Sprite2D":
            if n["name"] == "Painting":
                layer("Painting", [1, 1], [n], z)
            else:
                loose.append(n)
        elif n["type"] == "Node2D" and n["name"] in ("Terrain", "DecorMid", "DecorFront", "Front"):
            layer(n["name"], [1, 1], kids, z)
        elif n["type"] == "Node2D" and n["name"] in STUDIO_LAYERS:  # laid by the «Текстуры» tab
            layer(n["name"], [1, 1], kids, z)
            if layers and layers[-1]["name"] == n["name"]:
                layers[-1]["studio"] = True
    if loose:
        layer("Sprites", [1, 1], loose)
    layers.sort(key=lambda l: l["z"])
    spawns = [[c["props"].get("enemy_id", '""').strip('"'), *_vec(c["props"].get("position"))]
              for c in nodes if c["parent"] == "Spawns" and c["type"] == "Marker2D"]
    # the tops of the room's colliders: where an enemy placed in the studio can stand
    rects = {m[0]: (float(m[1]), float(m[2])) for m in re.findall(
        r'\[sub_resource type="RectangleShape2D" id="([^"]+)"\]\s*size = Vector2\(([-\d.]+), ([-\d.]+)\)', text)}
    surfaces = []
    for c in nodes:
        shape = re.match(r'SubResource\("([^"]+)"\)', c["props"].get("shape", ""))
        if c["parent"] in ("Geometry", "Ledges") and c["type"] == "CollisionShape2D" and shape and shape[1] in rects:
            (cx, cy), (w, h) = _vec(c["props"].get("position")), rects[shape[1]]
            if w >= 16 and cy - h / 2 >= 0:
                surfaces.append([round(cx - w / 2, 1), round(cy - h / 2, 1), round(w, 1)])
    # what burns or drowns already (scripts/rooms/hazard.gd): the painted rooms' lava, and whatever
    # liquids the generator laid from tools/rooms/studio_rooms.json; «Жидкости» shows them on the map
    hazard_ids = set(re.findall(r'\[ext_resource type="Script"[^\]]*?path="res://scripts/rooms/hazard\.gd"[^\]]*?id="([^"]+)"\]', text))
    hazards = []
    for n in nodes:
        script = re.match(r'ExtResource\("([^"]+)"\)', n["props"].get("script", ""))
        if n["type"] == "Area2D" and script and script[1] in hazard_ids:
            hx, hy = _vec(n["props"].get("position"))
            hw, hh = _vec(n["props"].get("size"), (100, 30))
            kind = (n["props"].get("kind") or n["props"].get("liquid") or '"lava"').strip('"&')
            hazards.append([kind, round(hx, 1), round(hy, 1), round(hw, 1), round(hh, 1),
                            {"painted": n["props"].get("painted", "true") != "false", "name": n["name"]}])
    return {
        "spawns": spawns, "surfaces": surfaces, "hazards": hazards,
        "id": "room_" + path.stem, "kind": "bg", "name": path.stem,
        "width": int(float(top.get("width", 1280))), "height": int(float(top.get("height", 360))),
        "viewW": round(640 / VIEW_ZOOM), "viewH": round(360 / VIEW_ZOOM), "ambient": ambient,
        "resDir": f"res://assets/backgrounds/{path.stem}/", "images": images, "layers": layers,
        "origin": {"kind": "game", "generator": ROOM_GENERATOR, "room": path.stem}, "updated": 0,
        "rev": rev(root, path.relative_to(root).as_posix()),
        "intro_cutscene": top.get("intro_cutscene", '""').strip('"'), "outro_cutscene": top.get("outro_cutscene", '""').strip('"'),
    }


def library(root: Path):
    out = []
    for d in LIB_DIRS:
        for f in sorted((root / "assets" / d).rglob("*.png")):
            rel = f.relative_to(root).as_posix()
            w, h = Image.open(f).size
            out.append({"res": "res://" + rel, "url": rel, "cat": d, "w": w, "h": h})
    return out


# ------------------------------------------------------ sound and story ---

def take_base(name):
    """hit_2 -> hit (Audio._base_name): only a trailing number marks a take."""
    head, _, tail = name.rpartition("_")
    return head if head and tail.isdigit() else name


def load_strings(root: Path):
    with open(root / "localization/strings.csv", encoding="utf-8") as f:
        return {row["keys"]: {k: row.get(k, "") for k in ("en", "ru", "uk", "zh_CN")} for row in csv.DictReader(f)}


def audio(root: Path, strings):
    base = root / "assets/audio"
    entries = {}
    moods_of = {}
    for mood, tracks in json.loads((root / "data/music/playlists.json").read_text(encoding="utf-8")).items():
        for t in tracks:
            moods_of.setdefault(t, []).append(mood)
    for f in sorted(base.rglob("*")):
        if f.suffix not in (".wav", ".ogg", ".mp3"):
            continue
        parts = f.relative_to(base).parts
        cat, stem, locale = parts[0], f.stem, None
        if cat == "sfx":
            key, name = f"sfx/{take_base(stem)}", take_base(stem)
        elif cat == "music":
            key, name = f"music/{stem}", stem
        elif cat == "voice":
            locale = parts[1]
            key, name = f"voice/{locale}/{stem}", stem
        else:
            continue
        e = entries.setdefault(key, {"key": key, "cat": cat, "name": name, "locale": locale, "takes": []})
        rel = f.relative_to(root).as_posix()
        e["takes"].append({"file": f.name, "stem": stem, "ext": f.suffix[1:], "url": rel, "res": "res://" + rel})
        if cat == "music":
            e["moods"] = moods_of.get(stem, [])
        if cat == "voice":
            e["text"] = strings.get(stem, {}).get(locale) or strings.get(stem, {}).get("en", "")
    return list(entries.values())


def game_doc(root: Path) -> dict:
    """data/game.json (docs/GAME_PACKS.md): the game's rooms in play order, its practice yard, its paths."""
    path = root / "data/game.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def game_rooms(game: dict) -> list:
    """Every night's rooms in play order: "rooms", then each of "nights" (DataDoc.all_rooms)."""
    out = []
    for path in game.get("rooms", []) + [p for night in game.get("nights", []) for p in night.get("rooms", [])]:
        if path not in out:
            out.append(path)
    return out


def room_scenes(root: Path):
    """The room scenes the game has: every one in scenes/rooms for Ashes; for a game
    pack (game.json "inherit") the ones its game.json plays, borrowed or its own,
    and whatever else it keeps in content/scenes/rooms."""
    game = game_doc(root)
    if "inherit" not in game:
        return sorted((root / "scenes/rooms").glob("*.tscn"))
    found = {}
    for res in game_rooms(game) + [game.get("practice_room", "")]:
        path = res_to_path(root, res) if res else None
        if path and path.exists():
            found[path.as_posix()] = path
    for path in sorted((root / "content/scenes/rooms").glob("*.tscn")):
        found.setdefault(path.as_posix(), path)
    return list(found.values())


def room_order(root: Path):
    game = game_doc(root)
    seen = []
    for path in game_rooms(game) + [game.get("practice_room", "")]:
        name = Path(path).stem
        if name and name not in seen:
            seen.append(name)
    return seen


def story(root: Path, strings, rooms):
    scenes = []
    for f in sorted((root / "data/cutscenes").glob("*.json")):
        c = json.loads(f.read_text(encoding="utf-8"))
        scenes.append({"id": c.get("id", f.stem), "kind": "cutscene", "steps": c.get("steps", []),
                       "origin": {"kind": "game", "file": f.relative_to(root).as_posix()}, "updated": 0,
                       "rev": rev(root, f.relative_to(root).as_posix())})
    dialogues = {}
    for f in sorted((root / "data/dialogues").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        for one in (d if isinstance(d, list) else [d]):  # a file may hold several dialogues
            one["_file"] = f.name
            dialogues[one.get("id", f.stem)] = one
    # who plays each dialogue besides a cutscene: an NPC talked to on E (bubbles), a note
    # read as a caption, a fork's question at a door — any data file naming it as "dialogue"
    used_by = {}
    def users(node, kind, name):
        if isinstance(node, dict):
            if isinstance(node.get("dialogue"), str):
                used_by.setdefault(node["dialogue"], []).append({"kind": kind, "name": node.get("name") or node.get("id") or name})
            for v in node.values():
                users(v, kind, name)
        elif isinstance(node, list):
            for v in node:
                users(v, kind, name)
    for sub in ("npcs", "notes", "forks", "props", "rest_points"):
        for f in sorted((root / "data" / sub).glob("*.json")):
            users(json.loads(f.read_text(encoding="utf-8")), sub, f.stem)
    played_in = {}
    for r in rooms:
        for k in ("intro_cutscene", "outro_cutscene"):
            if r.get(k):
                played_in.setdefault(r[k], []).append(r["name"])
    backdrops = json.loads((root / "data/backdrops.json").read_text(encoding="utf-8"))
    # the dialogue windows' styles and the speakers' portraits (scripts/ui/dialogue_look.gd):
    # a speaker without one of its own shows the avatar of the person bearing its name
    looks_file = root / "data/dialogue_looks.json"
    looks = json.loads(looks_file.read_text(encoding="utf-8")) if looks_file.exists() else {"styles": {"default": {}}, "speakers": {}}
    faces = {}
    for f in sorted((root / "data/npcs").glob("*.json")):
        npc = json.loads(f.read_text(encoding="utf-8"))
        if npc.get("name") and npc.get("avatar"):
            faces[npc["name"]] = npc["avatar"]
    portraits = sorted("res://" + f.relative_to(root).as_posix() for f in (root / "assets/portraits").glob("*.png")
                       if "atlas" not in f.stem)
    return {"cutscenes": scenes, "dialogues": dialogues, "strings": strings,
            "looks": looks, "faces": faces, "portraits": portraits,
            "speakers": sorted(k for k in strings if k.startswith("SPEAKER_")),
            "playlists": json.loads((root / "data/music/playlists.json").read_text(encoding="utf-8")),
            "played_in": played_in, "used_by": used_by, "room_order": room_order(root),
            "families": sorted(backdrops.get("families", {}).keys()), "pictures": sorted(backdrops.get("rooms", {}).keys())}


def enemies(root: Path, strings):
    """What the enemy wizard offers to inherit from: every enemy with its fight in short,
    where the game brings it out (`where`, empty: nowhere) and whose character holds the
    strips it is drawn with (`char`, see strip_owners) — the studio's «Персонажи» lists them all."""
    raw, resolved = game_enemies(root)
    places, (owner, _own) = enemy_places(root, raw, resolved, strings), strip_owners(root, raw, resolved)
    out = []
    for f in sorted((root / "data/enemies").glob("*.json")):
        e = json.loads(f.read_text(encoding="utf-8"))
        attacks = e.get("attacks", []) + ([e["attack"]] if "attack" in e else [])
        name = strings.get(e.get("name", ""), {})
        out.append({"id": e.get("id", f.stem), "extends": e.get("extends"), "behaviour": e.get("behaviour", "walker"),
                    "voice": e.get("voice", e.get("id", f.stem)),
                    "boss": bool(e.get("boss")), "tags": e.get("tags", []), "hp": e.get("hp"), "speed": e.get("speed"),
                    "material": e.get("material"), "attacks": sorted({a.get("type", "?") for a in attacks}),
                    "name": {"ru": name.get("ru", ""), "en": name.get("en", "")},
                    "sprite": e.get("sprite", {}).get("cell"), "bestiary": e.get("bestiary", True),
                    "where": places.get(e.get("id", f.stem), []), "char": owner.get(e.get("id", f.stem)),
                    "tint": enemy_sprite(resolved, resolved.get(e.get("id", f.stem), {}).get("sprite", {})).get("tint")})
    return out


def shared(kind, game_ids=()):
    """Projects saved from the studio into tools/studio/projects/<kind>/.

    A shared cutscene with a game cutscene's id is the same scene once its pull
    request is in, so the game's file wins; a shared character or background
    with a game id is somebody's variant and is listed beside it."""
    out = []
    for f in sorted((STUDIO / "projects" / kind).glob("*.json")):
        p = json.loads(f.read_text(encoding="utf-8"))
        p["shared"] = f.relative_to(ROOT).as_posix()
        p["rev"] = rev(ROOT, p["shared"])
        if p.get("id") in game_ids:
            if kind == "cuts":
                continue
            p["id"] = "shared_" + p["id"]
        out.append(p)
    return out


## Files a generator writes only a part of, reading the rest as its input: the studio may
## edit the rest. build_bestiary_assets.py writes_cells() sets "sprite.cell" and "pad_y" in
## the archetype tree and keeps every other key as it found it — the attacks are input.
GENERATOR_INPUTS = {"data/enemy_archetypes/tree.json"}


def generated(root: Path):
    """Every tracked file a generator owns, straight from tools/check_generators.py,
    so the studio refuses exactly what CI would fail on."""
    spec = importlib.util.spec_from_file_location("check_generators", root / "tools/check_generators.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    files, owners = [], []
    for name, argv, paths, _slow in mod.GENERATORS:
        owners.append({"name": name, "script": argv[0], "paths": paths})
        listed = subprocess.run(["git", "ls-files", "--"] + paths, cwd=root, capture_output=True, text=True, check=True)
        files += listed.stdout.split()
    # files the studio itself created in a generator's folder stay editable from the studio
    registry = STUDIO / "projects" / "files.json"
    owned = set(json.loads(registry.read_text(encoding="utf-8"))) if registry.exists() else set()
    return sorted(set(files) - owned - GENERATOR_INPUTS), owners


def overridable(files, owners):
    """The generated PNGs the studio may edit — as an override (tools/art/studio_overrides.py)
    that their generator lays over its own picture, never the file itself."""
    sys.path.insert(0, str(STUDIO.parents[0] / "art"))
    from studio_overrides import OVERRIDABLE
    roots = [p for g in owners if g["name"] in OVERRIDABLE for p in g["paths"]]
    return [f for f in files if f.lower().endswith(".png")
            and any(f == p or f.startswith(p.rstrip("/") + "/") for p in roots)]


def overrides(root: Path):
    """The studio's edits of generated pictures, as tools/art/studio_overrides.py keeps them."""
    path = root / "tools/studio/overrides/overrides.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


# ----------------------------------------------------------- living backdrops
# data/backdrops.json keys a rule by room scene name or by picture file name;
# the studio's zone editor needs the picture each key lights.
LIFE_NODES = ["Painting", "Parallax/Backdrop", "Interior/AuthoredMasonry/ChurchPainting",
              "Interior/AuthoredMasonry/PreacherPainting"]   # BackdropLife.painting_of
LIFE_SCENES = {"main_menu": ("scenes/ui/main_menu.tscn", "Layers/Background"),
               "arena": ("scenes/pvp/arena.tscn", "Parallax/Backdrop")}
# the church and the nave paint their wall in code (scripts/rooms/interior_architecture.gd PAINTINGS)
LIFE_INTERIORS = r'const PAINTINGS := \{(.*?)\}'
LIFE_DIRS = ["assets/cutscenes", "assets/ui/transitions"]   # cutscene panels, passage cards


def _scene_texture(root: Path, scene: Path, paths):
    ext, nodes = parse_tscn(scene.read_text(encoding="utf-8"))
    by_path = {}
    for n in nodes[1:]:
        parent = n["parent"] or "."
        by_path[n["name"] if parent == "." else f"{parent}/{n['name']}"] = n
    for want in paths:
        n = by_path.get(want)
        m = n and re.match(r'ExtResource\("([^"]+)"\)', n["props"].get("texture", ""))
        if m and m[1] in ext:
            return ext[m[1]]
    return None


def life(root: Path):
    rules = json.loads((root / "data/backdrops.json").read_text(encoding="utf-8"))
    src = (root / "scripts/rooms/backdrop_life.gd").read_text(encoding="utf-8")
    block = re.search(r"const KINDS := \{(.*?)\n\}", src, re.S)[1]
    kinds = {k: {"index": int(i), "strength": float(st), "speed": float(sp)}
             for k, i, st, sp in re.findall(r'"(\w+)": \[(\d+), ([\d.]+), ([\d.]+)\]', block)}
    pictures = {}
    for scene in room_scenes(root):
        res = _scene_texture(root, scene, LIFE_NODES)
        if res:
            pictures[scene.stem] = {"res": res, "kind": "room"}
    inner = re.search(LIFE_INTERIORS, (root / "scripts/rooms/interior_architecture.gd").read_text(encoding="utf-8"), re.S)
    for key, res in re.findall(r'"(\w+)": "(res://[^"]+)"', inner[1] if inner else ""):
        pictures[key] = {"res": res, "kind": "room"}
    for key, (scene, node) in LIFE_SCENES.items():
        res = (root / scene).exists() and _scene_texture(root, root / scene, [node])
        if res:
            pictures[key] = {"res": res, "kind": "scene"}
    # a room the studio composed has a picture of its own, keyed as BackdropLife.room_key keys it
    for p in sorted((root / "assets/levels/composed").glob("*.png")):
        if not p.stem.endswith("_backfill"):
            pictures["composed/" + p.stem] = {"res": "res://" + p.relative_to(root).as_posix(), "kind": "room"}
    for d in LIFE_DIRS:
        for p in sorted((root / d).glob("*.png")):
            pictures.setdefault(p.stem, {"res": "res://" + p.relative_to(root).as_posix(), "kind": "picture"})
    out = []
    for key, pic in pictures.items():
        size = _size(root, pic["res"])
        if not size:
            continue
        rule = rules.get("rooms", {}).get(key)
        out.append({"key": key, "kind": pic["kind"], "res": pic["res"], "url": asset_url(pic["res"]),
                    "w": size[0], "h": size[1], "has_rule": rule is not None})
    return {"kinds": kinds, "families": rules.get("families", {}), "lean": rules.get("lean", {}),
            "max_zones": int(re.search(r"const MAX_ZONES := (\d+)", src)[1]), "pictures": out}


# ------------------------------------------------------- platform pieces
# assets/decor/platforms: the pieces tools/rooms/generate_rooms.py lays over a
# room's colliders (terrain_nodes). A piece she redraws at the same size goes
# straight in: the scenes name the file, the manifest keeps its size and top.
def tiles(root: Path):
    manifest = json.loads((root / "assets/decor/platforms/manifest.json").read_text(encoding="utf-8"))
    uses = {name: {} for name in manifest}
    for scene in room_scenes(root):
        text = scene.read_text(encoding="utf-8")
        for name in manifest:
            n = text.count(f'ExtResource("piece_{name}")')
            if n:
                uses[name][scene.stem] = n
    src = (root / "tools/rooms/generate_rooms.py").read_text(encoding="utf-8")
    overlap = int(re.search(r"^OVERLAP = (\d+)", src, re.M)[1])
    played = room_order(root)
    return {"overlap": overlap, "played": played, "pieces": [dict(name=name, res=f"res://assets/decor/platforms/{name}.png",
                                                url=f"assets/decor/platforms/{name}.png", uses=uses[name], **info)
                                           for name, info in manifest.items()]}


# ------------------------------------------------- seams of widened panels
# A painted room is wider than its panel: generate_rooms.py inserts a band at
# each ROOM_EXPANSION_CUTS cut, quilted from the painting either side of it.
# Every pixel of a band is a copy of one 160 px away, so a banner or a window
# near a cut stands there twice. The studio shows the bands, worst first, and
# lets her repaint one; it goes in as an override of the wide painting.
def seams(root: Path):
    import ast
    from PIL import ImageFilter, ImageStat
    src = (root / "tools/rooms/generate_rooms.py").read_text(encoding="utf-8")
    start = src.index("ROOM_EXPANSION_CUTS = {")
    cuts = ast.literal_eval(src[src.index("{", start):src.index("\n}\n", start) + 2])
    sys.path.insert(0, str(root / "tools/rooms"))
    from painted_rooms import PAINTED
    out = {}
    for room, points in cuts.items():
        r = PAINTED.get(room, {})
        if "painting" not in r:
            continue
        res = f"res://assets/levels/{r['painting']}_wide.png"
        path = res_to_path(root, res)
        if not path.exists():
            continue
        amount = 120 if r.get("interior") else 160
        im = Image.open(path).convert("L")
        detail = lambda box: ImageStat.Stat(im.crop(box).filter(ImageFilter.FIND_EDGES)).mean[0]
        whole = max(1.0, detail((0, 0, im.width, im.height)))
        bands = []
        for i, cut in enumerate(points):
            x0 = cut + i * amount
            # how busy the band is against the painting as a whole: fog and dark stone hide a twin, banners do not
            bands.append({"x": x0, "w": amount, "cut": cut, "score": round(detail((x0, 0, x0 + amount, im.height)) / whole, 2)})
        out[res] = {"room": room, "w": im.width, "h": im.height, "bands": bands}
    return out


def game_enemies(root: Path):
    """Every enemy as the game builds it (data_loader.gd): extends first, then the archetype
    overlay. -> ({id: its own file}, {id: resolved})"""
    raw = {}
    for f in sorted((root / "data/enemies").glob("*.json")):
        e = json.loads(f.read_text(encoding="utf-8"))
        raw[e.get("id", f.stem)] = e
    resolved = {}
    for eid, e in raw.items():
        merged = json.loads(json.dumps(raw.get(e.get("extends"), {}))) if e.get("extends") else {}
        for k, v in e.items():
            merged[k] = {**merged[k], **v} if isinstance(merged.get(k), dict) and isinstance(v, dict) else v
        resolved[eid] = merged
    tree = root / "data/enemy_archetypes/tree.json"
    for over in (json.loads(tree.read_text(encoding="utf-8")) if tree.exists() else []):
        if over.get("id") in resolved and "sprite" in over:
            resolved[over["id"]]["sprite"] = {**resolved[over["id"]].get("sprite", {}), **over["sprite"]}
    return raw, resolved


def enemy_sprite(resolved, sprite):
    """The sprite a body is drawn with (Enemy._setup_sprite): "like" borrows another creature's
    strips, its own keys laid over them."""
    if "like" in sprite:
        sprite = {**resolved.get(sprite["like"], {}).get("sprite", {}), **{k: v for k, v in sprite.items() if k != "like"}}
    return sprite


def enemy_body(root: Path, resolved, sprite):
    """What the preview needs to draw a body: its strips, cell, fps, scale (Enemy._setup_sprite)."""
    sprite = enemy_sprite(resolved, sprite)
    anims = {a: asset_url(res) for a, res in sprite.get("animations", {}).items() if _size(root, res)}
    if not anims or "cell" not in sprite:
        return None
    return {"cell": sprite["cell"], "fps": sprite.get("fps", 6), "scale": sprite.get("scale", 1.0),
            "pad_y": sprite.get("pad_y", 0), "tint": sprite.get("tint"), "anims": anims,
            "frames": {a: _size(root, res)[0] // sprite["cell"][0] for a, res in sprite.get("animations", {}).items() if a in anims}}


def enemy_places(root: Path, raw, resolved, strings):
    """Where the hero meets each enemy of data/enemies, in words for the studio's lists:
    {id: ["Глава I · Кладбище, Болото", "призывает: Офаним", …]}; an empty list is a
    creature the game never brings out (a leftover or a draft). In a room of any night
    (an EnemySpawn, or a guardian of a prop standing there), summoned, split off, sealed
    or promoted to (vials, omens) by one that is, or the practice yard's own (behaviour dummy)."""
    ru = lambda key: strings.get(key, {}).get("ru", "") or key
    chapter = {}
    for f in sorted((root / "data/chapters").glob("*.json")):
        for area in json.loads(f.read_text(encoding="utf-8")):
            for res in area.get("rooms", []):
                chapter[res] = (ru(area.get("chapter", "")).split(" · ")[0], ru(area.get("title", "")))
    props = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (root / "data/props").glob("*.json")}
    seen, why = {}, {}

    def meet(eid, chap, area):
        if eid in raw:
            areas = seen.setdefault(eid, {}).setdefault(chap, [])
            if area not in areas:
                areas.append(area)
    for res in game_rooms(game_doc(root)):
        path = res_to_path(root, res)
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        chap, area = chapter.get(res, ("", path.stem))
        for eid in re.findall(r'^enemy_id = &?"([^"]+)"', text, re.M):
            meet(eid, chap, area)
        for pid in re.findall(r'^prop_id = &?"([^"]+)"', text, re.M):
            for wave in props.get(pid, {}).get("guardians", []):
                for g in wave:
                    meet(g[0], chap, area)
    for eid, e in resolved.items():
        if e.get("behaviour") == "dummy":
            why.setdefault(eid, []).append("тренировочный двор")
    promote = {}  # (common, elite) -> what promotes it
    for d, label in (("vials", "чаша гнева"), ("omens", "знамение")):
        for f in sorted((root / "data" / d).glob("*.json")):
            doc = json.loads(f.read_text(encoding="utf-8"))
            for entry in doc if isinstance(doc, list) else [doc]:
                for a, b in entry.get("rules", {}).get("promote", {}).items():
                    if label not in promote.setdefault((a, b), []):
                        promote[(a, b)].append(label)
    tree = root / "data/enemy_archetypes/tree.json"
    attacks = {e["id"]: e["attacks"] for e in (json.loads(tree.read_text(encoding="utf-8")) if tree.exists() else []) if "attacks" in e}

    def brings(eid):
        """-> [(other id, how it comes)]: what this one brings onto the floor."""
        e, out = resolved[eid], []
        if e.get("summons", {}).get("id"):
            out.append((e["summons"]["id"], "его призывает:"))
        own = attacks.get(eid) or e.get("attacks", []) + ([e["attack"]] if "attack" in e else [])
        out += [(a["id"], "его призывает:") for a in own if a.get("type") == "summon" and a.get("id")]
        if e.get("on_death", {}).get("type") == "split":
            out.append((e["on_death"].get("into"), "остаётся от:"))
        if e.get("seal_phase", {}).get("seal"):
            out.append((e["seal_phase"]["seal"], "печати ставит:"))
        return out
    live = set(seen) | set(why)
    while True:
        grew = False
        for eid in sorted(live):
            for other, how in brings(eid):
                line = f"{how} {ru(raw[eid].get('name', eid))}"
                if other in raw and line not in why.setdefault(other, []):
                    why[other].append(line)
                    grew = grew or other not in live
                    live.add(other)
        for (a, b), by in promote.items():
            if a in live and b in raw:
                line = f"элита вместо: {ru(raw[a].get('name', a))} ({', '.join(by)})"
                if line not in why.setdefault(b, []):
                    why[b].append(line)
                    grew = grew or b not in live
                    live.add(b)
        if not grew:
            break
    return {eid: [f"{c} · {', '.join(areas)}" if c else ", ".join(areas) for c, areas in seen.get(eid, {}).items()] + why.get(eid, [])
            for eid in raw}


# ---------------------------------------------------------- ranged attacks
# data/projectiles.json is how every bolt looks; the attacks that loose them are
# the ranged ones in data/enemies and the bolt skills in data/abilities. The
# studio's «Снаряды» edits all three, so it needs each attack's place in its file.
def projectiles(root: Path, strings):
    doc = json.loads((root / "data/projectiles.json").read_text(encoding="utf-8"))
    sheets = {}
    for look in doc["styles"].values():
        res = look.get("sheet", "")
        size = _size(root, res)
        if size:
            sheets[res] = {"url": asset_url(res), "w": size[0], "h": size[1]}
    name = lambda key: {k: strings.get(key, {}).get(k, "") or key for k in ("ru", "en")}
    raw, resolved = game_enemies(root)
    body = lambda sprite: enemy_body(root, resolved, sprite)
    hero = {"cell": [128, 64], "fps": 10, "scale": 1.0, "hero": True,
            "anims": {a: f"assets/sprites/elian_{a}.png" for a in ("idle", "attack") if (root / f"assets/sprites/elian_{a}.png").exists()}}
    dummy = body(resolved.get("training_dummy", {}).get("sprite", {}))
    users, roster = [], []
    places = enemy_places(root, raw, resolved, strings)
    tree = root / "data/enemy_archetypes/tree.json"
    tree_entries = json.loads(tree.read_text(encoding="utf-8")) if tree.exists() else []
    for eid in sorted(raw):
        e, at = raw[eid], attack_source(eid, raw, tree_entries)
        if at is None:
            continue
        b = body(resolved.get(eid, {}).get("sprite", {}))
        roster.append({"id": eid, "name": name(e.get("name", "")), "body": b, "boss": bool(resolved[eid].get("boss")),
                       "material": resolved[eid].get("material", "cloth"),
                       "behaviour": resolved[eid].get("behaviour", "walker"), "source": at, "where": places[eid],
                       "attacks": [{"type": a.get("type"), "animation": a.get("animation")} for a in at["items"]]})
        for i, a in enumerate(at["items"]):
            if a.get("type") == "ranged":
                users.append({"kind": "enemy", "id": eid, "name": name(e.get("name", "")), "index": i,
                              "file": at["file"], "path": None if at["inherited"] else at["path"] + ([at["key"]] if at["single"] else [at["key"], i]),
                              "attack": a, "boss": bool(resolved[eid].get("boss")), "body": b})
    for f in sorted((root / "data/abilities").glob("*.json")):
        for gi, g in enumerate(json.loads(f.read_text(encoding="utf-8"))):
            for ei, eff in enumerate(g.get("effects", [])):
                if eff.get("type") == "skill" and eff.get("skill", {}).get("kind") == "bolt":
                    users.append({"kind": "gift", "id": g.get("id", ""), "name": name(g.get("name", "")),
                                  "file": f"data/abilities/{f.name}", "path": [gi, "effects", ei, "skill"], "attack": eff["skill"],
                                  "body": hero})
    return {"styles": doc["styles"], "sheets": sheets, "users": users, "roster": roster, "hero": hero, "dummy": dummy}


def attack_source(eid, raw, tree_entries):
    """Where the attacks an enemy fights with are written (data_loader.gd: extends, then the
    archetype overlay, whose "attacks" replace the file's and drop its single "attack").
    {file, path, key, items, single, inherited, over?}: path is the object holding `key` in `file`;
    an inherited list (extends, nothing of its own) is written into the enemy's own file."""
    for i, over in enumerate(tree_entries):
        if over.get("id") == eid and "attacks" in over:
            return {"file": "data/enemy_archetypes/tree.json", "path": [i], "key": "attacks", "items": over["attacks"],
                    "single": False, "inherited": False}
    e, own = raw[eid], f"data/enemies/{eid}.json"
    if "attacks" in e:
        return {"file": own, "path": [], "key": "attacks", "items": e["attacks"], "single": False, "inherited": False}
    base = raw.get(e.get("extends"))
    if "attack" in e:
        # a single "attack" over a base's single "attack" is laid over it key by key
        # (data_loader.gd merges a dictionary one level deep): the studio shows and edits
        # the attack the game fights with, and writes back only what differs ("over")
        if base is not None and isinstance(base.get("attack"), dict) and isinstance(e["attack"], dict):
            return {"file": own, "path": [], "key": "attack", "items": [{**base["attack"], **e["attack"]}], "single": True,
                    "inherited": False, "over": f"data/enemies/{e['extends']}.json"}
        return {"file": own, "path": [], "key": "attack", "items": [e["attack"]], "single": True, "inherited": False}
    if base is not None:
        items = base.get("attacks") or ([base["attack"]] if "attack" in base else [])
        if items:
            return {"file": own, "path": [], "key": "attacks", "items": items, "single": False, "inherited": True,
                    "from": f"data/enemies/{e['extends']}.json", "from_key": "attacks" if "attacks" in base else "attack"}
    return None


# ---------------------------------------------------------- action particles
# data/action_fx.json: particles on any action of any body (scripts/fx/action_fx.gd).
# The studio's «Частицы» needs every body it can dress — Elian and each creature, drawn
# as in «Снаряды» — with its animations, and the events the game names.
def action_fx(root: Path, strings, shots):
    doc = json.loads((root / "data/action_fx.json").read_text(encoding="utf-8"))
    src = (root / "scripts/fx/action_fx.gd").read_text(encoding="utf-8")
    consts = {k: re.findall(r'"(\w+)"', re.search(rf"const {k} := \[(.*?)\]", src)[1]) for k in ("KINDS", "ANCHORS", "EVENTS")}
    hero_anims, hero_fps = {}, {}
    for a in hero(root)["animations"]:
        res = a.get("file", "")
        if res and _size(root, res) and _size(root, res)[1] == 64:
            hero_anims[a["name"]] = asset_url(res)
            hero_fps[a["name"]] = a.get("fps", 10)
    bodies = [{"key": "elian", "name": {"ru": "Элиан", "en": "Elian"}, "hero": True, "events": consts["EVENTS"],
               "body": {"cell": [128, 64], "fps": 10, "fps_of": hero_fps, "scale": 1.0, "hero": True, "anims": hero_anims}}]
    for r in shots["roster"]:
        if r.get("body"):
            bodies.append({"key": r["id"], "name": r["name"], "boss": r["boss"], "events": [], "body": r["body"]})
    return {"rules": doc.get("bodies", {}), "kinds": consts["KINDS"], "anchors": consts["ANCHORS"], "bodies": bodies}


# ---------------------------------------------------------- blood and torn limbs
# data/gore.json (scripts/fx/gore.gd): what each material bleeds, and a body's own keys over it.
# The studio's «Кровь» shows it on the same bodies «Частицы» dresses, each with its material.
def gore(root: Path, pfx, shots):
    doc = json.loads((root / "data/gore.json").read_text(encoding="utf-8"))
    src = (root / "scripts/fx/gore.gd").read_text(encoding="utf-8")
    keys = re.findall(r'"(\w+)"', re.search(r"const KEYS := \[(.*?)\]", src, re.S)[1])
    start = src.index("{", src.index("const DEFAULTS :="))
    depth, end = 0, start
    for end, ch in enumerate(src[start:], start):  # the table nests (cuts): balance the braces
        depth += {"{": 1, "}": -1}.get(ch, 0)
        if depth == 0:
            break
    defaults = json.loads(src[start:end + 1].replace("\n", " ").replace("\t", ""))
    # the blows (Gore.MOVES) and what a blow the table leaves out does (MOVE_DEFAULTS)
    moves = re.findall(r'"(\w+)"', re.search(r"const MOVES := \[(.*?)\]", src, re.S)[1])
    move_defaults = json.loads(re.search(r"const MOVE_DEFAULTS := (\{.*?\})", src, re.S)[1].replace("\n", " ").replace("\t", ""))
    material ={r["id"]: r.get("material", "cloth") for r in shots["roster"]}
    bodies = [{**b, "material": "flesh" if b["key"] == "elian" else material.get(b["key"], "cloth")} for b in pfx["bodies"]]
    return {"materials": doc.get("materials", {}), "bodies_rules": doc.get("bodies", {}), "keys": keys,
            "defaults": defaults, "bodies": bodies, "moves": doc.get("moves", {}), "move_names": moves,
            "move_defaults": move_defaults}


def world(root, rooms):
    files = {p.relative_to(root).as_posix(): json.loads(p.read_text(encoding="utf-8"))
             for p in sorted((root / "data").rglob("*.json"))}
    # a game pack's rooms take the studio's additions from its own table (generate_rooms.py --pack)
    own = root / "content/rooms/studio_rooms.json"
    table = own if (root / "content/data/game.json").exists() else root / "tools/rooms/studio_rooms.json"
    files["tools/rooms/studio_rooms.json"] = json.loads(table.read_text()) if table.exists() else {}
    return {"files": files, "enemies": sorted(p.stem for p in (root / "data/enemies").glob("*.json"))}


def composer(root: Path):
    """The «Конструктор» (js/composer.js, tools/rooms/compose.py): the panels a room may be put
    together from, every painted room's own geometry in its panel's pixels, what is composed
    already, and the numbers its preview needs (the grid, the hero's reach for check_reach).
    The room tools run in the engine itself, never a game view: the engine's rooms name the
    engine's people, which a pack need not inherit; content/ (the pack) is the same there."""
    sys.path.insert(0, str(ROOT / "tools/rooms"))
    import compose
    import front
    import generate_rooms
    import painted_rooms
    owned = compose.owners(painted_rooms.PAINTED, generate_rooms.DEPTH_WINDOWS)
    by_painting = {}
    rooms = {}
    for name, room in painted_rooms.PAINTED.items():
        if "painting" not in room:
            continue
        by_painting.setdefault(room["painting"], name)
        rooms[name] = {"painting": room["painting"],
                       # a thing standing in a seam ("wide") has no place in the bare panel
                       **{k: [list(v) for v in room.get(k, []) if "wide" not in v] for k in ("ground", "ledges", "platforms", "crumbling_platforms", "ramps", "hazards", "spawns", "props", "npcs")},
                       "player": list(room["player"]), "door": list(room["door"])}
    panels = []
    for path in sorted((root / "assets/levels").glob("*.png")) + sorted((root / "assets/levels/panels").glob("*.png")):
        stem = path.relative_to(root / "assets/levels").with_suffix("").as_posix()
        if stem.endswith("_wide"):
            continue
        with Image.open(path) as im:
            if im.size != compose.CELL:
                continue
        plate = compose.plate_path(stem)
        lights = compose.auto_lights({"cells": [{"painting": stem, "col": 0, "row": 0}]})
        panels.append({"stem": stem, "url": f"assets/levels/{stem}.png", "room": by_painting.get(stem, ""),
                       # what a cell of it brings: the far openings of its room, the plate behind them, its candles
                       "windows": [{"index": i, "points": [list(p) for p in polygon]} for i, polygon in owned.get(stem, (0, []))[1]],
                       "strength": owned[stem][0] if stem in owned else None,
                       "plate": Path(plate).relative_to(compose.ROOT).as_posix(),
                       "lights": [list(light) for light in lights]})
    reach = {k: getattr(painted_rooms, k) for k in ("JUMP_UP", "JUMP_ACROSS", "DROP_ACROSS", "RUN_SPEED", "JUMP_VELOCITY", "GRAVITY", "BODY_WIDTH", "REACH_MARGIN")}
    reach["FLYERS"] = sorted(painted_rooms.FLYERS)
    ids = lambda folder: sorted(p.stem for p in (root / "data" / folder).glob("*.json"))
    return {"cell": list(compose.CELL), "max": [compose.MAX_COLS, compose.MAX_ROWS], "seam": compose.SEAM,
            "panels": panels, "rooms": rooms, "reach": reach,
            # a game pack composes into its own table, starting from none of Ashes'
            "composed": compose.load(compose.PACK_TABLE) if (root / "content/data/game.json").exists() else compose.load(),
            "enemies": ids("enemies"), "props": ids("props"), "npcs": ids("npcs"),
            "front": {"depth": list(front.DEPTH), "max": front.MAX_PIECES}, "window_depth": list(compose.WINDOW_DEPTH)}


def write(out: Path, rel: str, data):
    path = out / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return rel


def head_sha(root: Path):
    r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True)
    return r.stdout.strip()


def _gd_list(source: str, name: str):
    """A const list of strings from a GDScript source (`const NAME := [...]`)."""
    m = re.search(r"const %s := \[(.*?)\]" % name, source, re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


def _gd_bounds(source: str, name: str):
    """A const dictionary of [low, high] pairs from a GDScript source (`const NAME := {"k": [a, b], ...}`)."""
    m = re.search(r"const %s := \{(.*?)\}" % name, source, re.S)
    return {k: [float(a), float(b)] for k, a, b in re.findall(r'"(\w+)": \[(-?[\d.]+), (-?[\d.]+)\]', m.group(1))} if m else {}


def gamedata(root: Path, strings):
    """What the studio's later editors read beside world.json (js/gamedata.js): every line of
    strings.csv, the lists the validator checks against (so a draft is refused in the browser
    before CI refuses it), the music library and each room's mood and size, and the
    flags GDScript itself reads or writes (the story map)."""
    validator = (root / "scripts/tools/validate_data.gd").read_text(encoding="utf-8")
    caps_src = (root / "scripts/combat/ability_system.gd").read_text(encoding="utf-8")
    caps = {k: [float(a), float(b)] for k, a, b in re.findall(r'"(\w+)": \[(-?[\d.]+), (-?[\d.]+)\]', caps_src.split("const CAPS := {", 1)[1].split("\n}", 1)[0])}
    deeds = (root / "scripts/meta/achievements.gd").read_text(encoding="utf-8")
    fetch = (root / "tools/audio/fetch_music.py").read_text(encoding="utf-8")
    existing = ast.literal_eval(re.search(r"EXISTING = (\{.*?\n\})", fetch, re.S).group(1))
    manifest = json.loads((root / "tools/audio/music_manifest.json").read_text(encoding="utf-8"))
    music = root / "assets/audio/music"
    rooms = {}
    for path in sorted((root / "scenes/rooms").glob("*.tscn")):
        whole = path.read_text(encoding="utf-8")
        m = re.search(r'^music = "([^"]*)"', whole, re.M)  # on the room's Ambient
        text = whole[whole.find('[node name="Room"'):]  # the room's own size, not a sub-resource's
        text = text[:text.find("\n[", 1)]
        w = re.search(r"^width = (\d+)", text, re.M)
        h = re.search(r"^height = (\d+)", text, re.M)
        rooms[path.stem] = {"music": m.group(1) if m else "", "width": int(w.group(1)) if w else 0, "height": int(h.group(1)) if h else 0}
    return {
        "strings": strings,
        "stats": _gd_list(validator, "STATS"), "item_stats": _gd_list(validator, "ITEM_STATS"),
        "techniques": _gd_list(validator, "TECHNIQUES"), "caps": caps,
        "counters": _gd_list(deeds, "COUNTERS"),
        # flags something other than a branch reads: the game's own list (data/game.json "flags_read")
        "flags_read_in_code": json.loads((root / "data" / "game.json").read_text()).get("flags_read", []),
        "flags_set_in_code": _gd_list(validator, "FLAGS_SET_IN_CODE"),
        "flags_for_tests": _gd_list(validator, "FLAGS_FOR_TESTS"),
        "music": {"existing": existing, "tracks": [{k: t[k] for k in ("slug", "title", "author", "license", "playlists")} for t in manifest["tracks"]],
                  "files": {p.stem: p.name for p in sorted(music.iterdir()) if p.suffix in (".mp3", ".ogg", ".wav")}},
        "rooms": rooms,
        # what _check_weapon bounds a weapon by (the studio's «Оружие»), the icons one may wear,
        # and every room scene the game has (the «Ночи» tab adds one to a night)
        "weapon": {"bounds": _gd_bounds(validator, "WEAPON_BOUNDS"), "step_bounds": _gd_bounds(validator, "WEAPON_STEP_BOUNDS"),
                   "needs": _gd_list(validator, "WEAPON_STEP_NEEDS"), "animations": _gd_list(validator, "WEAPON_ANIMATIONS"),
                   "arcs": _gd_list(validator, "WEAPON_ARCS")},
        "icons": sorted("res://" + p.relative_to(root).as_posix() for p in (root / "assets/icons").rglob("*.png")),
        "scenes": ["res://" + p.relative_to(root).as_posix() for p in room_scenes(root)],
    }


def write(out: Path, rel: str, data):
    path = out / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return rel


def head_sha(root: Path):
    r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True)
    return r.stdout.strip()


def build(root: Path, out: Path, asset_base: str, branch: str = "main", sha: str = "", pack: dict | None = None):
    """`pack` (docs/GAME_PACKS.md): {"repo", "branch", "sha", "content_base", "engine": {"repo", "sha"}} when
    `root` is a game pack laid over the engine — meta.json then names the pack's repository, which the
    studio writes to, and the URL its own files (content/…) are read from."""
    strings = load_strings(root)
    chars = [hero(root)] + bestiary(root, strings)
    chars += shared("chars", {c["id"] for c in chars})
    write(out, "list.json", [write(out, f"chars/{c['id']}.sprite.json", c) for c in chars])
    rooms = [room_project(root, p) for p in room_scenes(root)]
    rooms = [r for r in rooms if r["layers"]]
    rooms += shared("bgs", {r["id"] for r in rooms})
    write(out, "rooms_list.json", [write(out, f"rooms/{r['id']}.bg.json", r) for r in rooms])
    write(out, "world.json", world(root, rooms))
    write(out, "library.json", library(root))
    write(out, "life.json", life(root))
    write(out, "tiles.json", tiles(root))
    write(out, "seams.json", seams(root))
    write(out, "composer.json", composer(root))
    shots = projectiles(root, strings)
    write(out, "projectiles.json", shots)
    write(out, "attacks.json", {"roster": shots["roster"]})
    pfx = action_fx(root, strings, shots)
    write(out, "action_fx.json", pfx)
    write(out, "gore.json", gore(root, pfx, shots))
    write(out, "audio.json", audio(root, strings))
    write(out, "enemies.json", enemies(root, strings))
    write(out, "gamedata.json", gamedata(root, strings))
    st = story(root, strings, [r for r in rooms if r.get("origin", {}).get("kind") == "game"])
    st["cutscenes"] += shared("cuts", {c["id"] for c in st["cutscenes"]})
    write(out, "cutscenes.json", st)
    files, owners = generated(root)
    repo = (pack or {}).get("repo") or REPO
    owner, name = repo.split("/")
    game = game_doc(root)
    write(out, "meta.json", {"repo": repo, "branch": branch, "assetBase": asset_base, "sha": sha or head_sha(root),
                             "site": f"https://{owner.lower()}.github.io/{name}/",
                             "game": {"id": game.get("id", ""), "name": game.get("name", "")},
                             **({"pack": pack, "contentBase": pack.get("content_base", "")} if pack else {}),
                             "generated": files, "generators": owners,
                             "overridable": overridable(files, owners), "overrides": overrides(root),
                             "generatorInputs": sorted(GENERATOR_INPUTS)})
    return {"chars": len(chars), "rooms": len(rooms), "cutscenes": len(st["cutscenes"])}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--asset-base", default="../../", help="prefix for asset URLs (default: the repository, when the page is served from its root)")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--sha", default="", help="the commit the data is built from (default: HEAD)")
    ap.add_argument("--out", default=str(STUDIO / "import"))
    ap.add_argument("--repo", default="", help="a game pack's repository (owner/name), when content/ holds one")
    ap.add_argument("--content-base", default="", help="prefix for the pack's own files (content/…): its raw URL, or a local path")
    ap.add_argument("--content-sha", default="", help="the pack's commit (default: content/'s own git HEAD, when it is a checkout)")
    ap.add_argument("--engine-repo", default=REPO)
    a = ap.parse_args()
    root, pack = ROOT, None
    sys.path.insert(0, str(ROOT / "tools" / "packs"))
    from game_view import game_view, pack_game
    if pack_game(ROOT) is not None:
        # a game pack is laid over the engine: read the game it makes (tools/packs/game_view.py)
        root = game_view(ROOT)
        content = (ROOT / "content").resolve()
        content_sha = a.content_sha or (subprocess.run(["git", "rev-parse", "HEAD"], cwd=content, capture_output=True, text=True).stdout.strip()
                                        if (content / ".git").exists() else "")
        pack = {"repo": a.repo, "branch": a.branch, "sha": content_sha, "content_base": a.content_base or a.asset_base + "content/",
                "engine": {"repo": a.engine_repo, "sha": a.sha or head_sha(ROOT)}}
    print(build(root, Path(a.out), a.asset_base, a.branch, a.sha or head_sha(ROOT), pack))


if __name__ == "__main__":
    main()
