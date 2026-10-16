# Глава II — что нарисовано и что осталось

*Картины главы «Уныние» (docs/CHAPTER2.md) нарисованы Codex CLI (`codex exec`, встроенная
генерация картинок) по промптам ниже и прошли обычный конвейер; глава в игре. Этот файл —
промпты, по которым их можно перерисовать, и список того, что Codex не сделал или сделал
слабо: это заказ художнице (её ChatGPT, навык `ashes-art`, `.claude/skills/ashes-art/SKILL.md`).*

## Состояние

| Что | Статус | Где |
|---|---|---|
| 12 панелей 1280×720 | **нарисованы Codex**, оттрассированы, проходимы (reach / stairs / void / smoke) | `assets/levels/seir_*.png`, `painted_rooms.py` |
| Атласы `watchman`, `waiting_townsman`, `gate_warden`, `drowned`, `drowned_bosun` | **нарисованы Codex**, нарезаны | `assets/sprites/enemy_atlases/`, `tree.json` |
| `sea_wraith` | перекрашенный `wraith` — оставлено как есть | `data/enemies/sea_wraith.json` |
| Портреты врагов (5) и людей (Лазарь, Иона, Ноеминь) | **нарисованы Codex**; портрет `sea_wraith` вышел бирюзовым, а наш дух — красного прилива: стоит портрет `wraith` | `assets/portraits/seir_*_atlas.png` |
| Листы тел людей (`lazarus`, `lazarus_quay`, `lazarus_tyre`, `jonah`, `naomi`) | **нарисованы Codex**: Лазарь лёжа (`lazarus_*`) и сидя (`lazarus_sit_*`, на пристани и в Тире), Иона, Ноеминь; режет `tools/art/build_people_sheets.py` из `assets/sprites/people_sheets/<id>.png` | `assets/sprites/<id>_{idle,walk,interact}.png` |
| Пластины глубины за проёмами (`depth/<room>_backfill.png`) и `DEPTH_WINDOWS` | **нет** — это новые картины (у главы I они дорисованы вручную, инструмента в репозитории нет), заказ в §3а | `generate_rooms.py` |
| Передний план (`front_layers.json`) | **вырезан** из своих картин в пяти комнатах (`seir_road`, `seir_square`, `seir_roofs`, `seir_quay`, `seir_wrecks`); в остальных тёмный ключ не отделяет предмет от стены — заказ в §3а | docs/DEPTH.md |
| Замурованные стены у тайников (`reveals`) | **нет** — тайники стоят открыто | `make_secret_walls.py` |
| Слабые места панелей | галерея складов (`seir_warehouses`) нарисована, но не достаётся прыжком — уступ снят; лестница маяка: третий марш на картине начинается над вторым, ход наверх — карнизы | `painted_rooms.py` |

Порядок, если перерисовывать: сначала пластины глубины
и передний план, потом панели, которые хочется лучше.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: тёмный готический пиксель-арт, нарисованный, а не из
тайлов; ночь; читаемость прежде красоты; нижняя пятая часть фона тёмная и тихая — там тела.
Что меняется в Сеире:

- **Город, а не кладбище.** Каменные дома в два-три этажа, ставни, пороги, вывески без букв,
  бельевые верёвки, часы на башне. Камень тёплее, чем в главе I: охра и песчаник под
  холодной ночью, а не сине-серая кладка.
- **Свет.** Окна города тёмные — почти все. Тёплый свет только там, где кто-то ждёт: лампа
  Ноемини, огонь маяка, редкие свечи на подоконниках. Красный — море и вода каналов (вторая
  труба: третья часть моря стала кровью), тусклый, тёмно-винный, не алый; больше красный в
  главе ничем не занят.
- **Тишина.** Ничего не горит, ничего не разрушено боем. Опустение — пыль, неубранные столы,
  остановленные часы, лодки у причала, повернутые к морю стулья. Люди сидят — на порогах, на
  ступенях, на краю причала.
- **Море** стоит как стекло, без волн, с красным отливом и чёрными остовами кораблей.

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent stone sizes. A deserted harbour city at night: ochre and sandstone
> houses under cold blue night light, almost every window dark; the only warm lights are a few
> candles and lamps. Where water is visible it is still as glass and dull wine-red. Quiet,
> abandoned, not ruined by battle: dust, shutters, stopped clocks, chairs turned to face the
> sea. Gentle contrast so enemies and hero remain legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. Entrance at the left edge, a real dark doorway or
> passage at the far right (about 97 percent across) for the game's exit gate. Ledges a person
> could stand on drawn as flat-topped ledges with readable edges, no floating platforms. The
> bottom fifth stays dark and quiet. Opaque canvas, artwork to every edge. No characters, no
> people, no text, no letters, no labels, no UI, no watermark, no border.

## 1. Панели комнат — 12 штук, 1280×720 (нарисованы Codex)

Каждая — `assets/levels/<id>.png`, 16:9 (ChatGPT рисует 1536×1024 или 1792×1024 — студия
кадрирует и масштабирует; размер в промпт **не** писать). Генератор потом расширит её до 1600
швами (`_quilt_band`): ориентиры держать подальше от 35 % и 65 % ширины или назвать их в
`FOCAL_RANGES`. После картины: `tools/rooms/trace_panel.py`, `<id>.lights.json` на нарисованные
огни, `RoomLayers.FAR_WINDOWS` для проёмов в небо, правило в `data/backdrops.json`.

Картинки-роли во всех промптах панелей:
**Image 1** — игровой стиль: `assets/levels/graveyard_arches.png` (масштаб камня, толщина
уступов, темнота — ТОЛЬКО это, не архитектура кладбища). **Image 2** — референс места, если
она его выберет (фото или картина), иначе не прикладывать.

| # | id | Что на картине (Primary request + Composition) | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `seir_road` | A dusty road outside a walled city at night; a dead tree, a milestone, the city wall and a closed gate far right. Low, mostly flat ground with one raised bank. | Лазарь лежит у мильного камня в левой трети; вороны на дереве. |
| 2 | `seir_gate` | The city gate seen from inside the gatehouse: a vaulted passage, guard benches, a bricked-up guardroom door on the upper level, a portcullis half raised on the right. | Два привратника под аркой; тайник за замурованной дверью наверху. |
| 3 | `seir_street` | A narrow street of three-storey houses; doorsteps with stone steps, balconies with shutters (two upper windows faintly lit — the shades' windows), washing lines. Two walkable balcony levels. | Ждущие на порогах; тени в верхних окнах. |
| 4 | `seir_square` | A town square with a clock tower whose hands have stopped, a dry fountain in the centre, a flat roof on the right (east) high enough to sit on, café tables left out. | Иона на восточной крыше; место отдыха — фонтан. Дверь на развилку справа. |
| 5а | `seir_roofs` | Rooftops: chimneys, a broken belfry, ridge lines and dormer windows at several heights; the dark city below. Vertical, two screens tall. | Тени у слуховых окон, вороны на трубах. |
| 5б | `seir_canal` | A canal with dull red still water between stone embankments, two footbridges, moored rowing boats. Embankment ledges at two heights; water at the bottom is a fall. | Утопленники вылезают из воды. |
| 6 | `seir_quay` | The harbour quay: a long stone pier, a bench with one oil lamp burning (the only warm light), a small sailors' shrine with a carved boat, bollards, the red still sea behind. | Ноеминь на скамье у лампы; место отдыха — часовня. |
| 7 | `seir_wrecks` | Burned ship hulls beached at low tide, ribs and masts, a cabin with a sealed door on one wreck's deck, the red sea. Walkable decks at several heights. | Боцман на палубе; тайник в каюте. |
| 8а | `seir_warehouses` | Inside a grain warehouse: sacks, rotting grain heaps, loading galleries, hoists, low beams. Close and dark. | — |
| 8б | `seir_breakwater` | The breakwater running out to sea: open sky, a long stone mole with broken steps, the red sea on both sides, the lighthouse visible far right. | Духи прилива над водой. Падение в море — смерть. |
| 9 | `seir_lighthouse_stair` | The inside of a lighthouse tower: a spiral stone stair seen in cross-section, landings with small niches, one niche holds a sealed letter. Two screens tall. | Тайник в нише на средней площадке. |
| 10 | `seir_lighthouse` | The lamp room at the top: a great oil lamp behind glass on the right, a gallery rail, the night sea through the windows; one screen tall, flat floor for a boss fight. | Сторож между Элианом и огнём. |

Промпт панели целиком (пример для `seir_quay`; остальные — так же, со своей строкой из таблицы):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark
> fantasy pixel-art platformer, chapter II "Seir, the waiting city".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> darkness ONLY — not its architecture.
> **Primary request:** The harbour quay: a long stone pier, a bench with one oil lamp burning
> (the only warm light), a small sailors' shrine with a carved boat, bollards, the red still sea
> behind.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

## 2. Враги — атласы 7×7 (нарисованы Codex, кроме `sea_wraith`)

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`, «Enemies»). Режет
`tools/art/build_bestiary_assets.py`. Один новый чат ChatGPT на атлас. Роли:
**Image 1** — дизайн персонажа (её референс или одобренный первый кадр);
**Image 2** — `tools/studio/refs/elian_style_idle.png`: масштаб, контур, темнота палитры ТОЛЬКО,
не его броня и не меч. Клетку и масштаб задаёт `GAME_CELLS` в сборщике, полосы — `sprite` в `data/enemies/<id>.json`
и `data/enemy_archetypes/tree.json`.

| id | Кто | Рост (от героя, 44) | material | Ряды, на что смотреть | Сейчас стоит |
|---|---|---|---|---|---|
| `watchman` (босс) | Старый сторож маяка в выцветшем дозорном плаще поверх кольчуги, алебарда, на поясе фонарь; лицо в тени капюшона, седая борода | 56–60 | mail | idle — стоит, опершись на алебарду, смотрит вдаль; attack — **долгий** отвод алебарды назад (2–3 кадра замаха), удар; attack_alt — поднимает фонарь, тот разгорается (луч рисует игра); special — «долгое ожидание»: алебарда над головой, неподвижно, потом рубит; death — опускается на колено, не падает | `knight_of_ash` |
| `waiting_townsman` | Горожанин в домашней одежде, сутулый, пустой взгляд; idle **сидя на пороге** | 40–44 | cloth | idle — сидит; walk — медленно, шаркая; attack — встаёт и неловко бьёт кулаком (замах виден); hurt; death — садится обратно и замирает | `possessed_villager` |
| `gate_warden` | Привратник в старой форме городской стражи, шлем-шапель, алебарда, плащ цвета охры | 46–48 | mail | idle — стоит на посту; attack — длинный замах алебардой сверху | `fallen_guard` |
| `drowned` | Утопленник: мокрая одежда моряка, водоросли, синевато-серая кожа, с него капает; тянет руки | 42–44 | flesh | attack — руки вверх и назад, хватает; attack_alt — бросок вперёд (лунж) | `possessed_villager` (тонирован) |
| `drowned_bosun` | Утопший боцман: широкий, в рваной куртке, якорная цепь в кулаках, якорь за спиной | 54–58 | flesh | attack — якорь поднимается над головой, бьёт широко; attack_alt — отводит цепь назад, бросает прямо | `fallen_champion` |
| `sea_wraith` | *(не обязательно)* Дух красного прилива: полупрозрачная волна с лицом, винно-красный | 40 | spirit | сейчас честно перекрашенный `wraith` — можно оставить | `wraith` |

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, по одному кадру idle.

## 3. Люди — листы NPC и портреты (нарисованы Codex)

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет для диалогов — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли те же: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png` (масштаб/контур/темнота).

Как нарисованы листы: Codex рисует лист 4×3 (ряды idle, walk, interact; фигура смотрит
**вправо**) на ровной мадженте `#FF00FF` по раскладке `npc_sources/matthew_v2_atlas.png`
(стоя) или `tirzah_v2_atlas.png` (сидя) и портрету героя как Image 3; маджента снимается в
альфу, лист кладётся в `assets/sprites/people_sheets/<id>.png` (не импортируется:
`.gdignore`), `tools/art/build_people_sheets.py <id>` режет его в клетки 48×48 — рост тела
из `PEOPLE` (лежачего — по длине), центр по медиане ряда idle. Генератор в
`check_generators.py`, правки студии — через `patched()`.

| id | Кто | Поза idle | interact | Сейчас стоит |
|---|---|---|---|---|
| `lazarus` | Нищий у дороги: худой, в лохмотьях, босой, на плечах тряпица; лежит на боку у камня | лежит, медленно дышит | приподнимается на локте | **свой** (`lazarus_*`) |
| `lazarus_quay` | Тот же Лазарь, **сидя** на скамье (тот же лист, отдельная полоса idle) | сидит | поднимает голову | **свой** (`lazarus_sit_*`) |
| `jonah` | Пророк: всклокоченная борода, власяница, посох; сидит на краю крыши, ноги свешены | сидит, смотрит вниз на город | встаёт, указывает посохом | **свой** |
| `naomi` | Вдова в тёмном платке, немолодая, прямая спина, в руках масляная лампа | сидит на скамье, лампа на коленях | поднимает лампу выше | **свой** |
| (портрет) `watchman` | Сторож крупно: капюшон, борода, свет фонаря снизу | — | — | — |

## 3а. Глубина: пластины за проёмами и передний план

**Передний план.** Куски режет `tools/rooms/front.py` из собственных картин комнат
(`front_layers.json`), проверены `depth_shot.gd`:

| Комната | Кусок | Где читается |
|---|---|---|
| `seir_road` | ветви мёртвого дерева с утёса | над морем и лунной дорожкой |
| `seir_square` | мачты с такелажем из гавани | перед фонтаном |
| `seir_roofs` | кипарис | поднимается снизу перед крышами |
| `seir_quay` | мачта затонувшего корабля | над красной водой |
| `seir_wrecks` | косая сломанная мачта с цепями | перед правым корпусом |

В `seir_gate`, `seir_street`, `seir_canal`, `seir_warehouses`, `seir_breakwater`,
`seir_lighthouse_stair` и `seir_lighthouse` вырезать нечего: железо люстры, копья, фонари и штурвал так же темны, как
кладка за ними, тёмный ключ оставляет прямоугольник стены, а освещённые столбы не тёмные.
Им нужны **прозрачные PNG** (`assets/levels/pieces/<имя>.png`, ключ `alpha`, «🖼 Своя спереди»
в студии): люстра на цепи и стойка копий (ворота), бельевая верёвка с простынями (улица),
навес лавки (канал), фонарный столб и кнехт (мол), фонарь на цепи (лестница маяка),
штурвал и цепь у окна (маяк), сетка с грузом и цепь с крюком (склады). Тот же стиль, что у панели, силуэт без фона, 1:1 пиксели.

**Дальний план.** `DEPTH_WINDOWS` пусты: пластина — это та же панель, где ближние предметы
убраны и даль дописана (как `assets/levels/depth/swamp_moon_backfill.png` рядом с
`swamp_moon.png`), чтобы при сдвиге до 16 px в проёме не было пустоты. Подделать её копией
панели нельзя — край ближнего предмета поедет вместе с далью. Заказ, 1280×720, промпт панели +
«the same view with every near object removed; continue the distant city, sea and sky behind
them»:

| Комната | Проём (что видно) | Что дорисовать на пластине |
|---|---|---|
| `seir_road` | небо, море и дальние скалы левее башни ворот | море и утёсы за деревом и мильным камнем |
| `seir_gate` | море и город за решёткой и в узких окнах | гавань за решёткой целиком, без прутьев |
| `seir_street` | просветы между домами (мачты, город) | ночной город и мачты за домами |
| `seir_square` | гавань с мачтами и город за часовой башней | гавань и город без башни и навеса |
| `seir_roofs` | красное море и город над крышами | море и даль за колокольней и трубами |
| `seir_canal` | город и собор над мостами и под арками | канал, уходящий вдаль, без мостов |
| `seir_quay` | город и мачты за красной водой | гавань без часовни и кнехтов |
| `seir_wrecks` | город и купол за корпусами | город за кораблями |
| `seir_breakwater` | небо и горизонт над молом и под арками | море и небо без мола |
| `seir_lighthouse` | море и город в окнах фонарной | вид из окон без переплётов |

Склады и лестница маяка — интерьеры без дали (окна-щели), им пластина не нужна. Когда
пластина есть: `depth/<room>_backfill.png`, многоугольники проёмов в `DEPTH_WINDOWS`
(`generate_rooms.py`), номера дальних проёмов в `RoomLayers.FAR_WINDOWS`, потом
`layers_test.gd`, `depth_shot.gd`.

## 4. Как это было нарисовано

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`,
по 3–4 минуты на картинку. Панели — по промпту §1 с картиной главы I как ролью стиля; атласы — с
атласом `fallen_guard` (раскладка 7×7) и `tools/studio/refs/elian_style_idle.png` (масштаб, контур);
портреты — с `enemies_atlas.png` / `people_atlas.png`. Затем: панель → `trace_panel.py <путь.png> <id>`
→ строка в `painted_rooms.py` → `generate_rooms.py`; атлас → `enemy_atlases/<id>.png` + `GAME_CELLS`
→ `build_bestiary_assets.py`. Все выходы идут через `patched()` (правки студии).

## 5. Проверка перед pull request

- `make validate`.
- `reach_test.gd -- seir_<id>`, `stairs_test.gd`, `void_fall_test.gd` на каждую новую комнату.
- Бестиарий: каждая полоса против своей клетки (валидатор), рост против героя.
