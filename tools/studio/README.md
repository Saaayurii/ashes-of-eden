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

```sh
python3 -m unittest discover -s tools/studio/tests   # converter, server guard
node --test tools/studio/tests/*.test.js             # lib.js, formats against the real files
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
6. **→ В игру** — отправить; **☁ Поделиться** — сохранить проект для всех;
   **⬇ zip** — скачать файлы себе. Ошиблась — Cmd/Ctrl+Z.
