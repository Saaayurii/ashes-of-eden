#!/usr/bin/env python3
"""Build the bestiary portraits and extra combat strips from source atlases.

The two atlases are generated source art.  Keeping this small builder beside
them makes every crop and every derived animation reproducible.
"""

from pathlib import Path
from statistics import median
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
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
GAME_CELLS = {
    "possessed_villager": (64, 64), "elite_possessed": (72, 64),
    "cultist": (64, 64), "zealot": (64, 72), "fallen_guard": (72, 72),
    "fallen_champion": (96, 80), "knight_of_ash": (128, 96),
    "blind_preacher": (80, 88), "raven": (80, 56), "shade": (64, 64),
    "wraith": (96, 80), "ophanim": (128, 128),
}


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
        canvas.save(PORTRAITS / f"{name}.png", optimize=True)


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
    output.save(path, optimize=True)


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


def _trim_cell_bleed(frame: Image.Image, border: int = 3) -> Image.Image:
    """Remove thin fragments imported from the neighbouring atlas cell."""
    cleaned = frame.copy()
    alpha = cleaned.getchannel("A")
    draw = ImageDraw.Draw(alpha)
    draw.rectangle((0, 0, cleaned.width, border - 1), fill=0)
    draw.rectangle((0, cleaned.height - border, cleaned.width, cleaned.height), fill=0)
    cleaned.putalpha(alpha)
    return cleaned


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
            frame = _trim_cell_bleed(frame)
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
            magic = Image.new("RGBA", body.size)
            draw = ImageDraw.Draw(magic)
            radius = (2, 3, 4, 6, 7, 5, 2)[i]
            positions = [(76, 35)] if animation == "attack" else [(75, 26), (80, 37), (73, 48)]
            for x, y in positions:
                draw.ellipse((x - radius, y - radius, x + radius, y + radius),
                             fill=(98, 255, 198, 185), outline=(203, 255, 228, 255))
            canvas.alpha_composite(magic.filter(ImageFilter.GaussianBlur(2.0)))
            canvas.alpha_composite(magic)
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


def build_generated_animation_strips() -> None:
    atlas_dir = SPRITES / "enemy_atlases"
    flyers = {"raven", "shade", "wraith", "ophanim"}
    for enemy, target_cell in GAME_CELLS.items():
        source = atlas_dir / f"{enemy}.png"
        if not source.exists():
            continue
        atlas = Image.open(source).convert("RGBA")
        raw_rows: dict[str, list[Image.Image]] = {name: [] for name in ANIMATION_ROWS}
        for row, animation in enumerate(ANIMATION_ROWS):
            for column in range(7):
                x0, x1 = round(atlas.width * column / 7), round(atlas.width * (column + 1) / 7)
                y0, y1 = round(atlas.height * row / 7), round(atlas.height * (row + 1) / 7)
                frame = atlas.crop((x0, y0, x1, y1))
                if enemy in {"raven", "wraith"}:
                    frame = _remove_smooth_backdrop(frame)
                raw_rows[animation].append(frame)

        # One scale and one anchor per creature, derived from the idle row.
        # Earlier versions trimmed and re-centred every generated frame. That
        # made bodies jump around and allowed a large spell to push the actor
        # against a cell edge. Keeping atlas coordinates stable makes every
        # strip animate as one continuous drawing instead of 7 separate icons.
        idle_bounds = []
        for frame in raw_rows["idle"]:
            bounds = frame.getchannel("A").getbbox()
            if bounds:
                idle_bounds.append(bounds)
        reference_w = max((b[2] - b[0] for b in idle_bounds), default=1)
        reference_h = max((b[3] - b[1] for b in idle_bounds), default=1)
        scale = min((target_cell[0] - 4) / reference_w, (target_cell[1] - 3) / reference_h)
        anchor_x = median(((b[0] + b[2]) / 2 for b in idle_bounds)) if idle_bounds else atlas.width / 14
        anchor_y = median(((b[1] + b[3]) / 2 for b in idle_bounds)) if idle_bounds else atlas.height / 14
        anchor_bottom = median((b[3] for b in idle_bounds)) if idle_bounds else atlas.height / 7

        rows: dict[str, list[Image.Image]] = {name: [] for name in ANIMATION_ROWS}
        for animation in ANIMATION_ROWS:
            for frame_index, frame in enumerate(raw_rows[animation]):
                canvas = Image.new("RGBA", target_cell)
                # Spectral specials often devote most of the generated cell to
                # a ring or projectile and accidentally cut the body at a grid
                # boundary. Put the intact idle silhouette underneath first;
                # the attack art still supplies all motion and light on top.
                layers = []
                if enemy in {"shade", "wraith"} and animation in {"attack_alt", "special"}:
                    layers.append(raw_rows["idle"][frame_index])
                layers.append(frame)
                for layer in layers:
                    resized = layer.resize(
                        (max(1, round(layer.width * scale)), max(1, round(layer.height * scale))),
                        Image.Resampling.LANCZOS,
                    )
                    x = round(target_cell[0] / 2 - anchor_x * scale)
                    if enemy in flyers:
                        y = round(target_cell[1] / 2 - anchor_y * scale)
                    else:
                        y = round(target_cell[1] - 1 - anchor_bottom * scale)
                    canvas.alpha_composite(resized, (x, y))
                rows[animation].append(canvas)
        if enemy == "wraith":
            rows["special"] = _wraith_special(rows["idle"])
        _repair_actor_continuity(rows)
        if enemy == "wraith":
            _clean_wraith(rows)
            for animation, sequence in rows.items():
                for index, frame in enumerate(sequence):
                    bounds = frame.getbbox()
                    if bounds and (bounds[0] <= 0 or bounds[1] <= 0
                                   or bounds[2] >= target_cell[0] or bounds[3] >= target_cell[1]):
                        raise ValueError(f"wraith {animation} frame {index} touches a crop edge")
        for animation, sequence in rows.items():
            save_strip(SPRITES / f"{enemy}_v2_{animation}.png", sequence)


def main() -> None:
    split_atlas(PORTRAITS / "enemies_atlas.png", ENEMIES, 4, 3)
    split_atlas(PORTRAITS / "people_atlas.png", PEOPLE, 3, 2)
    build_strips()
    build_generated_animation_strips()


if __name__ == "__main__":
    main()
