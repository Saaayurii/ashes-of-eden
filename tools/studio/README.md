# Art studio (`tools/studio`)

A browser tool for the game's art, sound and story, for people who do not open
Godot: characters frame by frame (cleaned up from image-model output), parallax
backgrounds, cutscenes with their dialogue lines, and sound effects, music and
spoken lines. It reads the game itself and writes back into it.

- **Hosted:** <https://saaayurii.github.io/ashes-of-eden/studio/> — built by
  `pages.yml` from `main`. Writing needs a GitHub sign-in with push access; every
  change arrives as a pull request, so CI validates it before it lands.
- **Local:** `python3 tools/studio/serve.py` → <http://localhost:8765/tools/studio/>.
  Writes straight into the working tree, runs `validate_data.gd` after each
  write, and **▶ В Godot** opens the game in the room being edited.

## How it fits the repository

| file | what it is |
|---|---|
| `index.html` | the page (UI in Russian) |
| `lib.js` | the pure half: background removal, pixel-grid recovery, palette, file formats; tested in Node |
| `repo.js` | sign-in, writing (local server or GitHub pull request), what each tab sends |
| `build_data.py` | turns the game into `import/*.json` for the page (not tracked) |
| `serve.py` | the local server; writes only under `assets/`, `data/cutscenes`, `data/dialogues`, `data/backdrops.json`, `localization/strings.csv`, `tools/studio/projects/` |
| `projects/` | studio projects people shared, and `files.json`: files the studio created |
| `refs/` | style references to attach in an image model (the hero at 16×) |

**It never fights a generator.** `build_data.py` lists every file a generator in
`tools/check_generators.py` owns, and the studio refuses to write those —
CI would fail. So: the hero's and the bestiary's strips, room scenes and
placeholder sounds are read-only here; new characters, takes, lines,
backgrounds and cutscenes are plain new files. A changed generated sound is
written as a new numbered take beside it (`Audio._clip` prefers takes), the way
`generate_sfx.py` says to replace a placeholder.

**Living backdrops** (`js/life.js`, the «Оживление» tab). `build_data.py` writes
`import/life.json`: every picture a rule in `data/backdrops.json` can light — a
room's painting as `BackdropLife.painting_of` finds it (the interiors from
`interior_architecture.gd`), the menu's and the arena's, every cutscene panel
and passage card — with the zone kinds and their defaults read from
`BackdropLife.KINDS`. The page runs `backdrop_life.gdshaderinc` ported to
WebGL2 (one loop over the zones instead of the cell grid; the same noise, the
same reactions: gust, lightning, a cleared room, a boss's rage, dread, the
path's colour). Change the shader there, change `LIFE_FS` here.
`lib.js setBackdropRule` rewrites one rule in the file's own style; every rule
of the real file must round-trip byte for byte (`tests/lib.test.js`).

**Platform pieces** (`js/tiles.js`, «🧱 Плитки» in the backgrounds tab).
`build_data.py` writes `import/tiles.json`: `assets/decor/platforms/manifest.json`,
which scenes lay each piece, which rooms are played. A piece she redraws is
fitted to its manifest size and its alpha hardened as `slice_batch9.py` does;
at the same size the scenes need no change, so only the PNG is written. The
row preview is `generate_rooms.lay()` in miniature: no twins side by side,
`OVERLAP` between pieces, each in its own shade (`_piece_shade`).

**Seams of widened paintings** (`js/seams.js`, «🩹 Швы» on a room's painting).
`generate_rooms.py` widens each painted panel by quilting a band at every
`ROOM_EXPANSION_CUTS` cut out of the painting either side, so anything that
stands near a cut stands there twice. `build_data.py` writes `import/seams.json`
(the bands in wide-painting pixels, and how busy each is — fine detail against
the painting as a whole, a rough "how visible is the twin"). The studio cuts a
band out with 80 px either side and the room's floors drawn on it, takes her
repaint back, keeps only the band (feathered into its sides) and sends the wide
painting through the override path, so only the band goes in.
Before the band is cut out, her repaint is put back onto the crop the way
ref2game's `variantfix.py` does (`lib.js alignEdit` / `warpEdit` /
`matchColours`): an image model's edit drifts a few pixels, a percent or two in
size and a shade in colour, so the offset and scale are searched against the
80 px sides (which were to stay) and each channel's mean and spread brought to
theirs.

**Ranged attacks** (`js/shots.js`, the «Снаряды» tab). `build_data.py` writes
`import/projectiles.json`: the looks of `data/projectiles.json`, their strips,
and every ranged attack in `data/enemies` and bolt gift in `data/abilities`
with its place in its file. The preview flies them as `scripts/fx/projectile.gd`
does — keep the two in step. Styles go back as the whole file; an attack goes
back through `lib.js patchJson`, which rewrites only the values she touched and
writes a new key the way Python's `json.dumps(indent=2)` would (both checked
against every enemy file, `tests/`). An attack is edited where the game reads it
(`build_data.attack_source`, as `data_loader.gd` merges): the archetype overlay
`data/enemy_archetypes/tree.json` when it lists the creature's attacks (its
generator writes only `sprite.cell` / `pad_y` there — `GENERATOR_INPUTS`), else the
creature's own list, its single `attack`, or the list it inherits. Given or taken
attacks rewrite that list through `lib.js setJsonList`, every attack kept as its
own text; a copied attack takes only how it shoots (`SHOT_COPY`). A new strip goes in as
`assets/sprites/projectiles/<style>_studio.png`.

**Dialogues** (`js/dialogues.js`, «Диалоги»). Every dialogue in `data/dialogues`, not only
the ones a cutscene step reaches: the people on E, the notes, the forks' questions at a door
(`build_data.py` lists who plays each as `used_by` in `import/cutscenes.json`, from every data file
naming it as `"dialogue"`). Lines (speaker, text in all four locales), answers (id, the paths they
weigh on, the flags they set, where they lead), routers (flag / path / habit / vial / omen) and the
window: the panel at the bottom, or captions at the top (`"blocking": false`, no answers). An NPC's
blocking dialogue is drawn as bubbles instead (`DialogueBox.play_bubble`). The preview draws each of
the three as `dialogue_box.tscn` and `_build_bubbles` / `_place_bubbles` lay them out, in the game's
fonts — change the box, change `dlgDrawPanel` / `dlgDrawCaption` / `dlgDrawBubble`. What the
validator would refuse is listed in red before sending (`dlgProblems`), including Chinese outside
the font subset. A changed dialogue is written back by `lib.js mergeDialogueFile`: every node still
as it was keeps its bytes, a changed one keeps its own layout (one line or expanded), so a
hand-laid file stays hand-laid (`tests/lib.test.js` rebuilds every dialogue of the game).

**Particles on actions** (`js/particles.js`, «Частицы»). `data/action_fx.json` is
read by `scripts/fx/action_fx.gd`, an `ActionFx` node on the hero's and every
creature's sprite: an animation's start, chosen frames or a timer, plus the events
the game names (`ActionFx.EVENTS`). `build_data.py` writes `import/action_fx.json`:
the rules, `KINDS` / `ANCHORS` / `EVENTS` read from the script, and every body with
its strips (the hero's per-animation fps). The preview draws a likeness of `Fx`;
keep the kinds in step with `ActionFx.emit`.

**Old content too: edits of what a generator draws are overrides.** The
bestiary's strips, the props from `make_*.py`, the hero's special moves, the
practice yard and the rooms' paintings are generator-owned, and an edit of one
is never written over it. It goes beside the generator instead, the way rooms
take `tools/rooms/studio_rooms.json`:
- her picture whole, at `tools/studio/overrides/<path>`;
- a mask of what she changed, at `<path>.mask.png`;
- a line in `overrides.json`.

Every generator that writes pictures passes them through
`tools/art/studio_overrides.py` `patched()` just before saving, which lays her
pixels over its own. Regenerating keeps her work and `check_generators.py`
stays green with no exceptions.

The mask holds only what she changed. For a character from the game,
`frameEdits` in `lib.js` compares each frame slot with the game's (build_data
gives every frame its `region` in the game's files): a replaced or moved frame
is its whole cell, a ✎ touch-up is its pixels, and an untouched frame stays
out. That matters because the studio's processing does not give a game sprite
back pixel for pixel. For a picture replaced whole (🖌 «Перерисовать картину»
on a room's painting in the backgrounds tab), the mask is where it differs from
the game's.

The robot (`studio-robot.yml`) runs `studio_overrides.py regenerate` on her
pull request: the owning generators lay the edit and record the picture she
drew on, and `settle` covers pictures in a generator's folder that nobody
generates (the hero's strips in `assets/sprites`). The local server does the
same and keeps only the overridden pictures of what the generators rewrite.

If a generator later draws something else under an edit of the same size, the
edit still applies, the entry is marked `stale`, and the studio says «База
изменилась — проверь». If the size changed, the generator fails, naming the
override. A frame cannot be added to a generated strip (make a new character),
and the hero's `.tres` stays the generator's.

**It keeps the repository's formatting.** `strings.csv`, dialogue files and
cutscenes are rewritten byte-identically when unchanged (tests check this
against the real files); a dialogue file holding several dialogues is edited
only inside the one that changed; a new cutscene picture gets a still rule in
`data/backdrops.json` (the validator wants one for every panel); a new string
fills all four locales, borrowing English where nobody translated yet.

**It keeps her work.** Each send carries the studio project
(`projects/<kind>/<id>.json`) in the same pull request, so **Мои отправки**
lists her pull requests with their state — checking, checked, merged, live on
the site (the merge commit is in the deployed `meta.json` sha) — and can open
any of them back in the studio, from the branch, on any computer. Copies from
the game never overwrite what she changed (`mergeDecision` in `lib.js`: every
game item carries a `rev`, a hash of its files); if the game changed the same
thing meanwhile, the studio asks which to keep. A sent project stays hers until
its pull request is live, then follows the game again.

**She plays what she sent.** For every open studio pull request (branch
`studio/…`) `pages.yml` exports a data pack from its head and serves
`preview-<n>.html`: the main build's engine with that pack
(`make_preview_page.py`), nothing kept between visits, and `?room=` /
`?practice=<enemy>` honoured through `--studio-preview` (`run.gd`). Мои отправки
links it, straight into the room of a changed cutscene or the practice yard
against a new enemy; the owner's reviews and comments show under each send,
she can answer, and a fix goes into the same pull request.

**She sees it in the game while drawing.** «🎮 Песочница» opens the Web build
beside the frames (`studio-live.html`, made by `make_preview_page.py --live`
in `pages.yml`; served from the working tree the studio embeds the hosted one).
The game starts with `--studio-live` (`scripts/run/studio_live.gd`) in the
practice yard and says `ashes-live-ready`; after every rebuild of the frames the
studio posts the strips of each enemy slot (`enemySlotFor`, `liveMessage` in
`lib.js`) with the enemy it fights like, and the game makes textures of them
(`Image.load_png_from_buffer` → `Fx.runtime_strips`), lays the creature over its
base in `Data.enemies` as `studio_live` and swaps the yard's foe. Seconds, no
pull request; the page keeps nothing. `studio_live_test.gd` covers the game side.

**Rigs bake into frames.** «Риг» (`js/rig.js`, maths in `js/rig-core.js`,
Node-tested in `tests/rig.test.js`) is ref2game's cut-out rig
(`.claude/skills/ref2game/references/animation.md`, `templates/live/lib.js`
`twoBone`, `scripts/partrig.py`) as a frame generator. A part sheet (body
without limbs, one leg, one arm, the weapon; magenta or transparent) is keyed
and cut into pieces; roles are guessed by shape and can be fixed by hand.
Joints are measured on the drawings (partrig's rows) and dragged into place.
Each limb is cut into thigh/shin/foot or upper/fore arm; the far side is the
same drawing, darker, drawn behind the body. Poses are per frame: drag a foot
or a hand and two-bone IK sets the joint between, drag the hips and the
planted feet stay. Keys blend smoothly. «🚶 Шаг» generates a walk in place —
feet planted and sliding back at body speed, hips riding the stance leg — and
«🫁 Дыхание» generates a breath. The measured checks run on the joint trace
before baking: foot slide, ground, stride, lift and pops. «Запечь» renders
every frame at 8× the game's size, shrinks it by the dominant colour of each
cell to `contentH`, and writes the frames into the animation as `baked`.
The frame pipeline takes those as they are (no grid search, kept in place in
the cell) and the sandbox shows them at once. A walk's fps is set from the
base enemy's speed, so the feet keep their grip in the game.

**Checked before it leaves.** After every rebuild `artChecks` (`lib.js`)
measures the processed frames. It checks the height (the idle's, not a raised
blade's) against the one asked for and against the hero's 44 px. It checks
that the feet stay on one row and that the legs' centre does not jump between
frames in idle and walk/run. Attacks, rolls and deaths move on purpose, and a
flyer (`flyer` / `boss_ophanim`, as the practice yard has it) has no ground
line. It looks for a palette larger than the one set, for the source's own
background colour left on the silhouette's edge (the key measured when the
background was removed, so a purple ghost on a transparent source is not a
fringe), and for soft alpha. What is wrong is listed in red under the preview
and counted in a badge on «→ В игру» and «⚔ Сделать врагом», which ask once
more before sending. Calibrated against the game's own 22 characters: none of
them turns it red.

**A character can become an enemy.** «⚔ Сделать врагом» writes
`data/enemies/<id>.json` that `extends` an enemy the game has (its fight, its
sounds), with the strips she drew, name, lore and the `tip` the validator wants,
in all four locales. Rooms still get their spawns from the room generator.

**Rooms through the generator, by a robot.** Placing an enemy or tying a
cutscene to a room writes `tools/rooms/studio_rooms.json`, which
`generate_rooms.py` merges into its tables (spawns in the finished room's
pixels, checked by `check_reach` like every walker). On a studio pull request
`.github/workflows/studio-robot.yml` regenerates the rooms, pushes the scenes
onto the branch and starts CI and the preview again; `serve.py` does the same
locally (keeping the panels as committed — their re-encoding differs by a level
on other machines than CI's). The placement map snaps a click to the floor
below it by the rule `check_reach` uses.

**Pictures without a key in the browser.** ⚡ generation goes, in order, to a
key typed in this browser, the local server's `OPENAI_API_KEY`, or — signed in
through GitHub — `.github/workflows/studio-images.yml`: the studio points
`studio-gen/<login>` at main plus one commit with the request, the workflow
draws it with the repository secret `OPENAI_API_KEY` (`generate_image.py`) and
pushes `out.png` back.

**Enemy voices.** Without her own sounds an enemy speaks with the voice of the
one it fights like (`"voice"`); with any of hers, the cues she left out are
copied from that one as `<id>_<kind>_N.wav`, so it never falls silent. A
portrait is optional (`avatar`); otherwise the bestiary plays its idle strip.

The page is plain scripts in `js/` sharing one scope, loaded in order by
`index.html`; `lib.js` (pure) and `repo.js` (the repository side) beside them.

```sh
node --test tools/studio/tests/*.test.js             # lib.js, formats against the real files
python3 -m unittest discover -s tools/studio/tests   # converter, server guard, preview page
cd tools/studio/e2e && npm install --no-save --no-package-lock playwright@1.49.1 \
  && npx playwright install chromium && node studio.e2e.cjs   # the page in Chromium (CI runs it)
node studio.github.e2e.cjs   # (same folder) send → PR → owner's review → answer → fix, against a fake GitHub
```



**A tablet and a pencil** (`js/touch.js`). Every drawing surface has
`touch-action: none`. One pointer does the work: a palm on the glass is ignored,
and a palm that landed first is let go when the pencil touches. Once a pencil
has been seen on the device, a single finger no longer paints; two fingers pinch
and pan the pixel editor. A hovering Apple Pencil Pro shows the pixel it would
paint. Squeeze and double tap never reach a web page, so every tool has its
button: ↶ ↷ inside the pixel editor, «📋 Вставить» on each frame and on the
reference (a picture from the clipboard without Cmd+V), and «⬆ Файл», which
opens Photos and Files on an iPad. The e2e test drives it as an iPad
(820×1180, touch) with a pen pointer through CDP.

## Для художника (как пользоваться)

С Claude (установка и фразы): [docs/ARTIST.md](../../docs/ARTIST.md).

1. Открой <https://saaayurii.github.io/ashes-of-eden/studio/>. Справа вверху
   **Войти**: студия покажет, как получить ключ GitHub (нужно один раз).
2. **Персонажи.** Новый персонаж → вставь референс → выбери анимацию →
   «📋 Промпт» / «📋 Промпт ленты» в ChatGPT; всплывающая подсказка скажет,
   какие картинки приложить и в каком порядке (референс персонажа, затем
   `refs/elian_style_idle.png` — только масштаб и палитра). Картинку обратно —
   Cmd/Ctrl+V или «📂 Файлы». Масштаб «Сетка пикселей + подогнать рост»
   снимает сетку и ставит рост как у героя (44 px) — размер в промпте не
   просим, ChatGPT его всё равно не держит. **Каждая анимация — новый чат
   ChatGPT**; следующие кадры — правка одобренного кадра в том же чате.
3. **Задники.** Слои с параллаксом; «📋 Промпт слоя», картинка Cmd/Ctrl+V,
   «Из игры…» — любая картинка игры.
4. **Катсцены.** Шаги, реплики (ru/en), превью с картинами, титрами и звуком.
5. **Звуки.** Прослушать, заменить файлом или записью с микрофона, обрезать,
   громкость.
6. **→ В игру** — отправить (красный значок на кнопке — проверки нашли
   что-то: рост, ноги, рывки, цвет фона по краю; список под превью); **☁ Поделиться** — сохранить проект для всех;
   **⬇ zip** — скачать файлы себе. Ошиблась — Cmd/Ctrl+Z.
7. **Мои отправки** — что с каждой отправкой: на проверке → проверено →
   влито → в игре. «Открыть в студии» вернёт отправленное, даже на другом
   компьютере. «Из игры» никогда не затирает твои правки; если ту же вещь в
   игре поменял кто-то ещё, студия спросит, какую версию оставить.
8. **▶ Играть с моими правками** — в «Моих отправках»: игра с твоими изменениями
   ещё до вливания (сразу в комнату катсцены или на тренировку с новым врагом).
   Там же замечания владельца: ответить, поправить — «→ В игру» допишет
   исправления в ту же отправку.
9. **Риг** — лист частей (тело без рук и ног, нога, рука, оружие) → тяни
   розовые точки: стопы, кисти, таз, голова. «🚶 Шаг» делает ходьбу, ноги
   стоят на земле; «Запечь» — кадры 44 px в выбранную анимацию. Красное в
   «Проверках» — поправь до запекания.
10. **Старые персонажи и комнаты.** «Из игры» → враг, герой или комната →
    правь кадры (✎, замена кадра) или картину комнаты (🖌 «Перерисовать
    картину», тот же размер) → «→ В игру». Правка ляжет поверх того, что
    рисует генератор; робот пересоберёт картинки в той же отправке. «База
    изменилась — проверь» — генератор перерисовал картинку под правкой:
    посмотри и отправь ещё раз.
11. **🎮 Песочница** — открывается на всё окно (▣ — уменьшить в угол рядом с
    кадрами, ⛶ — весь экран компьютера): твой персонаж на тренировочном
   дворе, дерётся как выбранный враг и обновляется сам через пару секунд после
   правки. Кликни по игре, чтобы управлять. Ничего не отправляет.
12. **⚔ Сделать врагом** — персонаж становится врагом игры: выбираешь, на кого
   он похож по бою, имя, описание и подсказку «как драться».
13. Кадры: ＋ вставить, ⧉ дублировать, ⇋ отразить, → скопировать в другую
    анимацию. Звуки: обрезка — тяни ручки на волне; Cmd/Ctrl+Z работает везде.
14. В мастере врага: **Где появляется** — выбери комнату и кликни по полу на
    карте (зелёное — пол, красное — кто уже стоит). **Голос** — свои крики
    файлом или с микрофона. Катсцена: **🏠 В комнату** — при входе или после
    зачистки. Сцены комнат пересоберёт робот, ничего делать не нужно.
15. ⚡ без своего ключа: войди через GitHub — рисует робот ключом владельца.
16. **Оживление** — картина комнаты (катсцены, перехода, меню) живёт так же,
    как в игре: тот же шейдер. Тяни по картине — новая зона: водопад, вода,
    качается (знамя, мох, клетка), свечение (луна, витраж), лава, марево,
    звёзды, пульс. Зону двигают мышью и тянут за угол; «＋ Нарисовать» — новая
    поверх другой. Справа сила, скорость, цвет. Кнопки «Порыв», «Молния»,
    «Зачистка», ползунки «Босс» и «Раны», «Путь» — как место отвечает герою.
    «◐ Без жизни» — сравнить с нарисованным. → В игру меняет только твои
    правила в `data/backdrops.json` (не больше 24 зон на картину).
17. **🧱 Плитки** (во вкладке «Задники») — куски, из которых генератор
    складывает пол, полки и края комнат там, где их не нарисовала картина
    (тренировочный двор, пол церкви и нефа). Видно, где каждый лежит и как
    генератор кладёт ряд. ⬇ Скачать → перерисуй (📋 Промпт — для ChatGPT,
    приложи скачанный кусок образцом) → ⬆ Своя картинка или Cmd/Ctrl+V:
    студия подгонит к размеру куска. → В игру — кусок встанет во все комнаты.
18. **🩹 Швы** (Задники → комната → картина) — расширенная картина комнаты:
    полосы, которые вставил генератор, заметные первыми. ⬇ Кусок → в ChatGPT
    с 📋 Промптом → ⬆ Заплатка (или Cmd/Ctrl+V). Меняется только полоса между
    фиолетовыми рисками, края плавно сходятся; зелёные линии — пол, он должен
    остаться на месте. «◐ Было» — сравнить. Уходит правкой поверх генератора.
19. **Снаряды** — все дальние атаки: враги (культист, офаним, ревнитель,
    рыцарь пепла…) и дары героя. Справа превью: замах → залп → пауза, как в
    игре. Слева: как выглядит (стиль), как летит (прямо, волной, разгоняется,
    дугой, зависает, возвращается, наводится), скорость, сколько снарядов и
    веер, залпов подряд и пауза, разброс скорости, размер, урон, замах, цвет.
    Ниже — сам стиль: ⬆ свой спрайт (лента кадров слева направо), кадры,
    размер, вращение, пульс, дрожь, виляние, отражение позади, чем
    разбивается. «⧉ Новый» — свой стиль из этого. Стиль меняется у всех, кто
    им стреляет. → В игру меняет только то, что ты тронула.
    «＋ Дать дальнюю атаку» — любому персонажу, даже тому, кто бил только
    вблизи: новую с нуля или «на основе» любой дальней атаки из игры (берётся
    только то, как она стреляет). Можно дать вторую, третью. «⧉ Ещё одна
    такая» — копия выбранной. «🗑 Убрать атаку» — персонаж больше так не
    стреляет (одна атака у него должна остаться). «Показать персонажей» —
    кто стреляет и в кого, их спрайты из игры.
20. **Частицы** — дым из-под ног, искры, пепел, вспышки на любое действие
    любого персонажа. Слева: кто (Элиан или любой враг) и когда — анимация
    (бег, удар, прыжок…) или событие (шаг, прыжок, приземление, перекат,
    пробуждение). «＋ Частицы»: что вылетает (пыль, облачко, искры, пепел,
    осколки, кольцо, вспышка), откуда (ноги, тело, голова, рука, спина),
    когда (в начале, на выбранных кадрах, всё время каждые … секунд), сколько,
    цвет и прозрачность, куда летит, сдвиг. «точки» — показать, где на теле
    ноги, рука, голова. Дым под ногами Элиана теперь тоже здесь: шаг,
    приземление, перекат.
