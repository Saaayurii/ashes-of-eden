#!/usr/bin/env python3
"""Keeps mobile and Web builds small without making them quiet or ugly.

The full music library (tools/audio/music_manifest.json) is ~110 MB: fine on
desktop, too much for an APK or a browser download. This picks a light subset
— the repository's own track of every mood plus the first LITE_PER_MOOD
fetched tracks of each playlist — and writes every other MP3 into the
exclude_filter of the Android and Web presets in export_presets.cfg. Entries
that are not music (tools/, build/, full-size paintings…) are left alone.
Audio._pick skips tracks a build does not carry, so playlists just get shorter.

It also drops what no build needs at runtime: the *_source.png sheets the art
tools cut from, the narrow painted panels the wide ones replaced, and the
tools/docs/build folders.

    python3 tools/export/music_filters.py
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLAYLISTS = os.path.join(ROOT, "data", "music", "playlists.json")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
PRESETS = os.path.join(ROOT, "export_presets.cfg")
LITE_PER_MOOD = 1
LIGHT_PRESETS = ("Android", "Web")
ALWAYS_EXCLUDE = ["tools/*", "build/*", "docs/*", "*_source.png",
                  "assets/sprites/source/*", "assets/sprites/projectiles/source/*"]


def unused_art():
    """Narrow panels that have a _wide twin (the rooms load the wide one)."""
    levels = os.path.join(ROOT, "assets", "levels")
    out = []
    for f in sorted(os.listdir(levels)):
        if f.endswith(".png") and not f.endswith("_wide.png") and os.path.exists(os.path.join(levels, f[:-4] + "_wide.png")):
            out.append(f"assets/levels/{f}")
    return out


def _file_of(track):
    for ext in (".ogg", ".mp3", ".wav"):
        path = os.path.join(MUSIC, track + ext)
        if os.path.exists(path):
            return track + ext
    return None


def lite_set():
    """One track per mood, the lightest one that exists (an OGG original or a
    fetched MP3); the ambient bed always stays."""
    playlists = json.load(open(PLAYLISTS))["playlists"]
    keep = {"ambient_night.wav"}
    for tracks in playlists.values():
        files = [f for f in (_file_of(t) for t in tracks) if f]
        files.sort(key=lambda f: os.path.getsize(os.path.join(MUSIC, f)))
        keep.update(files[:LITE_PER_MOOD])
    return keep


def main():
    keep = lite_set()
    every = sorted(f for f in os.listdir(MUSIC) if f.endswith((".mp3", ".ogg", ".wav")))
    drop = [f"assets/audio/music/{f}" for f in every if f not in keep]
    text = open(PRESETS).read()
    sections = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
    out = []
    for section in sections:
        name = re.search(r'(?m)^name="([^"]*)"$', section)
        if name and name.group(1) in LIGHT_PRESETS:
            m = re.search(r'(?m)^exclude_filter="([^"]*)"$', section)
            old = [e.strip() for e in m.group(1).split(",") if e.strip()] if m else []
            other = [e for e in old if not e.startswith("assets/audio/music/")]
            fixed = ALWAYS_EXCLUDE + unused_art()
            other = [e for e in other if e not in fixed]
            value = ", ".join(fixed + other + drop)
            section = re.sub(r'(?m)^exclude_filter="[^"]*"$', f'exclude_filter="{value}"', section, count=1)
        out.append(section)
    open(PRESETS, "w").write("".join(out))
    kept_mb = sum(os.path.getsize(os.path.join(MUSIC, f)) for f in keep) / 1e6
    print(f"light builds keep {len(keep)} tracks, one per mood ({kept_mb:.1f} MB); {len(drop)} excluded")


if __name__ == "__main__":
    main()
