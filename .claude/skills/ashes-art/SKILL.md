---
name: ashes-art
description: The Ashes of Eden art pipeline for an artist who does not code. Use when she gives a reference and asks for a character, an enemy, an NPC, a background or a cutscene picture for the game ("вот референс, сделай персонажа / врага / фон", "нарисуй анимацию ходьбы", "сделай его врагом", "отправь в игру"), or asks how her art gets into the game. Covers reference study and a style bible, role-labelled prompts, generation in HER browser ChatGPT through Claude in Chrome (she presses Enter, never the agent), processing and scale in the art studio, cut-out rigs baked to pixel frames, measured checks, the sandbox, and the studio's «→ В игру» pull request.
---

# ashes-art: a reference → art in Ashes of Eden

She is an artist. She speaks Russian; **every message to her is in Russian**, short, without
programmer words (no "commit", "branch", "JSON" unless she asks). Decide technical matters
yourself and tell her what you decided in one line. Ask her only what is hers to decide —
with `AskUserQuestion`, 2–4 options, the recommended one first.

Read once per session: `CLAUDE.md` (the game's rules), `tools/studio/README.md` (the studio),
`docs/ARTIST.md` (what she was told). The ref2game skill (`.claude/skills/ref2game/`) is the
method and the tools; its WebGL engine is **not** where art is judged — the real game is
(the sandbox, step 7).

## Hard rules

1. **Never send a generation.** In ChatGPT you type the prompt and attach the images; she
   presses Enter. No clicking the send button, no Enter key, no script that submits — not even
   when she says "жми сама". OpenAI's terms and her account are at stake. Say:
   «Промпт и картинки на месте — нажми Enter в ChatGPT».
2. **Downloading a picture is a download**: ask before each one («Скачать эту картинку?»), or
   let her copy it (right click → «Копировать изображение») and paste it into the studio herself.
3. **One new ChatGPT chat per animation.** A long chat drifts the character. The first frame of an
   animation is drawn from the design; every later frame is an *edit of the approved frame*,
   in the same chat.
4. **Scale is fixed in code, never in the prompt.** ChatGPT ignores "44 pixels tall" and
   "16×16 blocks" (it drew 87 and 55). The studio recovers the pixel grid and fits the height
   («Сетка пикселей + подогнать рост»). Prompts say "chunky pixel art" and nothing about counts.
5. **Every attached image has a role**, named in the prompt in attach order: the character
   design (her reference / the approved anchor), the game's style (the hero sheet,
   `tools/studio/refs/elian_style_idle.png` — scale, outline, palette darkness ONLY, never his
   armour or sword), the approved frame. The studio's «📋 Промпт» buttons write this for you
   (`spritePrompt` in `tools/studio/lib.js`) and its toast says what to attach.
6. **Never merge, never push to `main`, never force-push.** Her work leaves only as the
   studio's «→ В игру» pull request; the owner reviews and merges.
7. **Never write a file a generator owns** (the hero's strips, the bestiary atlases, room scenes —
   `tools/check_generators.py`). The studio refuses them; don't go around it. New characters
   are new files.
8. Content is data: player-facing text goes through the studio (it fills all four locales).

## Sizes worth knowing

- Hero: 43–44 px tall, feet at the cell's bottom row, cells 128×64. A human-sized enemy or NPC
  is about the hero's height (`contentH` 44 in the studio); a big brute 52–60; a crawler 20–30.
- Look at the bestiary strips in `assets/sprites/` of an enemy of the same kind before choosing.
- The game is dark: night, cold ambient light, warm torches. A bright saturated sprite reads
  as a sticker. Measure against the hero, not against her reference.

## The flow

### 0. Look, then ask once
Look at the reference. Then one `AskUserQuestion` (Russian) with only what you cannot settle:
what it is (enemy / NPC / hero skin / background / cutscene picture); for an enemy, which
existing enemy it fights like (the studio's «⚔ Сделать врагом» `extends` one — list 3–4 fitting
ones from `data/enemies/`); which animations (default for an enemy: idle, walk, attack, hurt,
death — the ones `extends` needs); rig or frame by frame (step 4: rig for walkers and
anything with limbs, frames for blobs, smoke, flames, a cape-only ghost).

### 1. Study the reference (≈5 min)
Work in `art-inbox/<id>/` (git-ignored): copy the reference there as `ref.png`.
- `python3 .claude/skills/ref2game/scripts/study.py probe art-inbox/<id>/ref.png --out art-inbox/<id>/study`
  then `… study.py image …` (palette, values, outline; exact CLI in the script's docstring); read `.claude/skills/ref2game/references/study.md` §1–3 the first time.
- Write `art-inbox/<id>/style_bible.txt`: 3–5 lines, measured, in English, verbatim on every
  prompt as the studio's «Стиль» field — the reference's shapes and costume + the game's look
  (dark fantasy pixel art, hard pixels, dark outline, muted palette, cold night light).
- Tell her in two lines what you saw and what you'll keep / change for the game.

### 2. The studio
Open it in Chrome (Claude in Chrome tools; load them in one ToolSearch call):
- hosted: <https://saaayurii.github.io/ashes-of-eden/studio/> — she signs in with GitHub once
  (button top right); «→ В игру» opens a pull request;
- local (only if she asks, or the site is down): `python3 tools/studio/serve.py` in the background,
  then <http://localhost:8765/tools/studio/>.

Characters tab → new character → description (one English sentence), «Стиль» ← the bible,
reference into the reference box (drop or paste), animations from the presets (they carry poses).
Uploading files into frames: the hidden input `#frameFiles` («📂 Файлы») takes Claude in
Chrome's `file_upload`; it fills from the selected frame on, or the first empty one.

### 3. Generation in her ChatGPT
For each animation (rule 3: a **new chat**):
1. Open <https://chatgpt.com/> in a new tab (her account; never sign in or out for her).
2. In the studio press «📋 Промпт» on the frame (or «📋 Промпт ленты»); read the clipboard
   text from the studio's toast/`copyText` — or rebuild it with `spritePrompt`. Paste it into
   ChatGPT's composer.
3. Attach the images the toast lists, in that order (`file_upload` on ChatGPT's file input):
   her reference / approved anchor, `tools/studio/refs/elian_style_idle.png`, the approved frame.
4. Stop. «Нажми Enter». Wait for her to say it's done (or watch the page until the image appears).
5. Collect: ask, then download (rule 2) — the file lands in `~/Downloads`; copy it into
   `art-inbox/<id>/<anim>/NN.png`; upload it into the studio frame.
6. Judge it before the next frame (step 5's checks on this one frame). A wrong identity →
   a fresh chat from the approved frame, not another try in the drifting one.

Fastest for a rig (step 4): one **anchor** (the character standing in a rig pose: side view,
legs apart, arms free of the body, weapon not crossing the torso), approved by her, then one
**part sheet** as an edit of it (ref2game `references/animation.md` §1, `art.md` part-sheet
row): body+head without limbs, ONE complete leg, ONE complete arm, the weapon pointing down,
wide gutters, magenta background. Two generations, and every animation comes from them.

### 4. Rig and bake («Риг» tab)
For anything with limbs. Method: ref2game `references/animation.md` §2–5, §12, §14.
Load the part sheet (or the anchor, then cut it), auto-cut, drag the pivots onto the real joints
(hip, knee, ankle, shoulder, elbow, hand), key the poses per animation (feet on the ground by
two-bone IK), preview, then «Запечь»: rendered at high resolution, snapped to the pixel grid at the
character's height, mapped to its palette, written as ordinary frames. Fix every measured check
the tab shows before baking (foot slide, stride, pops). If the studio has no «Риг» tab yet,
draw frame by frame (step 3 for each frame) and say so to her.

### 5. Checks — before she sees it as "done"
- The studio's warnings and its red badge (height vs hero, feet on one line across frames,
  jumps of the centre between frames, palette size, key-colour halos). Zero red.
- Look frame by frame yourself (the studio's preview, or a contact sheet:
  `python3 .claude/skills/ref2game/scripts/sheet.py art-inbox/<id>/<anim>.png <frames…> --bg checker --label`). Identity the same in every frame?
- Against the reference: `python3 .claude/skills/ref2game/scripts/compare.py` (reference vs a frame at the same scale,
  `--k`; subcommands in its docstring) for colours and values; against the hero: side by side at 1:1 and ×4.
Fix what a check can find before showing her anything; report what's left in one line.

### 6. Make it an enemy (if it is one)
«⚔ Сделать врагом»: name and lore in Russian (she writes or approves them), the tip «как драться»
true to the enemy it `extends` (wind-ups, reach — read its JSON), where it appears (click a floor
on the map). Voice: borrowed from the one it fights like unless she records her own.

### 7. Sandbox
«Песочница» in the studio: the real game in the page, her character in the practice yard,
refreshed in seconds, no pull request. Play it with her there: does it read at game size, in the
dark, next to the hero? If the studio has no sandbox yet, use «▶ Играть с моими правками» after
sending (step 8) — slower, but the real game.

### 8. Send
«→ В игру» (signed in with GitHub): one pull request with her files and the studio project.
Give her the link from «Мои отправки», say the owner will look, and that comments show up there.
If CI fails, read the failing check (`gh pr checks <n>` if `gh` is installed, else the PR page),
fix it in the studio and send again — it lands in the same pull request.

## When she says…

| she says | you do |
|---|---|
| «вот референс, сделай врага / персонажа» | steps 0 → 8 |
| «сделай фон / задник» | Backgrounds tab: one layer per prompt («📋 Промпт слоя»), same ChatGPT rules, then «→ В игру» |
| «перерисуй кадр N» / «он тут другой» | that frame as an edit of the approved one, same chat |
| «не похож на референс» | `compare.py`, name the 2–3 biggest gaps, fix the bible or the anchor, not every frame |
| «покажи в игре» | the sandbox (step 7) |
| «отправь» / «в игру» | step 8 |
| «что с моими отправками?» | the studio's «Мои отправки» |
| «обнови всё» | `git pull` in the game folder (she has write access but works only through PRs), then `bash tools/setup_artist.sh` |

## Pitfalls
- Magenta halo on the edges after keying → raise the studio's tolerance or pick «альфа» if
  ChatGPT gave a transparent PNG; never paint over a halo by hand frame by frame.
- ChatGPT returns 1254×1254 with the figure tiny or cropped → the studio crops and scales; a
  cropped foot or weapon is a regeneration, not a fix.
- A strip whose figures touch → the studio cuts it into equal parts and warns; regenerate as
  single frames rather than trusting the cut.
- Identity drift after many edits → back to the approved frame in a new chat.
