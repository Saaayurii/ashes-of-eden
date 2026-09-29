#!/usr/bin/env python3
"""Spoken lines for the story, in all four languages, with Piper.

Where generate_voices.py gives every creature a throat, this gives the people
words. It reads who speaks which line out of data/dialogues, takes the text
for that line out of localization/strings.csv, and renders it with the voice
tools/audio/voice_cast.json assigns to that character in that language:

    assets/audio/voice/<locale>/<DLG_KEY>.mp3

Piper is local, offline and MIT-licensed, and its voices are CC-BY or public
domain (tools/audio/.cache/voices/<model>.onnx.json names the licence of each
one; assets/CREDITS.md carries them). Nothing here calls a paid service and
nothing leaves the machine.

These are placeholders in the same sense the generated SFX are: a real reading
by a real actor, dropped in at the same path, wins. Nothing in the game
requires them — a missing file means the line is a caption, which is how the
game plays today.

A note on what this is not. Mandarin ships one male Piper voice and chapter I
has five male parts, so the cast leans on --length-scale and a semitone shift
to tell them apart. That works well enough to follow a scene and nowhere near
well enough to ship as final audio; docs/VOICE.md says what replacing it takes.

    python3 tools/audio/generate_speech.py              # only what is missing
    python3 tools/audio/generate_speech.py --force      # re-render everything
    python3 tools/audio/generate_speech.py --locale ru  # one language
    python3 tools/audio/generate_speech.py --speaker SPEAKER_ELIAN
"""
import argparse, csv, glob, json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAST = os.path.join(ROOT, "tools", "audio", "voice_cast.json")
STRINGS = os.path.join(ROOT, "localization", "strings.csv")
DIALOGUES = os.path.join(ROOT, "data", "dialogues")
OUT = os.path.join(ROOT, "assets", "audio", "voice")
## Downloaded models live beside the audio build cache, which is git-ignored:
## they are large, and re-downloadable from the same command that made them.
MODELS = os.path.join(ROOT, "tools", "audio", ".cache", "voices")
LOCALES = ["en", "ru", "uk", "zh_CN"]


def die(message):
    sys.exit("generate_speech: " + message)


def speakers_by_key():
    """key -> speaker id, read out of the dialogue graphs themselves, so a line
    that changes hands in the story changes voice here without a second list."""
    out = {}
    for path in sorted(glob.glob(os.path.join(DIALOGUES, "*.json"))):
        doc = json.load(open(path, encoding="utf-8"))
        for dialogue in (doc if isinstance(doc, list) else [doc]):
            for node in dialogue.get("nodes", {}).values():
                speaker, text = node.get("speaker"), node.get("text")
                if speaker and text:
                    # Two speakers on one key would be a bug in the dialogue,
                    # not something to paper over with whichever came last.
                    if out.setdefault(text, speaker) != speaker:
                        die("%s is spoken by both %s and %s" % (text, out[text], speaker))
    return out


def strings():
    """key -> {locale: text}"""
    out = {}
    with open(STRINGS, encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            key = (row.get("keys") or "").strip()
            if key:
                out[key] = {loc: (row.get(loc) or "").strip() for loc in LOCALES}
    return out


## A rendered line inherits the licence of the voice that read it, and
## LICENSE-ASSETS.md lets nothing non-commercial or no-derivatives into this
## repository. These are the dataset licences that clear that bar; anything
## else has to be checked by a human and added here on purpose.
## Voices whose MODEL_CARD is known to fail the rule. Named rather than merely
## absent so that reaching for one gets an explanation instead of a download.
## This is not the whole of Piper's catalogue: a voice that is not here has not
## been cleared either, it has only not been caught. Read its MODEL_CARD.
KNOWN_BAD = {
    "en_US-ryan-medium": "CC BY-NC-SA 4.0 (non-commercial)",
    "en_US-hfc_male-medium": "CC BY-NC-SA 4.0 (non-commercial)",
    "en_US-lessac-medium": "Blizzard 2013 research licence",
    "en_GB-semaine-medium": "CC BY-NC-SA 4.0 (non-commercial)",
    "ru_RU-ruslan-medium": "CC BY-NC-SA 4.0 (non-commercial)",
    "ru_RU-irina-medium": "unknown licence",
    "zh_CN-xiao_ya-medium": "non-commercial (data-baker)",
    "zh_CN-huayan-medium": "unknown licence",
    "zh_CN-huayan-x_low": "unknown licence",
}


def check_licence(model):
    """Refuse a voice the repository is not allowed to ship the output of.

    The .onnx.json beside a model says nothing about licensing; the MODEL_CARD
    in rhasspy/piper-voices does. This checks the list above rather than the
    network, so it works offline and so that adding a voice is a decision
    somebody made, not one a download made for them.
    """
    if model in KNOWN_BAD:
        die("%s is %s - LICENSE-ASSETS.md does not allow its output in this "
            "repository. See the licence rule in tools/audio/voice_cast.json."
            % (model, KNOWN_BAD[model]))


def ensure_model(model):
    """Download a Piper voice once; later runs find it in the cache.

    A voice is two files, and an interrupted download tends to leave the big
    one and lose the small one. Checking only the .onnx means the next run
    thinks it is done and piper dies on the missing .onnx.json a hundred lines
    later, so both are required here and a half-downloaded pair is refetched.
    """
    check_licence(model)
    onnx = os.path.join(MODELS, model + ".onnx")
    config = onnx + ".json"
    if os.path.exists(onnx) and os.path.exists(config):
        return onnx
    os.makedirs(MODELS, exist_ok=True)
    if os.path.exists(onnx):
        print("  %s is missing its config, fetching again" % model)
        os.remove(onnx)
    print("  downloading", model)
    subprocess.run([sys.executable, "-m", "piper.download_voices",
                    "--data-dir", MODELS, model], check=True)
    for path in (onnx, config):
        if not os.path.exists(path):
            die("piper did not produce " + path)
    # A truncated download is a well-formed file of the wrong length, and
    # onnxruntime only complains about it at the first line it is asked to
    # read — a hundred lines into a run that then dies. Ask now.
    try:
        import onnxruntime
        onnxruntime.InferenceSession(onnx, providers=["CPUExecutionProvider"])
    except ImportError:
        pass  # piper pulls it in; if it is genuinely absent, piper will say so
    except Exception as error:
        os.remove(onnx)
        die("%s downloaded broken and has been deleted (%s). Run again."
            % (model, type(error).__name__))
    return onnx


def synthesise(text, model, length, noise, wav_path):
    subprocess.run(
        ["piper", "-m", model, "--data-dir", MODELS,
         "--length-scale", str(length), "--noise-scale", str(noise),
         "-f", wav_path],
        input=text.encode("utf-8"), check=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


## Moving a voice with asetrate moves its formants with it — the resonances
## that say "this is a human throat of about this size". Two semitones down is
## a deeper voice; six is a tape running slow, and that is what the first pass
## of this sounded like. WORLD separates the pitch from the formants and lets
## us move one and leave the other, so a character can be lower than the model
## without stopping being a person.
##
## The exception is on purpose: the voice in the dark and the Ophanim are not
## people, and dragging their formants down with them is exactly the effect
## those two want. `formants` in the cast says which.
def shift_pitch(wav_path, semitones, keep_formants=True):
    """Rewrite the wav in place at a new pitch. Falls back to ffmpeg's
    resample trick if WORLD is not installed, which sounds worse and is
    better than failing."""
    if not semitones:
        return
    ratio = 2.0 ** (semitones / 12.0)
    if not keep_formants:
        _ffmpeg(wav_path, ["asetrate=22050*%.6f" % ratio, "aresample=22050",
                           "atempo=%.6f" % (1.0 / ratio)])
        return
    try:
        import numpy as np
        import pyworld
        import soundfile
    except ImportError:
        _ffmpeg(wav_path, ["asetrate=22050*%.6f" % ratio, "aresample=22050",
                           "atempo=%.6f" % (1.0 / ratio)])
        return
    audio, rate = soundfile.read(wav_path, dtype="float64")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    # f0 is the pitch track, sp the spectral envelope (the formants), ap the
    # noisiness. Scaling f0 alone is the whole trick.
    f0, timeaxis = pyworld.harvest(audio, rate)
    sp = pyworld.cheaptrick(audio, f0, timeaxis, rate)
    ap = pyworld.d4c(audio, f0, timeaxis, rate)
    out = pyworld.synthesize(f0 * ratio, sp, ap, rate)
    peak = float(np.max(np.abs(out))) or 1.0
    soundfile.write(wav_path, (out / peak * 0.92).astype("float32"), rate)


def _ffmpeg(path, chain, out=None, extra=None):
    target = out or (path + ".tmp.wav")
    command = ["ffmpeg", "-y", "-i", path]
    if chain:
        command += ["-af", ",".join(chain)]
    command += (extra or ["-ar", "22050", "-ac", "1", target])
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if out is None:
        os.replace(target, path)


def shape(wav_path, out_path, pitch, echo, gain_db, keep_formants=True):
    """The character on top of the voice: a pitch shift to part two people
    sharing a model, a tail for whatever is speaking without a body, and a trim
    so nobody is louder than the person they are answering."""
    shift_pitch(wav_path, pitch, keep_formants)
    chain = []
    if echo:
        chain.append("aecho=" + echo)
    if gain_db:
        chain.append("volume=%.2fdB" % gain_db)
    # mp3, like the music: this ffmpeg has no libvorbis, and Godot reads both.
    # -q:a 5 at 22 kHz mono is clean for speech and lands a line near 10 KB.
    _ffmpeg(wav_path, chain, out=out_path,
            extra=["-c:a", "libmp3lame", "-q:a", "5", "-ar", "22050", "-ac", "1", out_path])


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-render lines that already exist")
    parser.add_argument("--locale", action="append", choices=LOCALES, help="only this locale (repeatable)")
    parser.add_argument("--speaker", action="append", help="only this speaker id (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="say what would be made, make nothing")
    args = parser.parse_args()

    for binary in ("piper", "ffmpeg"):
        if shutil.which(binary) is None:
            die("%s is not on PATH (pip install piper-tts / brew install ffmpeg)" % binary)

    cast = {k: v for k, v in json.load(open(CAST, encoding="utf-8")).items()
            if not k.startswith("_")}
    owner = speakers_by_key()
    text_of = strings()
    locales = args.locale or LOCALES

    # A cast entry naming a speaker no dialogue uses is a typo that would
    # otherwise show up as silence months later, so it is an error here.
    stray = sorted(set(cast) - set(owner.values()))
    if stray:
        die("cast names speakers no dialogue uses: " + ", ".join(stray))

    # Before anything is rendered or even listed, so --dry-run catches it too.
    for role in cast.values():
        for locale in LOCALES:
            if isinstance(role.get(locale), dict):
                check_licence(role[locale]["model"])

    wanted = set(args.speaker) if args.speaker else None
    if wanted:
        unknown = wanted - set(cast)
        if unknown:
            die("no cast entry for " + ", ".join(sorted(unknown)))

    jobs = []
    for key, speaker in sorted(owner.items()):
        role = cast.get(speaker)
        if role is None or (wanted and speaker not in wanted):
            continue
        for locale in locales:
            voice = role.get(locale)
            text = text_of.get(key, {}).get(locale, "")
            if not voice or not text:
                continue
            path = os.path.join(OUT, locale, key + ".mp3")
            if os.path.exists(path) and not args.force:
                continue
            jobs.append((key, speaker, locale, voice, role, text, path))

    if not jobs:
        print("nothing to do - every line in the cast already has audio (--force re-renders)")
        return

    print("%d lines to render, %d speakers, locales: %s"
          % (len(jobs), len({j[1] for j in jobs}), ", ".join(locales)))
    if args.dry_run:
        for key, speaker, locale, voice, _role, text, _path in jobs:
            print("  %-28s %-18s %-5s %-26s %s" % (key, speaker, locale, voice["model"], text[:48]))
        return

    for model in sorted({j[3]["model"] for j in jobs}):
        ensure_model(model)

    made = 0
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "line.wav")
        for key, speaker, locale, voice, role, text, path in jobs:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            synthesise(text, voice["model"],
                       voice.get("length", role.get("length", 1.0)),
                       voice.get("noise", role.get("noise", 0.5)), raw)
            shape(raw, path,
                  voice.get("pitch", role.get("pitch", 0.0)),
                  voice.get("echo", role.get("echo", "")),
                  voice.get("gain_db", role.get("gain_db", 0.0)),
                  bool(voice.get("formants", role.get("formants", True))))
            made += 1
            print("  %-5s %-28s %s" % (locale, key, speaker))
    print(made, "lines written to", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
