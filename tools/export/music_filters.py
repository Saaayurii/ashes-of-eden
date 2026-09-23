#!/usr/bin/env python3
"""Keeps mobile and Web builds small without making them quiet.

The full music library (tools/audio/music_manifest.json) is ~110 MB: fine on
desktop, too much for an APK or a browser download. This picks a light subset
— the repository's own track of every mood plus the first LITE_PER_MOOD
fetched tracks of each playlist — and writes every other MP3 into the
exclude_filter of the Android and Web presets in export_presets.cfg. Entries
that are not music (tools/, build/, full-size paintings…) are left alone.
Audio._pick skips tracks a build does not carry, so playlists just get shorter.

    python3 tools/export/music_filters.py
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLAYLISTS = os.path.join(ROOT, "data", "music", "playlists.json")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
PRESETS = os.path.join(ROOT, "export_presets.cfg")
LITE_PER_MOOD = 1
LIGHT_PRESETS = ("Android", "Web")


def lite_set():
    playlists = json.load(open(PLAYLISTS))["playlists"]
    keep = set()
    for tracks in playlists.values():
        fetched = [t for t in tracks if os.path.exists(os.path.join(MUSIC, t + ".mp3"))]
        keep.update(fetched[:LITE_PER_MOOD])
    return keep


def main():
    keep = lite_set()
    all_mp3 = sorted(f[:-4] for f in os.listdir(MUSIC) if f.endswith(".mp3"))
    drop = [f"assets/audio/music/{t}.mp3" for t in all_mp3 if t not in keep]
    text = open(PRESETS).read()
    sections = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
    out = []
    for section in sections:
        name = re.search(r'(?m)^name="([^"]*)"$', section)
        if name and name.group(1) in LIGHT_PRESETS:
            m = re.search(r'(?m)^exclude_filter="([^"]*)"$', section)
            old = [e.strip() for e in m.group(1).split(",") if e.strip()] if m else []
            other = [e for e in old if not e.startswith("assets/audio/music/")]
            value = ", ".join(other + drop)
            section = re.sub(r'(?m)^exclude_filter="[^"]*"$', f'exclude_filter="{value}"', section, count=1)
        out.append(section)
    open(PRESETS, "w").write("".join(out))
    kept_mb = sum(os.path.getsize(os.path.join(MUSIC, t + ".mp3")) for t in keep) / 1e6
    print(f"light builds keep {len(keep)} fetched tracks ({kept_mb:.1f} MB) + the repository's own; {len(drop)} excluded")


if __name__ == "__main__":
    main()
