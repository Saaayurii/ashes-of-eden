#!/usr/bin/env python3
"""Build the bestiary portraits and extra combat strips from source atlases.

The two atlases are generated source art.  Keeping this small builder beside
them makes every crop and every derived animation reproducible.
"""

import json
from pathlib import Path
from statistics import median
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)


ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT / "data" / "enemy_archetypes" / "tree.json"
PORTRAITS = ROOT / "assets" / "portraits"
SPRITES = ROOT / "assets" / "sprites"

ENEMIES = [
    "possessed_villager", "elite_possessed", "cultist", "zealot",
    "fallen_guard", "fallen_champion", "blind_preacher", "raven",
    "shade", "wraith", "knight_of_ash", "ophanim",
]
PEOPLE = ["knight", "mara", "matthew", "nun", "severin", "villager"]

STRIPS = {
    "possessed_villager": ("possessed_idle.png", (40, 36)),
    "elite_possessed": ("possessed_idle.png", (40, 36)),
    "cultist": ("cultist_idle.png", (32, 40)),
    "zealot": ("zealot_idle.png", (36, 44)),
    "fallen_guard": ("guard_idle.png", (44, 44)),
    "fallen_champion": ("champion_idle.png", (72, 64)),
    "blind_preacher": ("preacher_idle.png", (56, 64)),
    "raven": ("raven_fly.png", (48, 28)),
    "shade": ("shade.png", (24, 28)),
    "wraith": ("wraith_idle.png", (72, 56)),
    "knight_of_ash": ("ash_knight_idle.png", (96, 72)),
    "ophanim": ("ophanim_idle.png", (112, 112)),
}

# ImageGen source atlases are kept so the shipped strips remain reproducible.
# Every atlas is an exact 7x7 grid: idle, movement, three attacks, hurt, death.
ANIMATION_ROWS = ["idle", "walk", "attack", "attack_alt", "special", "hurt", "death"]
# The cell each creature is *scaled* to: its idle silhouette fills it. The
# strip's cell is that plus whatever room its widest swing needs (see
# _fit_canvas), and the builder writes the result into the tree's "cell".
GAME_CELLS = {
    "possessed_villager": (64, 64), "elite_possessed": (72, 64),
    "cultist": (64, 64), "zealot": (64, 72), "fallen_guard": (72, 72),
    "fallen_champion": (96, 80), "knight_of_ash": (128, 96),
    "blind_preacher": (80, 88), "raven": (80, 56), "shade": (64, 64),
    "wraith": (96, 80), "ophanim": (128, 128),
}


# How far past its grid line a frame may reach for its own swing, as a share
# of the atlas cell. The generated atlases are drawn on a 7x7 grid, but a
# halberd's arc does not know that. Rows stay cut at their lines: nothing in
# them crosses one on purpose, and what does is the next row's hat.
REACH = 0.6
# A frame is seeded by what stands in the middle of its cell: its body.
SEED_BAND = 0.3
LOOSE_REACH = 10


def _components(mask: np.ndarray) -> np.ndarray:
    """4-connected labels of a boolean mask (0 = background), flood by flood."""
    labels = Image.fromarray(mask.astype(np.int32), mode="I")
    ys, xs = np.nonzero(mask)
    label = 1
    for y, x in zip(ys.tolist(), xs.tolist()):
        if labels.getpixel((x, y)) == 1:
            label += 1
            ImageDraw.floodfill(labels, (x, y), label, thresh=0)
    return np.asarray(labels) - 1  # 0 background, 1.. components


def _dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    grown = mask.copy()
    padded = np.pad(mask, radius)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            grown |= padded[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
    return grown


def _grow(seeds: np.ndarray, within: np.ndarray) -> np.ndarray:
    """Spread seed labels through a shape, each pixel to the nearest seed along it."""
    labels = seeds.copy()
    while True:
        padded = np.pad(labels, 1)
        grown = labels.copy()
        for dy in range(3):
            for dx in range(3):
                neighbour = padded[dy:dy + labels.shape[0], dx:dx + labels.shape[1]]
                grown = np.where((grown == 0) & within & (neighbour > 0), neighbour, grown)
        if np.array_equal(grown, labels):
            return labels
        labels = grown


def _row_frames(atlas: Image.Image, row: int, backdrop: bool,
                feather: int = 0) -> list[tuple[Image.Image, tuple[int, int]]]:
    """One atlas row as seven frames of whole shapes, not seven hard crops.

    Every connected shape goes to the frame whose body it grows from: a swing
    that crosses the grid line stays whole in its own frame, the tip of the
    next frame's blade stays out of it. Where two frames' shapes touch, the
    shape is split along the drawing (each pixel to the body it is nearer to,
    walking the shape). A loose shape with no body goes to the cell its mass
    is in (a spark, a bolt), unless it touches the row's top or bottom edge,
    which makes it a piece of the row above or below. Returns each frame and
    where its top-left sits relative to its cell's.
    """
    width, height = atlas.size
    y0, y1 = round(height * row / 7), round(height * (row + 1) / 7)
    band = atlas.crop((0, y0, width, y1))
    if backdrop:
        band = _remove_smooth_backdrop(band)
    alpha = np.asarray(band.getchannel("A")).astype(np.int32)
    solid = alpha > 16
    labels = _components(_dilate(solid, 2)) * solid
    edges = [round(width * column / 7) for column in range(8)]
    # The seed is the body: the biggest shape in the middle of the cell, not
    # whatever passes through it (the previous frame's axe head can).
    seeds = np.zeros(solid.shape, np.int32)
    for column in range(7):
        x0, x1 = edges[column], edges[column + 1]
        margin = round((x1 - x0) * SEED_BAND)
        middle = labels[:, x0 + margin:x1 - margin]
        weights = np.bincount(middle.ravel(), alpha[:, x0 + margin:x1 - margin].ravel().astype(float))
        weights[0] = 0.0
        if weights.max() > 0.0:
            seeds[:, x0 + margin:x1 - margin] = np.where(middle == int(np.argmax(weights)), column + 1, 0)
    owner = np.zeros(solid.shape, np.int32)
    count = int(labels.max())
    ys, xs = np.nonzero(labels)
    which = labels[ys, xs]
    weight = alpha[ys, xs].astype(float)
    mass = np.bincount(which, weight, count + 1)
    mass_x = np.bincount(which, weight * xs, count + 1)
    loose = []
    for label in range(1, count + 1):
        shape = labels == label
        present = np.unique(seeds[shape])
        present = present[present > 0]
        if present.size == 1:
            owner[shape] = present[0]
        elif present.size > 1:
            top, bottom = np.nonzero(shape.any(1))[0][[0, -1]]
            left, right = np.nonzero(shape.any(0))[0][[0, -1]]
            box = (slice(top, bottom + 1), slice(left, right + 1))
            split = _grow(seeds[box] * shape[box], shape[box])
            owner[box] = np.where(shape[box], split, owner[box])
        elif mass[label] > 0.0:
            loose.append(label)
    # A loose shape (a spark, a bolt, the axe head that came off a shaft)
    # belongs to the nearest body within LOOSE_REACH px, else to the cell its
    # mass is in. One touching the row's top or bottom edge with no body near
    # is the row above's or below's.
    near = owner.copy()
    for _ in range(LOOSE_REACH):
        padded = np.pad(near, 1)
        for dy in range(3):
            for dx in range(3):
                neighbour = padded[dy:dy + near.shape[0], dx:dx + near.shape[1]]
                near = np.where(near == 0, neighbour, near)
    for label in loose:
        shape = labels == label
        votes = np.bincount(near[shape], minlength=8)[1:]
        if votes.any():
            owner[shape] = int(np.argmax(votes)) + 1
            continue
        rows_hit = np.nonzero(shape.any(1))[0]
        if rows_hit[0] == 0 or rows_hit[-1] == shape.shape[0] - 1:
            continue
        centre = mass_x[label] / mass[label]
        owner[shape] = min(6, max(0, int(np.searchsorted(edges, centre, side="right")) - 1)) + 1
    owner *= solid
    if feather:
        # a glow that runs past the row's line fades out instead of ending in one
        ramp = np.minimum(1.0, (np.minimum(np.arange(alpha.shape[0]), alpha.shape[0] - 1 - np.arange(alpha.shape[0])) + 1)
                          / float(feather))
        alpha = (alpha * ramp[:, None]).astype(np.int32)
    frames = []
    for column in range(7):
        x0, x1 = edges[column], edges[column + 1]
        wx0 = max(0, x0 - round((x1 - x0) * REACH))
        wx1 = min(width, x1 + round((x1 - x0) * REACH))
        frame = band.crop((wx0, 0, wx1, y1 - y0))
        mine = owner[:, wx0:wx1] == column + 1
        frame.putalpha(Image.fromarray((alpha[:, wx0:wx1] * mine).astype(np.uint8), mode="L"))
        frames.append((frame, (wx0 - x0, 0)))
    return frames


def _fit_canvas(enemy: str, target: tuple[int, int], extent: tuple[int, int, int, int],
                flyer: bool) -> tuple[int, int, int, int]:
    """The strip's cell and where the scale cell sits in it (left, top).

    Symmetric sideways, because the sprite is mirrored about its centre when
    the creature turns. A walker grows only upwards (its soles stay on the
    bottom row); a flyer grows both ways about its middle.
    """
    left, top, right, bottom = extent
    side = max(0, -left + 1, right - target[0] + 1)
    side += side % 2
    up = max(0, -top + 1)
    down = max(0, bottom - target[1] + 1) if flyer else 0
    if flyer:
        up = down = max(up, down)
    return target[0] + 2 * side, target[1] + up + down, side, up


def split_atlas(source: Path, names: list[str], columns: int, rows: int) -> None:
    image = Image.open(source).convert("RGBA")
    cell_w, cell_h = image.width // columns, image.height // rows
    PORTRAITS.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(names):
        x, y = (index % columns) * cell_w, (index // columns) * cell_h
        cell = image.crop((x, y, x + cell_w, y + cell_h))
        cell.thumbnail((192, 192), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (192, 192), (10, 8, 12, 255))
        canvas.alpha_composite(cell, ((192 - cell.width) // 2, (192 - cell.height) // 2))
        patched(PORTRAITS / f"{name}.png", canvas).save(PORTRAITS / f"{name}.png", optimize=True)


def frames(path: Path, cell: tuple[int, int]) -> list[Image.Image]:
    strip = Image.open(path).convert("RGBA")
    width, height = cell
    return [strip.crop((x, 0, x + width, height)) for x in range(0, strip.width, width)]


def save_strip(path: Path, sequence: list[Image.Image]) -> None:
    output = Image.new("RGBA", (sum(frame.width for frame in sequence), sequence[0].height))
    x = 0
    for frame in sequence:
        output.alpha_composite(frame, (x, 0))
        x += frame.width
    patched(path, output).save(path, optimize=True)


def tint(frame: Image.Image, color: tuple[int, int, int], strength: float) -> Image.Image:
    overlay = Image.new("RGBA", frame.size, color + (0,))
    overlay.putalpha(frame.getchannel("A").point(lambda a: int(a * strength)))
    result = frame.copy()
    result.alpha_composite(overlay)
    return result


def shifted(frame: Image.Image, dx: int, dy: int) -> Image.Image:
    result = Image.new("RGBA", frame.size)
    result.alpha_composite(frame, (dx, dy))
    return result


def build_strips() -> None:
    for enemy, (filename, cell) in STRIPS.items():
        source = frames(SPRITES / filename, cell)
        base = source[0]
        accent = (120, 55, 180) if enemy in {"shade", "fallen_champion"} else (210, 55, 35)
        if enemy in {"zealot", "blind_preacher", "ophanim"}:
            accent = (245, 200, 80)
        elif enemy == "wraith":
            accent = (55, 220, 155)

        hurt = [tint(shifted(base, dx, 0), (255, 235, 220), 0.45) for dx in (1, -1, 0)]
        save_strip(SPRITES / f"{enemy}_hurt.png", hurt)

        alt = []
        for dx in (0, 1, 3, 1, -1):
            ghost = tint(shifted(base, -dx, 0), accent, 0.35)
            body = shifted(base, dx, 0)
            ghost.alpha_composite(body)
            alt.append(ghost)
        save_strip(SPRITES / f"{enemy}_attack_alt.png", alt)

        special = []
        for radius in (0, 1, 2, 3, 1, 0):
            glow = base.getchannel("A").filter(ImageFilter.GaussianBlur(radius + 0.5))
            halo = Image.new("RGBA", base.size, accent + (0,))
            halo.putalpha(glow.point(lambda a: min(150, a // 2)))
            body = tint(base, accent, min(0.45, radius * 0.14))
            halo.alpha_composite(body)
            special.append(halo)
        save_strip(SPRITES / f"{enemy}_special.png", special)

        if not (SPRITES / f"{enemy}_death.png").exists():
            death = []
            for i in range(6):
                squashed = base.resize((cell[0], max(1, cell[1] - i * cell[1] // 7)), Image.Resampling.NEAREST)
                faded = squashed.copy()
                faded.putalpha(faded.getchannel("A").point(lambda a, i=i: int(a * (1.0 - i / 6.0))))
                frame = Image.new("RGBA", cell)
                frame.alpha_composite(faded, (0, cell[1] - faded.height))
                death.append(frame)
            save_strip(SPRITES / f"{enemy}_death.png", death)


def _remove_smooth_backdrop(cell: Image.Image) -> Image.Image:
    """Extract opaque generated sheets whose background is a smooth vignette.

    The subject/effects carry pixel-scale detail; the unwanted matte does not.
    Difference from a broad blur gives a stable foreground seed. Expanding and
    closing that seed keeps dark feathers and translucent spectral edges.
    """
    rgba = cell.convert("RGBA")
    rgb = rgba.convert("RGB")
    smooth = rgb.filter(ImageFilter.GaussianBlur(11))
    difference = ImageChops.difference(rgb, smooth)
    # Smooth backgrounds have almost no local contrast. Generated characters
    # reliably exceed this, including black raven feathers.
    detail = difference.convert("L").point(lambda value: 255 if value > 5 else 0)
    detail = detail.filter(ImageFilter.MaxFilter(9))
    detail = detail.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    detail = detail.filter(ImageFilter.GaussianBlur(0.7))
    alpha = ImageChops.multiply(rgba.getchannel("A"), detail)
    rgba.putalpha(alpha)
    return rgba


def _wraith_special(idle: list[Image.Image]) -> list[Image.Image]:
    """A clean seven-frame ritual that never sacrifices the wraith's body.

    The generated atlas let the large magic ring cross a row boundary. Keeping
    that crop would literally remove the hood in the middle of the animation,
    so the spell is redrawn over the intact processed idle silhouettes.
    """
    sequence = []
    pulse = [0.15, 0.45, 0.8, 1.0, 0.8, 0.42, 0.12]
    for index, base in enumerate(idle):
        width, height = base.size
        strength = pulse[index]
        glow = Image.new("RGBA", base.size)
        draw = ImageDraw.Draw(glow)
        radius_x = round(18 + strength * 18)
        radius_y = round(5 + strength * 7)
        center_y = round(height * 0.63)
        box = (width // 2 - radius_x, center_y - radius_y,
               width // 2 + radius_x, center_y + radius_y)
        color = (80, 255, 184, round(100 + strength * 140))
        draw.ellipse(box, outline=color, width=max(1, round(1 + strength * 2)))
        if strength > 0.6:
            inner = (box[0] + 7, box[1] + 3, box[2] - 7, box[3] - 3)
            draw.arc(inner, 185, 350, fill=(190, 255, 224, 210), width=2)
        halo = glow.filter(ImageFilter.GaussianBlur(3.0 + strength * 3.0))
        result = Image.new("RGBA", base.size)
        result.alpha_composite(halo)
        result.alpha_composite(glow)
        result.alpha_composite(tint(base, (80, 255, 170), strength * 0.18))
        sequence.append(result)
    return sequence


def _actor_overlap(frame: Image.Image, idle: Image.Image) -> float:
    """How much of the idle silhouette is still represented in this frame."""
    idle_alpha = idle.getchannel("A")
    body_zone = idle_alpha.filter(ImageFilter.MaxFilter(9))
    overlap = ImageChops.multiply(frame.getchannel("A"), body_zone)
    baseline = max(1, sum(value * count for value, count in enumerate(idle_alpha.histogram())))
    covered = sum(value * count for value, count in enumerate(overlap.histogram()))
    return covered / baseline


def _repair_actor_continuity(rows: dict[str, list[Image.Image]]) -> None:
    """Guarantee that attacks never turn a creature into a crop artefact."""
    hit_offsets = [0, -2, 2, -1, 1, 0, 0]
    rows["hurt"] = [
        tint(shifted(rows["idle"][i], hit_offsets[i], 0), (255, 235, 225), 0.34)
        for i in range(7)
    ]
    for animation in ("attack", "attack_alt", "special"):
        repaired = []
        for i, frame in enumerate(rows[animation]):
            if _actor_overlap(frame, rows["idle"][i]) < 0.18:
                # Preserve detached projectiles and magic, but restore the
                # creature underneath so a cast frame never becomes empty.
                restored = rows["idle"][i].copy()
                restored.alpha_composite(frame)
                frame = restored
            repaired.append(frame)
        rows[animation] = repaired


def _clean_wraith(rows: dict[str, list[Image.Image]]) -> None:
    """The green atlas bleeds neighbouring cells into casts and its death row.

    Keep its intact idle silhouette and draw the magic in bounded layers. This
    prevents detached limbs and hard crop lines when the wraith shoots or dies.
    """
    idle = []
    for frame in rows["idle"]:
        safe = Image.new("RGBA", frame.size)
        safe.alpha_composite(frame.resize((86, 72), Image.Resampling.LANCZOS), (5, 4))
        idle.append(safe)
    rows["idle"] = idle
    rows["walk"] = [shifted(frame, 0, (0, -1, -2, -1, 0, 1, 0)[i])
                    for i, frame in enumerate(idle)]
    rows["hurt"] = [tint(shifted(frame, (-1, 0, 1, 0, -1, 0, 0)[i], 0),
                         (192, 255, 228), 0.42) for i, frame in enumerate(idle)]
    rows["special"] = _wraith_special(idle)
    for frame in rows["special"]:
        alpha = frame.getchannel("A")
        edge = ImageDraw.Draw(alpha)
        edge.rectangle((0, 0, frame.width - 1, 1), fill=0)
        edge.rectangle((0, frame.height - 2, frame.width - 1, frame.height - 1), fill=0)
        edge.rectangle((0, 0, 1, frame.height - 1), fill=0)
        edge.rectangle((frame.width - 2, 0, frame.width - 1, frame.height - 1), fill=0)
        frame.putalpha(alpha)
    for animation in ("attack", "attack_alt"):
        frames = []
        for i, body in enumerate(idle):
            canvas = tint(body, (84, 255, 183), (0.05, 0.08, 0.12, 0.17, 0.2, 0.12, 0.06)[i])
            # a flame in the hand, not a coin: a soft glow, a small white-hot
            # core and a four-point glint that grows and fades with the cast
            glow = Image.new("RGBA", body.size)
            core = Image.new("RGBA", body.size)
            halo_draw, core_draw = ImageDraw.Draw(glow), ImageDraw.Draw(core)
            radius = (2, 3, 4, 6, 7, 5, 2)[i]
            positions = [(76, 35)] if animation == "attack" else [(75, 26), (80, 37), (73, 48)]
            for x, y in positions:
                halo_draw.ellipse((x - radius - 2, y - radius - 2, x + radius + 2, y + radius + 2),
                                  fill=(70, 255, 180, 150))
                hot = max(1, radius // 3)
                core_draw.ellipse((x - hot, y - hot, x + hot, y + hot), fill=(225, 255, 240, 255))
                arm = radius + 1
                core_draw.line((x - arm, y, x + arm, y), fill=(160, 255, 215, 200))
                core_draw.line((x, y - arm, x, y + arm), fill=(160, 255, 215, 200))
            canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(2.5)))
            canvas.alpha_composite(core)
            frames.append(canvas)
        rows[animation] = frames
    death = []
    for i, body in enumerate(idle):
        frame = shifted(body, 0, -i)
        opacity = (255, 225, 188, 145, 98, 48, 0)[i]
        frame.putalpha(frame.getchannel("A").point(lambda alpha: alpha * opacity // 255))
        if i > 2:
            draw = ImageDraw.Draw(frame)
            for j in range(7):
                x = 27 + j * 6 + (i % 2) * 2
                y = 11 + (j * 13 + i * 5) % 49
                draw.point((x, y), fill=(100, 255, 177, max(0, 175 - i * 22)))
        death.append(frame)
    rows["death"] = death


def build_generated_animation_strips() -> dict[str, tuple[tuple[int, int], int]]:
    """Every creature's seven strips; returns the strip cell of each and how
    many rows were added above a flyer's drawing (its "pad_y")."""
    atlas_dir = SPRITES / "enemy_atlases"
    flyers = {"raven", "shade", "wraith", "ophanim"}
    cells: dict[str, tuple[tuple[int, int], int]] = {}
    for enemy, target_cell in GAME_CELLS.items():
        source = atlas_dir / f"{enemy}.png"
        if not source.exists():
            continue
        atlas = Image.open(source).convert("RGBA")
        raw_rows: dict[str, list[tuple[Image.Image, tuple[int, int]]]] = {name: [] for name in ANIMATION_ROWS}
        for row, animation in enumerate(ANIMATION_ROWS):
            raw_rows[animation] = _row_frames(atlas, row, enemy in {"raven", "wraith"},
                                              8 if enemy in flyers else 0)

        # One scale and one anchor per creature, derived from the idle row.
        # Earlier versions trimmed and re-centred every generated frame. That
        # made bodies jump around and allowed a large spell to push the actor
        # against a cell edge. Keeping atlas coordinates stable makes every
        # strip animate as one continuous drawing instead of 7 separate icons.
        idle_bounds = []
        for frame, (dx, dy) in raw_rows["idle"]:
            bounds = frame.getchannel("A").getbbox()
            if bounds:
                idle_bounds.append((bounds[0] + dx, bounds[1] + dy, bounds[2] + dx, bounds[3] + dy))
        reference_w = max((b[2] - b[0] for b in idle_bounds), default=1)
        reference_h = max((b[3] - b[1] for b in idle_bounds), default=1)
        scale = min((target_cell[0] - 4) / reference_w, (target_cell[1] - 3) / reference_h)
        anchor_x = median(((b[0] + b[2]) / 2 for b in idle_bounds)) if idle_bounds else atlas.width / 14
        anchor_y = median(((b[1] + b[3]) / 2 for b in idle_bounds)) if idle_bounds else atlas.height / 14
        anchor_bottom = median((b[3] for b in idle_bounds)) if idle_bounds else atlas.height / 7

        def layers_of(animation: str, frame_index: int) -> list[tuple[Image.Image, tuple[int, int]]]:
            layers = []
            # Spectral specials often devote most of the generated cell to a
            # ring or projectile. Put the intact idle silhouette underneath
            # first; the attack art still supplies all motion and light on top.
            if enemy in {"shade", "wraith"} and animation in {"attack_alt", "special"}:
                layers.append(raw_rows["idle"][frame_index])
            layers.append(raw_rows[animation][frame_index])
            placed = []
            for layer, (dx, dy) in layers:
                resized = layer.resize(
                    (max(1, round(layer.width * scale)), max(1, round(layer.height * scale))),
                    Image.Resampling.LANCZOS,
                )
                x = round(target_cell[0] / 2 - (anchor_x - dx) * scale)
                if enemy in flyers:
                    y = round(target_cell[1] / 2 - (anchor_y - dy) * scale)
                else:
                    y = round(target_cell[1] - 1 - (anchor_bottom - dy) * scale)
                placed.append((resized, (x, y)))
            return placed

        # How far the drawing reaches past the scale cell, over every frame.
        # The wraith is redrawn inside its cell by _clean_wraith and keeps it.
        extent = [1, 1, target_cell[0] - 1, target_cell[1] - 1]
        if enemy != "wraith":
            for animation in ANIMATION_ROWS:
                for frame_index in range(7):
                    for resized, (x, y) in layers_of(animation, frame_index):
                        bounds = resized.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
                        if bounds:
                            extent = [min(extent[0], x + bounds[0]), min(extent[1], y + bounds[1]),
                                      max(extent[2], x + bounds[2]), max(extent[3], y + bounds[3])]
        cell_w, cell_h, left, top = _fit_canvas(enemy, target_cell, tuple(extent), enemy in flyers)
        cells[enemy] = ((cell_w, cell_h), top if enemy in flyers else 0)

        rows: dict[str, list[Image.Image]] = {name: [] for name in ANIMATION_ROWS}
        for animation in ANIMATION_ROWS:
            for frame_index in range(7):
                # drawn on a margin first: a window's transparent edges may hang
                # past the cell, and alpha_composite takes no negative offsets
                margin = max(cell_w, cell_h)
                canvas = Image.new("RGBA", (cell_w + 2 * margin, cell_h + 2 * margin))
                for resized, (x, y) in layers_of(animation, frame_index):
                    canvas.alpha_composite(resized, (x + left + margin, y + top + margin))
                canvas = canvas.crop((margin, margin, margin + cell_w, margin + cell_h))
                rows[animation].append(canvas)
        if enemy == "wraith":
            rows["special"] = _wraith_special(rows["idle"])
        _repair_actor_continuity(rows)
        if enemy == "wraith":
            _clean_wraith(rows)
        for animation, sequence in rows.items():
            for index, frame in enumerate(sequence):
                bounds = frame.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
                # a walker stands on the bottom row; nothing else may touch the edge
                if bounds and (bounds[0] <= 0 or bounds[1] <= 0 or bounds[2] >= cell_w
                               or (enemy in flyers and bounds[3] >= cell_h)):
                    raise ValueError(f"{enemy} {animation} frame {index} touches a crop edge")
        for animation, sequence in rows.items():
            save_strip(SPRITES / f"{enemy}_v2_{animation}.png", sequence)
    return cells


def write_cells(cells: dict[str, tuple[tuple[int, int], int]]) -> None:
    """The tree's "cell" is the strip's: the two must never disagree. A flyer
    grown in height also gets "pad_y", so the game keeps its body where the
    hitbox is (Enemy._setup_sprite)."""
    tree = json.loads(TREE.read_text(encoding="utf-8"))
    for entry in tree:
        if entry["id"] in cells and "sprite" in entry:
            cell, pad = cells[entry["id"]]
            entry["sprite"]["cell"] = list(cell)
            entry["sprite"].pop("pad_y", None)
            if pad:
                entry["sprite"]["pad_y"] = pad
    TREE.write_text(json.dumps(tree, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> None:
    split_atlas(PORTRAITS / "enemies_atlas.png", ENEMIES, 4, 3)
    split_atlas(PORTRAITS / "people_atlas.png", PEOPLE, 3, 2)
    build_strips()
    write_cells(build_generated_animation_strips())


if __name__ == "__main__":
    main()
