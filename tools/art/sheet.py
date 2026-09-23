#!/usr/bin/env python3
"""Shared helpers for slicing the generated sprite sheets (see slice_batch*.py).

The sheets are presentation images: rows of labelled sprites, sometimes on a
transparent background, sometimes on a painted panel. These helpers find the
sprites (connected blobs, grouped into rows), then cut them into the horizontal
strips the engine wants (`Fx.add_strip`: one animation per png, fixed cell).
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
DECOR = os.path.join(ROOT, "assets", "decor")
PROPS = os.path.join(ROOT, "assets", "props")
ICONS = os.path.join(ROOT, "assets", "icons")


def source(stamp, src=None):
    """The generated image whose file name ends with the given time stamp."""
    src = src or (sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads"))
    hits = glob.glob(os.path.join(src, f"*{stamp}.png"))
    if not hits:
        sys.exit(f"missing source image *{stamp}.png in {src}")
    return Image.open(hits[0]).convert("RGBA")


def alpha_mask(image, threshold=40):
    return np.array(image)[:, :, 3] > threshold


def panel_mask(image, background, tolerance=42):
    """For sheets painted on a panel: everything far enough from the panel colour."""
    rgb = np.array(image)[:, :, :3].astype(int)
    return np.sqrt(((rgb - np.array(background)) ** 2).sum(axis=2)) > tolerance


def denoise(mask, keep=3):
    """Drop lone specks: panel noise that survives the colour mask otherwise."""
    padded = np.pad(mask, 1)
    neighbours = sum(padded[1 + dy:padded.shape[0] - 1 + dy, 1 + dx:padded.shape[1] - 1 + dx].astype(np.uint8)
                     for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy, dx) != (0, 0))
    return mask & (neighbours >= keep)


def blobs(mask, step=4, min_size=8, pad=1):
    """Bounding boxes of the separate sprites, found on a downscaled mask.

    step blurs the mask down so the parts of one sprite (a lid, a spark) end up
    in one blob; min_size is in downscaled pixels.
    """
    h, w = mask.shape
    small = mask[: h // step * step, : w // step * step]
    small = small.reshape(h // step, step, w // step, step).any(axis=(1, 3))
    seen = np.zeros_like(small, dtype=bool)
    out = []
    for sy in range(small.shape[0]):
        for sx in range(small.shape[1]):
            if not small[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            y0 = y1 = sy
            x0 = x1 = sx
            size = 0
            while stack:
                cy, cx = stack.pop()
                size += 1
                y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < small.shape[0] and 0 <= nx < small.shape[1] and small[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if size >= min_size:
                out.append((max(0, x0 * step - pad), max(0, y0 * step - pad),
                            min(w, (x1 + 1) * step + pad), min(h, (y1 + 1) * step + pad)))
    return tighten(mask, out)


def tighten(mask, boxes):
    """Shrink every box back onto the pixels it actually contains."""
    out = []
    for x0, y0, x1, y1 in boxes:
        sub = mask[y0:y1, x0:x1]
        ys = np.where(sub.any(axis=1))[0]
        xs = np.where(sub.any(axis=0))[0]
        if len(ys) == 0 or len(xs) == 0:
            continue
        out.append((x0 + xs[0], y0 + ys[0], x0 + xs[-1] + 1, y0 + ys[-1] + 1))
    return out


def rows(boxes, tolerance=0.45):
    """Group boxes into rows by vertical overlap, each row sorted left to right."""
    out = []
    for box in sorted(boxes, key=lambda b: (b[1], b[0])):
        height = box[3] - box[1]
        for row in out:
            top = min(b[1] for b in row)
            bottom = max(b[3] for b in row)
            overlap = min(bottom, box[3]) - max(top, box[1])
            if overlap > tolerance * min(height, bottom - top):
                row.append(box)
                break
        else:
            out.append([box])
    for row in out:
        row.sort(key=lambda b: b[0])
    out.sort(key=lambda row: min(b[1] for b in row))
    return out


def cut(image, mask, box, feather=0):
    """The sprite inside box, with the background masked out."""
    x0, y0, x1, y1 = box
    frame = image.crop(box).convert("RGBA")
    if feather >= 0:
        alpha = np.array(frame)[:, :, 3].copy()
        alpha[~mask[y0:y1, x0:x1]] = 0
        rgba = np.array(frame)
        rgba[:, :, 3] = alpha
        frame = Image.fromarray(rgba)
    return frame


def solid_cut(image, mask, box):
    """Like cut(), but only the background the frame's border can reach is removed.

    A painted panel sheet has figures whose dark cloth matches the panel; masking
    by colour alone punches holes in them. Flood the background in from the edges
    of the box instead and keep everything it cannot reach.
    """
    x0, y0, x1, y1 = box
    sub = mask[y0:y1, x0:x1]
    h, w = sub.shape
    outside = np.zeros_like(sub)
    stack = []
    for y in range(h):
        for x in (0, w - 1):
            if not sub[y, x] and not outside[y, x]:
                outside[y, x] = True
                stack.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if not sub[y, x] and not outside[y, x]:
                outside[y, x] = True
                stack.append((y, x))
    while stack:
        cy, cx = stack.pop()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and not sub[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                stack.append((ny, nx))
    rgba = np.array(image.crop(box).convert("RGBA"))
    rgba[:, :, 3] = np.where(outside, 0, 255)
    return Image.fromarray(rgba)


def resize(frame, size, threshold=110):
    """Resize in premultiplied alpha (no dark fringe), then harden the edge."""
    a = np.array(frame).astype(np.float32)
    alpha = a[:, :, 3:4]
    premultiplied = Image.fromarray(np.dstack([a[:, :, :3] * alpha / 255.0, alpha]).astype(np.uint8))
    b = np.array(premultiplied.resize(size, Image.LANCZOS)).astype(np.float32)
    alpha = b[:, :, 3:4]
    rgb = np.clip(np.where(alpha > 0, b[:, :, :3] * 255.0 / np.maximum(alpha, 1.0), 0), 0, 255)
    return Image.fromarray(np.dstack([rgb, np.where(alpha > threshold, 255, 0)]).astype(np.uint8))


def fit(frame, cell, anchor="bottom", margin=1, threshold=110):
    """Scale a sprite into one cell without distorting it, then place it."""
    cw, ch = cell
    scale = min((cw - margin * 2) / frame.width, (ch - margin * 2) / frame.height)
    frame = resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))), threshold)
    out = Image.new("RGBA", cell, (0, 0, 0, 0))
    x = (cw - frame.width) // 2
    y = ch - frame.height - margin if anchor == "bottom" else (ch - frame.height) // 2
    out.alpha_composite(frame, (x, y))
    return out


def strip(cells, name, folder=SPRITES):
    os.makedirs(folder, exist_ok=True)
    cw, ch = cells[0].size
    out = Image.new("RGBA", (cw * len(cells), ch), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        out.alpha_composite(cell, (i * cw, 0))
    out.save(os.path.join(folder, f"{name}.png"))
    print(f"  {name}.png {out.size[0]}x{out.size[1]} ({len(cells)} frames)")


def single(frame, name, height=None, width=None, folder=DECOR, threshold=110):
    os.makedirs(folder, exist_ok=True)
    scale = 1.0
    if height:
        scale = height / frame.height
    if width:
        scale = min(scale, width / frame.width) if height else width / frame.width
    if scale != 1.0:
        frame = resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))), threshold)
    frame.save(os.path.join(folder, f"{name}.png"))
    print(f"  {name}.png {frame.size[0]}x{frame.size[1]}")


def contact_sheet(image, mask, path, scale=0.55):
    """Debug: the found boxes drawn over the sheet, numbered per row."""
    from PIL import ImageDraw
    preview = image.convert("RGB").copy()
    draw = ImageDraw.Draw(preview)
    for r, row in enumerate(rows(blobs(mask))):
        for i, box in enumerate(row):
            draw.rectangle(box, outline=(255, 60, 60))
            draw.text((box[0] + 2, box[1] + 2), f"{r}.{i}", fill=(255, 220, 80))
    preview = preview.resize((round(preview.width * scale), round(preview.height * scale)), Image.LANCZOS)
    preview.save(path)
    print("wrote", path)


def components(mask, connect=2):
    """Connected blobs at full resolution: a label per pixel (0 = background)
    and, per label, (x0, y0, x1, y1, area). Pixels closer than [connect] are
    joined first, so a hair-thin sword still belongs to the hand holding it.

    Run-length union-find: a row's runs link to the runs they overlap in the
    row above. Pure numpy/python, fast enough for a 1500 px sheet.
    """
    if connect:
        grown = Image.fromarray((mask * 255).astype(np.uint8)).filter(
            __import__("PIL.ImageFilter", fromlist=["MaxFilter"]).MaxFilter(connect * 2 + 1))
        joined = np.array(grown) > 0
    else:
        joined = mask
    h, w = joined.shape
    parent = []

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    labels = np.zeros((h, w), dtype=np.int32)
    previous = []  # (x0, x1, run id) of the row above
    for y in range(h):
        row = joined[y]
        edges = np.flatnonzero(np.diff(np.concatenate(([0], row.astype(np.int8), [0]))))
        current = []
        for x0, x1 in zip(edges[::2], edges[1::2]):
            run = len(parent)
            parent.append(run)
            for px0, px1, prun in previous:
                if px0 < x1 and x0 < px1:
                    a, b = find(run), find(prun)
                    if a != b:
                        parent[a] = b
            current.append((x0, x1, run))
            labels[y, x0:x1] = run + 1
        previous = current
    roots = np.array([find(i) for i in range(len(parent))], dtype=np.int32)
    remap = np.concatenate(([0], roots + 1))
    labels = remap[labels]
    labels[~mask] = 0  # the growth was only for connectivity
    info = {}
    ys, xs = np.nonzero(labels)
    for label, x, y in zip(labels[ys, xs], xs, ys):
        box = info.get(label)
        if box is None:
            info[label] = [x, y, x + 1, y + 1, 1]
        else:
            box[0] = min(box[0], x); box[1] = min(box[1], y)
            box[2] = max(box[2], x + 1); box[3] = max(box[3], y + 1); box[4] += 1
    return labels, {k: tuple(v) for k, v in info.items()}
