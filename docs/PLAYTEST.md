# Playtests

Until now every number in `docs/BALANCE_PROBE.md` came from the bot or from the
people who make the game. This is the kit for hearing from anyone else: a link
to hand out, a short form, and opt-in telemetry that turns their nights into the
same playtest logs the probe already reads.

## 1. Hand out a build

| Where | What to send | Notes |
|---|---|---|
| **Browser** (always there) | <https://saaayurii.github.io/ashes-of-eden/> | Rebuilt by `pages.yml` on every push to `main`. Works on a phone: Play asks for full screen; on an iPhone, Add to Home Screen. |
| **itch.io** (once `BUTLER_API_KEY` exists, `docs/ITCH.md`) | the itch page | `itch.yml` uploads the same Web build on every push and the desktop zips on a release. A restricted page with a download key is the easy way to keep a test to the people invited. |
| **Desktop** | the zips on a GitHub release (`release.yml`) | Unsigned until the certificates are bought (`docs/RELEASE.md`): tell macOS testers to right-click → Open, Windows testers "More info → Run anyway". |
| **Android** | the debug APK from `mobile.yml` | `adb install -r`, or open the file on the phone with "install unknown apps" allowed. `make pull-playtest` copies its local logs off a USB phone. |

Tell testers three things and nothing more: it is chapter one of a work in
progress, a night takes 20–40 minutes, and they can stop whenever they like and
still fill in the form.

## 2. The feedback form

Any form tool will do (Google Forms, Tally, a GitHub issue template). Keep it
under two minutes: a form nobody finishes measures nothing. Suggested
questions, in this order:

1. **How far did you get?** (the place's name, or "I stopped at …")
2. **What laid you low most often?** Was it fair — could you see it coming?
3. **Was there a moment you were confused about what to do or where to go?** Where?
4. **The gifts:** did you read the cards, or pick quickly? Did any feel useless?
5. **The stranger and the other talks:** did you read them, skip them, or wish there were fewer?
6. **After you died, did you want another night?** Why / why not?
7. **What did you play on?** (browser / desktop / phone; keyboard / pad / touch)
8. **One thing to change**, and **one thing to keep.**
9. Anything else (free text).

Questions 2, 4, 5 and 6 are the four numbers of `docs/CORE_LOOP.md` asked out
loud; telemetry measures the same four, and the two together say *what* and
*why*.

**In the game:** with a form's link set, a **Send feedback** button appears in
the pause menu (under Gifts) and on the night's end, and opens the link in the
browser (`FeedbackButton`, `scripts/ui/feedback_button.gd`). `{version}` and
`{locale}` in the link are filled in, so a form can prefill them — e.g.
`https://tally.so/r/abc?version={version}&lang={locale}`. No link, no button.

## 3. Opt-in telemetry

**What is sent.** One record per night (`scripts/autoload/telemetry.gd`): the
Playtest autoload's events of that night (rooms reached and cleared and how
long each took, what laid him low, the gifts taken and refused, choices made and
dialogues skipped, secrets, deeds, the vial and omen; not the stream of small
hurts), a summary of them, the version, platform, locale and difficulty, how
many nights the profile had played, whether it was online or the night of the
day (and which try of that day), and a random install id. A "retry" record
when Again is pressed after a death. **Never:** a name, an account, an address
the server keeps, a file path, a save, anything typed.

**When.** Only when all of these hold:

- the build names a server — `ashes/telemetry/url` in `project.godot`
  (empty in the repository), or `--telemetry-url=` on the command line;
- the player said yes. The first launch of such a build asks once, over the
  main menu (`TelemetryConsent`; focus starts on No, Escape is a no); either
  answer is kept, and Settings → *Send anonymous play data* changes it. A no
  also forgets the queue and the install id;
- it is not a tool script (`-s`), and it is a night: the practice yard is not
  one.

A build with no server never asks and never records. Sending is one
`HTTPRequest` at a time, in batches of ten, from a queue kept in
`user://telemetry_queue.json` (so a night ended by quitting goes out on the next
launch, at most 60 kept); a failure only doubles the wait before the next try
(30 s up to 10 min). It works the same in the Web build — the body goes as
`text/plain`, so a browser sends no preflight.

**Setting the server and the form for a release.** Add two *repository
variables* (Settings → Secrets and variables → Actions → Variables):
`TELEMETRY_URL` (e.g. `https://telemetry.example.org/collect`) and
`FEEDBACK_URL`. `pages.yml`, `itch.yml` and `release.yml` write them into the
build with `tools/telemetry/set_urls.py` before exporting; without them the
build is exactly what it was. Both must be `https://` — the Web build is served
over https and a browser refuses to send anywhere else (the validator checks
`project.godot` too).

### The receiver

`tools/telemetry/server.py` — standard library Python, no dependencies:

```bash
make telemetry
```

runs it in Docker on `http://localhost:8930/collect`, appending to
`build/telemetry/records-YYYY-MM.jsonl`. On a server: the same
`docker compose up -d telemetry` (or `docker build tools/telemetry`) behind
Caddy for https, e.g.

```
telemetry.example.org {
	reverse_proxy localhost:8930
}
```

It keeps no addresses (not in the files, not in its log); limits each address
to 30 posts a minute in memory (behind your own proxy, `--trust-proxy` reads
`X-Forwarded-For`); refuses bodies over 512 KB, batches over 20 records and
records without an id; answers CORS for any origin. `GET /export` hands over
everything when `TELEMETRY_TOKEN` is set and sent as a bearer token.

### From records to the balance report

```bash
TELEMETRY_URL=https://telemetry.example.org TELEMETRY_TOKEN=… make telemetry-pull
make probe-field
```

`tools/telemetry/pull.py` (with no `TELEMETRY_URL`, it reads the local
`build/telemetry/records-*.jsonl`) counts every record once by its id, writes
each night as a Playtest log under `build/telemetry/field/playtest/` and the
four numbers to `build/telemetry/field/four_numbers.md`:

| Number (docs/CORE_LOOP.md) | From |
|---|---|
| Reached the first gift on the first night | an install's night with `nights` = 0 that has a `gift` or `refuse` event |
| Room of the first death (median) | the highest `room_start` index of those first nights that ended in a `death` |
| Pressed Again after the first death | a `retry` record from the same install with `nights` ≤ 1 |
| Skipped the stranger | the first night each install met `ch1_stranger` (`--stranger` for a game pack): a `skip` rather than a `choice` |

Nights played online and second tries of the night of the day are left out of
the four numbers. `make probe-field` runs `balance_probe.gd` with
`-- playtests=<that folder>`, so `docs/BALANCE_PROBE.md`'s Playtests section
reads players instead of this machine.

Tests: `telemetry_test.gd` (no server or a no sends nothing, a yes batches, a
dead, failing or nonsense server is harmless, the yard sends nothing, daily
tries, a no forgets, settings restored) and `python3 -m unittest discover -s
tools/telemetry` (the receiver, `pull.py`, `set_urls.py`).
