"""The plane in front of the hero (docs/DEPTH.md).

A painted room has a far plane (the plates behind its openings) and a middle
one (the painting, and everyone who stands on it). What makes a side view feel
deep is a third: things closer to the eye than the hero — a grave's shoulder,
a branch, the edge of an arch — dark, a little soft, and moving faster than the
camera. This module bakes those pieces; `scripts/rooms/front_layer.gd` moves
them.

A piece is cut from a picture the game already has, never a stock cutout:

    {"from": "graveyard_cross",          # assets/levels/<from>.png
     "crop": [x, y, w, h],               # in that picture's pixels
     "at": [x, y],                       # top-left in the room, at its focus
     "depth": 1.35,                      # how much faster than the camera (> 1)
     "dark": 0.8,                        # how far towards black (backlit)
     "key": "dark",                      # "dark": keep what is darker than `cut`
     "cut": 70,                          #  — the luminance kept, 0..255
     "flip": false, "blur": 1.2,         # mirrored; soft, px (default from depth)
     "feather": 0.18}                    # edges faded, share of the shorter side

The crop's edges fade out over `feather`, so a cut never shows as a box.
`key: "alpha"` keeps the picture's own alpha instead: a transparent PNG the
studio uploaded to assets/levels/pieces/. The baked piece is `depth` times the
crop, so it is as much nearer as it is faster. At its focus — the camera's
centre on the piece's centre — it stands exactly at `at`; elsewhere it lies
at centre · depth + camera · (1 − depth), the same rule Parallax2D follows.
"""
import os
import re

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEVELS = os.path.join(ROOT, "assets", "levels")
OUT = os.path.join(LEVELS, "front")
SOURCE = re.compile(r"^((panels|pieces|composed)/)?[a-z0-9_]+$")
## A piece nearer than this would fill the screen as it slid past.
DEPTH = (1.05, 1.8)
## The most pieces a room carries: each is a full sprite drawn every frame.
MAX_PIECES = 12


def source_path(stem):
    return os.path.join(LEVELS, stem + ".png")


def validate(where, pieces, width, height):
    if not isinstance(pieces, list) or len(pieces) > MAX_PIECES:
        raise SystemExit(f"{where}: front is a list of at most {MAX_PIECES} pieces")
    for i, piece in enumerate(pieces, 1):
        stem = str(piece.get("from", ""))
        if not SOURCE.match(stem) or not os.path.exists(source_path(stem)):
            raise SystemExit(f"{where}: front piece {i} cuts from no picture assets/levels/{stem}.png")
        crop = piece.get("crop")
        with Image.open(source_path(stem)) as picture:
            size = picture.size
        if not (isinstance(crop, list) and len(crop) == 4 and crop[2] > 0 and crop[3] > 0
                and crop[0] >= 0 and crop[1] >= 0 and crop[0] + crop[2] <= size[0] and crop[1] + crop[3] <= size[1]):
            raise SystemExit(f"{where}: front piece {i} crop {crop} is not inside {stem}.png ({size[0]}x{size[1]})")
        depth = float(piece.get("depth", 1.35))
        if not DEPTH[0] <= depth <= DEPTH[1]:
            raise SystemExit(f"{where}: front piece {i} depth {depth} is not within {DEPTH[0]}..{DEPTH[1]}")
        at = piece.get("at")
        w, h = crop[2] * depth, crop[3] * depth
        if not (isinstance(at, list) and len(at) == 2 and -w < at[0] < width and -h < at[1] < height):
            raise SystemExit(f"{where}: front piece {i} at {at} is outside the {width}x{height} room")
        if piece.get("key", "dark") not in ("dark", "alpha"):
            raise SystemExit(f"{where}: front piece {i} key is dark or alpha")
        if not 0.0 <= float(piece.get("dark", 0.8)) <= 1.0:
            raise SystemExit(f"{where}: front piece {i} dark is 0..1")
        if not 0.0 <= feather_of(piece) <= 0.5:
            raise SystemExit(f"{where}: front piece {i} feather is 0..0.5")


def feather_of(piece):
    return float(piece.get("feather", 0.0 if piece.get("key") == "alpha" else 0.18))


def edge_fade(w, h, share):
    """1 inside, smoothly 0 at the crop's border, over `share` of its shorter side."""
    band = max(1.0, share * min(w, h))
    if share <= 0:
        return np.ones((h, w), np.float32)
    fx = np.clip((np.minimum(np.arange(w), np.arange(w)[::-1]) + 0.5) / band, 0, 1)
    fy = np.clip((np.minimum(np.arange(h), np.arange(h)[::-1]) + 0.5) / band, 0, 1)
    f = np.minimum(fy[:, None], fx[None, :]).astype(np.float32)
    return f * f * (3 - 2 * f)


def blur_of(piece):
    return float(piece.get("blur", round((float(piece.get("depth", 1.35)) - 1.0) * 3.0, 2)))


def bake(piece):
    """The piece as it is drawn: keyed, darkened, scaled by its depth, softened."""
    x, y, w, h = piece["crop"]
    depth = float(piece.get("depth", 1.35))
    with Image.open(source_path(piece["from"])) as picture:
        rgba = np.asarray(picture.convert("RGBA").crop((x, y, x + w, y + h)), dtype=np.float32)
    alpha = rgba[..., 3] / 255.0
    if piece.get("key", "dark") == "dark":
        lum = rgba[..., :3].mean(axis=2)
        cut = float(piece.get("cut", 70))
        alpha = alpha * np.clip((cut - lum) / 24.0 + 0.5, 0.0, 1.0)
    alpha = alpha * edge_fade(w, h, feather_of(piece))
    rgb = rgba[..., :3] * (1.0 - float(piece.get("dark", 0.8)))
    if piece.get("flip"):
        rgb, alpha = rgb[:, ::-1], alpha[:, ::-1]
    # premultiplied, so neither the scaling nor the blur grows a halo
    out = np.dstack([rgb * alpha[..., None], alpha * 255.0])
    image = Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")
    image = image.resize((max(1, round(w * depth)), max(1, round(h * depth))), Image.LANCZOS)
    radius = blur_of(piece)
    if radius > 0:
        pad = int(radius * 3 + 1)
        image = Image.fromarray(np.pad(np.asarray(image), ((pad, pad), (pad, pad), (0, 0)))).filter(
            ImageFilter.GaussianBlur(radius))
    arr = np.asarray(image, dtype=np.float32)
    a = arr[..., 3:4] / 255.0
    arr[..., :3] = np.where(a > 0, arr[..., :3] / np.maximum(a, 1e-6), 0)
    return Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")


def placed(piece):
    """Where the baked piece's centre stands at its focus, in room pixels."""
    x, y, w, h = piece["crop"]
    depth = float(piece.get("depth", 1.35))
    return (round(piece["at"][0] + w * depth / 2, 1), round(piece["at"][1] + h * depth / 2, 1))
