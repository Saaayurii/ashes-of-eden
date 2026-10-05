# Voice — spoken story lines

The story scenes are read out loud in all four languages. Nothing depends on it: a line with no
recording is a caption, which is how the game played before any of this existed, and a build that
ships no `assets/audio/voice/` at all is the same game with the sound turned down.

This is the same bargain as the generated sound effects. What is in the repository is a placeholder
good enough to follow a scene and hear who is who; a real reading by a real person, dropped in at
the same path, replaces it with no code change.

## What produces it

[Piper](https://github.com/OHF-Voice/piper1-gpl) — a local neural TTS. It matters that it is local:
it is MIT-licensed, runs offline, costs nothing, sends nothing anywhere, and given the same text
and the same settings it renders the same line, so regenerating does not churn the repository.

The models are downloaded on demand and are **not** committed — `tools/audio/.cache/` is
git-ignored. Only the rendered lines are.

### The licence rule, which decides most of the cast

Piper itself is MIT, but each voice is trained on somebody's dataset and carries that dataset's
licence — and **a rendered line inherits it**. [LICENSE-ASSETS.md](../LICENSE-ASSETS.md) lets
nothing non-commercial or no-derivatives into this repository, so only voices trained on CC0,
public-domain, CC BY or Apache 2.0 data may be used.

That excludes several of the best-sounding voices Piper ships:

| Voice | Why it cannot be used |
|---|---|
| `en_US-ryan`, `en_US-hfc_male`, `en_GB-semaine` | CC BY-NC-SA 4.0 — non-commercial |
| `ru_RU-ruslan` | CC BY-NC-SA 4.0 — non-commercial |
| `zh_CN-xiao_ya` | non-commercial (data-baker) |
| `en_US-lessac` | Blizzard 2013 research licence |
| `ru_RU-irina`, `zh_CN-huayan` | licence not stated |

`generate_speech.py` refuses these by name rather than quietly downloading them, and the refusal
says why. A voice that is *not* on that list has not been cleared either — it has only not been
caught. **Check the MODEL_CARD before adding one:**
`huggingface.co/rhasspy/piper-voices/raw/main/<lang>/<locale>/<voice>/<quality>/MODEL_CARD` names
the dataset and its licence. The `.onnx.json` that sits next to the downloaded model does not
mention licensing at all.

This rule, not taste, is why Russian leans on two voices and Mandarin on one.

```
assets/audio/voice/
  en/DLG_CH1_PROLOGUE_1.mp3
  ru/DLG_CH1_PROLOGUE_1.mp3
  uk/…
  zh_CN/…
```

One file per localization key per locale, named after the key it reads out. That is the whole
contract: `Audio.speak("DLG_CH1_PROLOGUE_1")` looks for the file under the locale being played, and
returns 0.0 when there is none.

## How a line gets a voice

Nobody maintains a list of lines. The pipeline reads the same data the game does:

1. **Who speaks what** — `data/dialogues/*.json`. Every node has a `speaker` and a `text` key; that
   is the mapping. Move a line to another character and it changes voice on the next run.
2. **What the line says** — `localization/strings.csv`, the column for each locale.
3. **What that character sounds like** — `tools/audio/voice_cast.json`.

A speaker with no entry in the cast is simply not voiced. That is the intended way to leave the
villagers as captions while the scenes that carry the chapter are spoken.

### The cast file

```json
"SPEAKER_VOICE": {
  "_note": "No body and no name. Deep, slow, arriving from further away than the room.",
  "en": {"model": "en_US-norman-medium", "length": 1.3},
  "ru": {"model": "ru_RU-dmitri-medium", "length": 1.3},
  "uk": {"model": "uk_UA-mykyta-high", "length": 1.3},
  "zh_CN": {"model": "zh_CN-chaowen-medium", "length": 1.3},
  "noise": 0.45, "pitch": -5.0, "echo": "0.8:0.85:480:0.4", "gain_db": -1.5
}
```

| field | what it does |
|---|---|
| `model` | a Piper voice; `python3 -m piper.download_voices` with no arguments lists every one |
| `length` | Piper's `--length-scale`. Above 1.0 is slower, and slower reads as older, heavier, more certain |
| `noise` | Piper's `--noise-scale`: how much the delivery wanders from line to line |
| `pitch` | semitone shift afterwards, via ffmpeg — pitch moves, pace does not |
| `echo` | an ffmpeg `aecho` tail, for the things that speak without a body |
| `gain_db` | trim, so nobody is twice as loud as the person they are answering |

Per-locale values override the shared ones, so one language can be slowed down without touching
the other three.

## Running it

```bash
pip install 'piper-tts[zh]' pyworld soundfile   # once; ffmpeg must also be on PATH
python3 tools/audio/generate_speech.py               # only the lines that are missing
python3 tools/audio/generate_speech.py --force       # re-render everything
python3 tools/audio/generate_speech.py --locale ru   # one language
python3 tools/audio/generate_speech.py --speaker SPEAKER_ELIAN
python3 tools/audio/generate_speech.py --dry-run     # list the work, do none of it
```

The first run of a voice downloads its model (60–115 MB) into `tools/audio/.cache/voices/`.

Two things worth knowing before the first run:

- **Mandarin needs the `[zh]` extra.** `zh_CN` voices phonemise through pinyin rather than espeak,
  which pulls in g2pW and `bert-base-chinese` on first use — a few hundred MB fetched from Hugging
  Face, and noticeably slower per line than the other three languages. Plain `pip install piper-tts`
  renders every other locale and fails on this one with "Chinese lookup tables not found".
- **Interrupted downloads are common and quiet.** Hugging Face throttles, and a truncated `.onnx`
  is a well-formed file that only fails when onnxruntime first reads it. The script now checks each
  freshly downloaded model, deletes it if it will not load, and tells you to run again; a model
  whose `.onnx.json` went missing is refetched rather than trusted.

## Who speaks, and who does not

Seventeen parts are cast. Everyone who carries a scene is voiced in all four
languages: Elian, the angel, the stranger, the voice in the dark, the blind
preacher, the Knight of Ash, the Ophanim, Father Matthew, Severin, the Knight
of the Watch, the narrator, and the three records Elian reads out of the caches.

Loudness is set per part by `gain_db`, not left to the model: a line should land
near −24 dB mean and −4 dB peak (`ffmpeg -af volumedetect`) like its neighbours.
The preacher's model, slowed and pitched, came out twelve decibels under the rest
and was barely audible under the nave's music until its `gain_db` said so.

**Sister Agnes, Mara and the crone are English and Ukrainian only.** That is
the licence rule again rather than a choice. Piper's clean-licensed voices are
very nearly all male: `ru_RU-irina` and `zh_CN-huayan` state no licence at
all, and `zh_CN-xiao_ya` is non-commercial, so Russian and Mandarin have no
female voice this repository may ship. In those two languages the three women
stay captions, which is what an unvoiced line has always been — and the honest
option, because pitching a man up to stand in for them is worse than silence.

Which is to say: a CC0 or CC BY recording of a Russian or Chinese woman's
voice would do more for this game than anything else on this page.

## Turning it off

Settings → **Spoken lines**. Off stops whatever is mid-sentence and leaves the
captions exactly as they were; it is remembered in `user://settings.cfg` and
costs nothing when off, because `Audio.speak` returns before it looks for a
file. What ships is synthesised, and a reader faster than the voice should not
have to mute the whole SFX bus to be rid of it.

## Pitch, and why it is small

A resampler moves a voice's formants along with its pitch — the resonances
that say "a human throat about this size". Four semitones down stops being a
deeper man and starts being a tape running slow, which is what the first pass
of this sounded like.

Shifting now goes through the WORLD vocoder (`pyworld`), which separates the
pitch track from the spectral envelope and moves only the first. The shifts
themselves are kept inside a couple of semitones anyway: two men are better
told apart by pace and by Piper's noise knobs than by pitch, and those do not
cost anything in naturalness.

Two parts opt out with `"formants": false` — the voice in the dark and the
Ophanim. Neither is a person, and for them the sliding formants are the
effect rather than the artefact.

Without `pyworld` installed the tool falls back to the resampler, which sounds
worse and is better than refusing to run.

## What is honestly wrong with it

**It is a text-to-speech engine reading a script, and it sounds like one.** It gets the words
across. It does not act. The Ophanim's confusion at the end of chapter I, the preacher's fear
underneath his certainty, the priest picking his way around what he did — a reader does those
things and a model does not.

**Mandarin has exactly one clean-licensed voice for seven parts.** `zh_CN-chaowen` (CC0) is the
only `zh_CN` model that clears the licence rule, so every Chinese character is that one voice
pitched and paced differently. It is followable and it is not good. Russian has two (`dmitri`,
`denis`), Ukrainian five, English six — Mandarin is by far the weakest seat, and a single
CC0 or CC BY Mandarin recording would improve the game more than anything else on this page.

**Nothing checks pronunciation.** Names invented for this game ("Ophanim", "Elian") come out
however the model guesses, and it guesses differently per language.

## Replacing it with a real reading

Drop `assets/audio/voice/<locale>/<KEY>.mp3` (or `.ogg`) over the generated file. Nothing else
changes — no code, no data, no import step. Then:

- remove that speaker's entry from `voice_cast.json`, or the next `--force` run will overwrite you;
- add the performer to `assets/CREDITS.md` with the licence they granted;
- keep it mono and 22 kHz or better, and roughly level with the other lines.

To get the lines out in a form somebody can actually read in a booth — every line one character
says, in play order, with the filename each take has to land on:

```bash
python3 tools/audio/export_script.py zh_CN -o /tmp/script.md      # every voiced part
python3 tools/audio/export_script.py ru --speaker SPEAKER_ELIAN
```

Recorded contributions are wanted, in any of the four languages — see
[CONTRIBUTING.md](../CONTRIBUTING.md). Story text and its translations are CC BY 4.0; a recording
you contribute is yours to license, and CC BY 4.0 is what keeps it in this repository rather than
in the private content overlay.

## Adding a character

1. Add an entry to `tools/audio/voice_cast.json` under the speaker id used in `data/dialogues`.
2. `python3 tools/audio/generate_speech.py --speaker <ID> --dry-run` to see what it would render.
3. Drop `--dry-run`.

If the id is wrong, the script says so instead of quietly rendering nothing: a cast entry that
matches no speaker is an error, and one key spoken by two different speakers is an error too.
