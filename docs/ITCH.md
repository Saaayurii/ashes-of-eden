# Publishing on itch.io

The game is already playable in a browser on [GitHub Pages][pages]. This is
about the second place, and it is worth having for four reasons that Pages
cannot cover:

1. **People look for games there.** Nobody browses GitHub Pages.
2. **Headers.** Pages cannot send any, so the Web preset must keep threads
   off (see the comment at the top of `pages.yml`). itch.io sends
   `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` when
   *SharedArrayBuffer support* is ticked, which is what a threaded Godot
   build needs. If the game ever wants threads, this is the host that has
   them.
3. **The desktop builds have somewhere to go.** Pages serves a web page;
   it has no download button.
4. **It costs nothing and asks for nothing.** No developer account, no
   99 $/year, no 25 $ registration, no review queue — unlike the App Store
   and Google Play (`docs/RELEASE.md`).

It does not replace GitHub Releases. Releases stay the canonical download for
anyone who came from the repository.

[pages]: https://saaayurii.github.io/ashes-of-eden/

## Setting it up, once

1. Make an account on <https://itch.io> and create a project:
   **Dashboard → Create new project**.
2. Fill the fields below, then **Save & view page**. Leave it as *Draft*
   until the first build is up.
3. Generate a key at <https://itch.io/user/settings/api-keys>.
4. Give it to the repository:

   ```bash
   gh secret set BUTLER_API_KEY   # paste the key
   ```

5. Check `ITCH_TARGET` at the top of `.github/workflows/itch.yml`. It is the
   page's URL — `<username>/<slug>` — not its title.
6. Push to `main`, or run the workflow by hand from the Actions tab.

Until that secret exists the workflow runs, says in its summary that it has
no key, and passes. A fork does not get a red tick for lacking someone
else's credentials.

## What the workflow does

`.github/workflows/itch.yml`, two jobs:

| When | What goes up | Channel |
|---|---|---|
| Every push to `main` | the Web export | `html5` |
| A published release | the zips `release.yml` already built | `windows`, `linux`, `osx` |

The release job downloads the assets instead of exporting again — a full
export is close to an hour of runner time and the same bytes already exist.

After the first `html5` upload, go to **Edit project → Uploads**, tick
*This file will be played in the browser* on the HTML upload, set the
viewport to **1280 × 720**, and turn on **Fullscreen button** and
**Mobile friendly**. Those are page settings, not things butler can send.

## The page

**Title** — Ashes of Eden

**Short description** (the one line under the title, 120 characters):

> A hanged man gets up. A 2D pixel action roguelite about a soul neither
> Heaven nor the Abyss will take.

**Classification** — Game · **Kind of project** — HTML
**Release status** — In development
**Pricing** — No payments (a *Donate* button is fine; see
`docs/MONETIZATION.md` for why it is not paid)

**Genre** — Action · **Tags** — `roguelike`, `pixel-art`, `metroidvania`,
`2d`, `godot`, `open-source`, `dark-fantasy`, `story-rich`, `co-op`,
`singleplayer`

**Description** — paste this:

> They hanged Elian and buried him outside the fence. He got up anyway.
>
> Side-view, fast and forgiving in the spirit of Dead Cells on the surface;
> a serious, deliberately ambiguous story underneath for anyone who wants
> it. You can finish the game without reading a word, and it will still
> have been about something.
>
> **In it now:** 15 rooms across 8 areas · 14 kinds of enemy including a
> mid-boss and a boss with two patterns · 36 gifts · 13 dialogue trees the
> world remembers your answers to · four languages · online co-op and a 1v1
> duel with crossplay · spoken story lines.
>
> **Free and open source.** No pay-to-win, no loot boxes, no ads. The code
> is MIT, the story is CC BY 4.0, and all of it is on GitHub — including
> the scripts that generate the art, the sound and this page's cover.
>
> Still a prototype (`v0.1.0-dev`). The roadmap is in the repository.

**Links** — GitHub: <https://github.com/Saaayurii/ashes-of-eden>

## The images

Generated from the game's own art by `tools/art/make_store_art.py` — the
chapter-one graveyard panel, Elian's idle frame, and Forum, the face the menu
is set in. Nothing was drawn for the store, which is the point: what a person
sees in the listing is what they get when they press play.

| File | Size | Where it goes |
|---|---|---|
| `docs/store/itch_cover.png` | 630 × 500 | itch.io **Cover image** |
| `docs/store/play_feature.png` | 1024 × 500 | Google Play feature graphic |

Screenshots for the page are in `docs/screenshots/` — `village.webp`,
`graveyard.webp`, `hell-gate.webp`, `boss-knight.webp`, `bestiary.webp`.
They are made by `scripts/tools/promo_screenshots.gd`.

Regenerate the covers with:

```bash
python3 tools/art/make_store_art.py
```

`tools/check_generators.py` verifies they still reproduce.
