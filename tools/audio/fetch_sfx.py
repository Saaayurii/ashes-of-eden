#!/usr/bin/env python3
"""Fetches the extra takes described in sfx_manifest.json.

    python3 tools/audio/fetch_sfx.py            # everything missing
    python3 tools/audio/fetch_sfx.py --force    # re-extract everything

The game already has one recording of most of its sounds. One recording is
what makes a fight sound like a loop: the same swing, the same step, the same
block, forty times a minute. Audio plays a random take of any name that has
them (`Audio._base_name`: swing_1, swing_2, …), so the cure is more takes, not
more code.

Every pack here is CC0 and downloaded once into a cache; the members named in
the manifest are peak-normalised (these packs are recorded at wildly different
levels) and written as <name>_<n>.wav beside what is already in
assets/audio/sfx. A clip that was there under the bare name is renamed to
<name>_1 first, so it stays in the pool rather than being shadowed by the new
ones. Credits are written into assets/CREDITS.md from the manifest, so the two
never drift apart.
"""
import json, os, re, subprocess, sys, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(ROOT, "tools", "audio", "sfx_manifest.json")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
CACHE = os.environ.get("SFX_CACHE", os.path.expanduser("~/.cache/ashes-of-eden/sfx"))
CREDITS = os.path.join(ROOT, "assets", "CREDITS.md")
START, END = "<!-- sfx-manifest:start -->", "<!-- sfx-manifest:end -->"
## The take numbers this manifest owns start here, well clear of the clips that
## were already in the folder. Fixed on purpose: re-running writes the same
## files again instead of piling a second set on top of the first.
FIRST_TAKE = 10


def pack_file(pack):
    os.makedirs(CACHE, exist_ok=True)
    target = os.path.join(CACHE, pack["url"].rsplit("/", 1)[-1])
    if not (os.path.exists(target) and os.path.getsize(target) > 1000):
        print("  downloading", os.path.basename(target))
        request = urllib.request.Request(pack["url"], headers={
            "User-Agent": "ashes-of-eden/0.1 (sfx fetch; see tools/audio/fetch_sfx.py)"})
        with urllib.request.urlopen(request, timeout=180) as response, open(target, "wb") as f:
            f.write(response.read())
    return target


def peak_db(path):
    """The loudest sample in this clip, in dBFS (0 = full scale).

    astats over a float stream, not volumedetect: a lossy file often decodes
    above full scale, and volumedetect would report those overs as a flat 0 dB
    and leave the clip clipping after the gain."""
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af",
                          "aformat=sample_fmts=flt,astats=measure_perchannel=none:measure_overall=Peak_level",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    found = re.search(r"Peak level dB: (-?[\d.]+)", out)
    return float(found.group(1)) if found else 0.0


def convert(src, dst, target_db):
    gain = target_db - peak_db(src)
    subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", src, "-af", "volume=%.2fdB" % gain,
                           "-ar", "44100", "-c:a", "pcm_s16le", dst])


## The clip that is already there becomes take one, instead of being shadowed
## by the takes we are about to write (Audio prefers takes over a bare name).
def promote(name):
    for extension in ("ogg", "wav"):
        bare = os.path.join(OUT_DIR, "%s.%s" % (name, extension))
        first = os.path.join(OUT_DIR, "%s_1.%s" % (name, extension))
        if os.path.exists(bare) and not os.path.exists(first):
            os.rename(bare, first)
            if os.path.exists(bare + ".import"):
                os.remove(bare + ".import")  # Godot writes a new one for the new path
            print("  %s.%s -> %s_1.%s" % (name, extension, name, extension))


def main():
    force = "--force" in sys.argv
    manifest = json.load(open(MANIFEST))
    rows = []
    for sound in manifest["sounds"]:
        pack = manifest["packs"][sound["pack"]]
        print(sound["name"], "<-", sound["pack"])
        promote(sound["name"])
        archive = pack_file(pack)
        next_take = FIRST_TAKE
        with zipfile.ZipFile(archive) as zf:
            for member in sound["members"]:
                dst = os.path.join(OUT_DIR, "%s_%d.wav" % (sound["name"], next_take))
                next_take += 1
                if os.path.exists(dst) and not force:
                    continue
                tmp = os.path.join(CACHE, os.path.basename(member))
                with zf.open(member) as source, open(tmp, "wb") as f:
                    f.write(source.read())
                convert(tmp, dst, float(sound.get("peak_db", -6.0)))
                os.remove(tmp)
        rows.append("| `audio/sfx/%s_*.wav` (%d takes) | %s | %s | %s — peak-normalised to %.0f dBFS by `tools/audio/fetch_sfx.py` |"
                    % (sound["name"], len(sound["members"]), pack["author"], pack["page"],
                       pack["license"], float(sound.get("peak_db", -6.0))))
    credits = open(CREDITS).read()
    block = START + "\n" + "\n".join(rows) + "\n" + END
    if START in credits:
        credits = credits[:credits.index(START)] + block + credits[credits.index(END) + len(END):]
    else:
        credits = credits.rstrip("\n") + "\n\n### Extra sound takes (generated)\n\n| Files | Author | Source | License / notes |\n|---|---|---|---|\n" + block + "\n"
    open(CREDITS, "w").write(credits)
    print(sum(len(s["members"]) for s in manifest["sounds"]), "takes in", OUT_DIR)


if __name__ == "__main__":
    main()
