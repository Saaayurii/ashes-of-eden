"""Textures laid into a room by hand, from the art studio's «Текстуры».

A room's scene is the generator's (tools/rooms/generate_rooms.py), so what she
does to its pictures is kept as the generator's input, in
tools/rooms/studio_rooms.json, and laid over the scene each time it is written:

    "graveyard_cross": {
      "textures": [                               # pictures of her own choosing
        {"tex": "decor/graveyard/angel_1.png",    # under assets/
         "at": [812, 540],                        # its centre, finished-room px
         "scale": [1.5, 0.8],                     # stretched each way
         "rot": -12,                              # degrees, clockwise
         "flip_h": true, "flip_v": false,
         "layer": "mid",                          # back | mid | front | top
         "z": 0,                                  # nudged within the layer
         "tint": "#c8b8ff", "alpha": 0.9,
         "blend": "mix",                          # mix | add | sub | mul
         "region": [0, 0, 300, 40],               # a crop of the picture, or more
         "repeat": "tile",                        #  than it with tile | mirror
         "filter": "pixel"}                       # pixel | smooth
      ],
      "retouch": {                                # what the generator laid itself
        "DecorMid/tombstone_3_4": {"was": "decor/tombstone_3.png",
                                   "at": [900, 610], "scale": [1, 1.4],
                                   "hidden": false, "tex": "decor/tombstone_5.png"}
      }
    }

Layers: `back` lies over the painting and under the terrain (behind every
platform), `mid` stands with the decor behind the characters, `front` is
over their feet (z 1, like DecorFront), `top` over everything the room draws
(z 3, the front plane's height). A retouch addresses a Sprite2D by its path
from the room's root and remembers the picture it had (`was`): when the
generator lays something else there next time, the edit is reported and left
off rather than landing on the wrong thing. A retouch writes the node's own
properties, so `at` is the node's position as it is (the top-left of a sprite
that is not centred), and its tint and alpha replace the node's modulate whole.
Nothing here touches a collider.
"""
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
## Folders a picture may come from: what the studio's library lists, the props'
## strips and the studio's own uploads (assets/decor/studio/).
TEXTURE = re.compile(r"^(decor|levels|backgrounds|environment|cutscenes|props)/[A-Za-z0-9_][A-Za-z0-9_./-]*\.png$")
LAYERS = {"back": ("StudioBack", 0), "mid": ("StudioMid", 0), "front": ("StudioFront", 1), "top": ("StudioTop", 3)}
BLENDS = {"mix": 0, "add": 1, "sub": 2, "mul": 3}
REPEATS = {"tile": 2, "mirror": 3}
FILTERS = {"pixel": 1, "smooth": 2}
MAX_TEXTURES = 200
SCALE = (0.02, 40.0)
KEYS = {"tex", "at", "scale", "rot", "flip_h", "flip_v", "layer", "z", "tint", "alpha", "blend", "region", "repeat", "filter", "name"}
RETOUCH_KEYS = (KEYS - {"layer", "name"}) | {"was", "hidden"}
NODE = re.compile(r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?')


def _number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _problems(where, t, retouch=False):
    """What is wrong with one texture entry (or a retouch), as sentences."""
    out = []
    keys = RETOUCH_KEYS if retouch else KEYS
    for k in t:
        if k not in keys:
            out.append(f"{where}: unknown key {k!r}")
    for k in ("tex", "was"):
        if k in t and (not isinstance(t[k], str) or not TEXTURE.match(t[k]) or ".." in t[k]):
            out.append(f"{where}: {k} must be a .png under assets/ (decor, levels, backgrounds, environment, cutscenes, props)")
        elif k == "tex" and k in t and not os.path.exists(os.path.join(ROOT, "assets", t[k])):
            out.append(f"{where}: no picture at assets/{t[k]}")
    if not retouch and "tex" not in t:
        out.append(f"{where}: tex is missing")
    if not retouch and "at" not in t:
        out.append(f"{where}: at is missing")
    if "at" in t and not (isinstance(t["at"], list) and len(t["at"]) == 2 and all(_number(v) and abs(v) <= 100000 for v in t["at"])):
        out.append(f"{where}: at is [x, y]")
    if "scale" in t and not (isinstance(t["scale"], list) and len(t["scale"]) == 2
                             and all(_number(v) and SCALE[0] <= v <= SCALE[1] for v in t["scale"])):
        out.append(f"{where}: scale is [sx, sy], each {SCALE[0]}..{SCALE[1]} (flip_h / flip_v mirror it)")
    if "rot" in t and not (_number(t["rot"]) and -360 <= t["rot"] <= 360):
        out.append(f"{where}: rot is degrees, -360..360")
    for k in ("flip_h", "flip_v", "hidden"):
        if k in t and not isinstance(t[k], bool):
            out.append(f"{where}: {k} is true or false")
    if "layer" in t and t["layer"] not in LAYERS:
        out.append(f"{where}: layer is one of {', '.join(LAYERS)}")
    if "z" in t and not (isinstance(t["z"], int) and not isinstance(t["z"], bool) and -10 <= t["z"] <= 10):
        out.append(f"{where}: z is a whole number, -10..10")
    if "tint" in t and not (isinstance(t["tint"], str) and re.match(r"^#[0-9a-fA-F]{6}$", t["tint"])):
        out.append(f"{where}: tint is #rrggbb")
    if "alpha" in t and not (_number(t["alpha"]) and 0 <= t["alpha"] <= 1):
        out.append(f"{where}: alpha is 0..1")
    if "blend" in t and t["blend"] not in BLENDS:
        out.append(f"{where}: blend is one of {', '.join(BLENDS)}")
    if "region" in t and not (isinstance(t["region"], list) and len(t["region"]) == 4 and all(_number(v) for v in t["region"])
                              and t["region"][2] > 0 and t["region"][3] > 0 and max(map(abs, t["region"])) <= 16384):
        out.append(f"{where}: region is [x, y, w, h] in the picture's pixels")
    if "repeat" in t and t["repeat"] not in REPEATS:
        out.append(f"{where}: repeat is tile or mirror")
    if "filter" in t and t["filter"] not in FILTERS:
        out.append(f"{where}: filter is pixel or smooth")
    if "name" in t and not isinstance(t["name"], str):
        out.append(f"{where}: name is text")
    return out


def validate(where, entry):
    """Raise SystemExit naming every problem in a room's `textures` and `retouch`."""
    out = []
    textures = entry.get("textures", [])
    if not isinstance(textures, list):
        out.append(f"{where}: textures is a list")
        textures = []
    if len(textures) > MAX_TEXTURES:
        out.append(f"{where}: at most {MAX_TEXTURES} textures a room")
    for i, t in enumerate(textures):
        out += _problems(f"{where}: texture {i + 1}", t) if isinstance(t, dict) else [f"{where}: texture {i + 1} is an object"]
    retouch = entry.get("retouch", {})
    if not isinstance(retouch, dict):
        out.append(f"{where}: retouch maps a node path to its edit")
        retouch = {}
    for path, t in retouch.items():
        if not re.match(r"^([A-Za-z0-9_]+/)*[A-Za-z0-9_]+$", path):
            out.append(f"{where}: retouch {path!r} is not a node path")
        out += _problems(f"{where}: retouch {path}", t, True) if isinstance(t, dict) else [f"{where}: retouch {path} is an object"]
    if out:
        raise SystemExit("\n".join(out))


def _f(v):
    """A number as the scene files write it: whole numbers without a point."""
    v = round(float(v), 4)
    return str(int(v)) if v == int(v) else repr(v)


def _modulate(t):
    rgb = [int(t["tint"][i:i + 2], 16) / 255 for i in (1, 3, 5)] if "tint" in t else [1, 1, 1]
    return "Color(%s, %s, %s, %s)" % tuple(_f(round(c, 4)) for c in (*rgb, t.get("alpha", 1)))


def _lines(t, ext_of, material_of, full=False):
    """The Sprite2D properties an entry sets, as `key = value` pairs. A retouch (`full`)
    writes every key it has, a default too: it is putting back what the generator set."""
    out = {}
    if "at" in t:
        out["position"] = "Vector2(%s, %s)" % (_f(t["at"][0]), _f(t["at"][1]))
    if "rot" in t and (t["rot"] or full):
        out["rotation"] = repr(round(math.radians(t["rot"]), 6))
    if "scale" in t and (list(t["scale"]) != [1, 1] or full):
        out["scale"] = "Vector2(%s, %s)" % (_f(t["scale"][0]), _f(t["scale"][1]))
    if "z" in t:
        out["z_index"] = str(t["z"])
    if "tint" in t or "alpha" in t:
        out["modulate"] = _modulate(t)
    if t.get("blend", "mix") != "mix" or full and "blend" in t:
        out["material"] = "null" if t["blend"] == "mix" else 'SubResource("%s")' % material_of(t["blend"])
    if "tex" in t:
        out["texture"] = 'ExtResource("%s")' % ext_of(t["tex"])
    if "filter" in t:
        out["texture_filter"] = str(FILTERS[t["filter"]])
    if "repeat" in t:
        out["texture_repeat"] = str(REPEATS[t["repeat"]])
    if "flip_h" in t:
        out["flip_h"] = "true" if t["flip_h"] else "false"
    if "flip_v" in t:
        out["flip_v"] = "true" if t["flip_v"] else "false"
    if "region" in t:
        out["region_enabled"] = "true"
        out["region_rect"] = "Rect2(%s)" % ", ".join(_f(v) for v in t["region"])
    if t.get("hidden") or full and "hidden" in t:
        out["visible"] = "false" if t["hidden"] else "true"
    return out


def _ext_paths(text):
    return {m[0]: m[1] for m in re.findall(r'\[ext_resource type="Texture2D" path="res://assets/([^"]+)" id="([^"]+)"\]', text)}


def apply(text, entry, where="room"):
    """The scene with her textures laid in and her retouches made: (text, warnings).

    `text` is a whole .tscn as generate_rooms.build writes it, before its
    load_steps are counted."""
    entry = entry or {}
    textures, retouch = entry.get("textures", []), entry.get("retouch", {})
    if not textures and not retouch:
        return text, []
    warnings = []
    known = _ext_paths(text)          # picture → an id the scene already has
    ext, subs = {}, {}

    def ext_of(path):
        if path in known:
            return known[path]
        if path not in ext:
            ext[path] = "studio_tex_%d" % (len(ext) + 1)
        return ext[path]

    def material_of(blend):
        subs.setdefault(blend, "studio_blend_%s" % blend)
        return subs[blend]

    # her retouches, node by node
    blocks = re.split(r"\n(?=\[)", text)
    by_path = {}
    for i, block in enumerate(blocks):
        m = NODE.match(block)
        if m:
            parent = m[3]
            by_path[m[1] if parent in (None, ".") else f"{parent}/{m[1]}"] = (i, m[2])
    for path, edit in sorted(retouch.items()):
        if path not in by_path:
            warnings.append(f"{where}: retouch {path}: no such node any more — left off")
            continue
        i, kind = by_path[path]
        if kind != "Sprite2D":
            warnings.append(f"{where}: retouch {path}: a {kind}, not a picture — left off")
            continue
        block = blocks[i]
        tex = re.search(r'^texture = ExtResource\("([^"]+)"\)', block, re.M)
        has = next((p for p, id_ in known.items() if tex and id_ == tex[1]), None)
        if edit.get("was") and has != edit["was"]:
            warnings.append(f"{where}: retouch {path}: the generator lays {has or 'something else'} there now, "
                            f"not {edit['was']} — left off")
            continue
        props = _lines(edit, ext_of, material_of, True)
        if not props:
            continue
        head, *rest = block.split("\n")
        kept = [line for line in rest if line.split(" = ", 1)[0] not in props]
        while kept and not kept[-1]:
            kept.pop()
        blocks[i] = "\n".join([head, *kept, *("%s = %s" % kv for kv in props.items())]) + "\n"
    text = "\n".join(blocks)

    # her own pictures, a node per layer that has any
    by_layer = {}
    for i, t in enumerate(textures, 1):
        by_layer.setdefault(t.get("layer", "mid"), []).append((i, t))
    nodes = {}
    for layer, items in by_layer.items():
        node, z = LAYERS[layer]
        out = f'[node name="{node}" type="Node2D" parent="."]\n' + (f"z_index = {z}\n" if z else "") + "\n"
        for i, t in items:
            props = _lines(t, ext_of, material_of)
            out += f'[node name="Tex{i}" type="Sprite2D" parent="{node}"]\n' + "".join("%s = %s\n" % kv for kv in props.items()) + "\n"
        nodes[layer] = out
    anchor_back = '[node name="Geometry" type="StaticBody2D" parent="."]'
    anchor_mid = '[node name="Props" type="Node2D" parent="."]'
    for layer, anchor in (("back", anchor_back), ("mid", anchor_mid), ("front", anchor_mid)):
        if layer in nodes:
            if anchor not in text:
                raise SystemExit(f"{where}: the scene has no {anchor} to lay {layer} textures by")
            text = text.replace(anchor, nodes[layer] + anchor, 1)
    if "top" in nodes:
        text = text.rstrip() + "\n\n" + nodes["top"]

    # what the new nodes need, each after the scene's own of its kind: pictures
    # among the external resources, blend materials among the sub-resources
    if ext:
        line_end = text.find("\n", text.rfind("[ext_resource")) + 1
        text = text[:line_end] + "".join(f'[ext_resource type="Texture2D" path="res://assets/{p}" id="{id_}"]\n'
                                         for p, id_ in ext.items()) + text[line_end:]
    if subs:
        materials = "".join(f'[sub_resource type="CanvasItemMaterial" id="{id_}"]\nblend_mode = {BLENDS[b]}\n\n'
                            for b, id_ in sorted(subs.items()))
        first_node = text.find("\n[node ") + 1
        text = text[:first_node] + materials + text[first_node:]
    return text, warnings
