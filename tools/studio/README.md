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
```



## Для художника (как пользоваться)

1. Открой <https://saaayurii.github.io/ashes-of-eden/studio/>. Справа вверху
   **Войти**: студия покажет, как получить ключ GitHub (нужно один раз).
2. **Персонажи.** Новый персонаж → вставь референс → выбери анимацию →
   «📋 Промпт» / «📋 Промпт ленты» в ChatGPT вместе с `refs/elian_style_draw.png`
   → картинку обратно Cmd/Ctrl+V. Масштаб «Сетка пикселей + подогнать рост»
   снимает сетку и ставит рост как у героя (44 px). Все кадры одной анимации —
   из одного чата. Кривой пиксель — «✎». Длительность кадра — «Длит. ×».
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
10. **🎮 Песочница** — игра рядом с кадрами: твой персонаж на тренировочном
   дворе, дерётся как выбранный враг и обновляется сам через пару секунд после
   правки. Кликни по игре, чтобы управлять. Ничего не отправляет.
11. **⚔ Сделать врагом** — персонаж становится врагом игры: выбираешь, на кого
   он похож по бою, имя, описание и подсказку «как драться».
12. Кадры: ＋ вставить, ⧉ дублировать, ⇋ отразить, → скопировать в другую
    анимацию. Звуки: обрезка — тяни ручки на волне; Cmd/Ctrl+Z работает везде.
13. В мастере врага: **Где появляется** — выбери комнату и кликни по полу на
    карте (зелёное — пол, красное — кто уже стоит). **Голос** — свои крики
    файлом или с микрофона. Катсцена: **🏠 В комнату** — при входе или после
    зачистки. Сцены комнат пересоберёт робот, ничего делать не нужно.
14. ⚡ без своего ключа: войди через GitHub — рисует робот ключом владельца.
