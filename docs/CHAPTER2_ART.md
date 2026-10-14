# Глава II — заказ художнице

*Всё, что нужно нарисовать, чтобы глава «Уныние» (docs/CHAPTER2.md) стала играбельной. Больше её
ничего не держит: данные, тексты, сцены и проверки готовы в `drafts/chapter_2/`. Рисует
художница в своём ChatGPT по правилам навыка `ashes-art` (`.claude/skills/ashes-art/SKILL.md`):
агент готовит промпт и картинки-роли, Enter нажимает она.*

Порядок — по важности для игры: сначала 12 панелей (без них нет комнат), потом Сторож и
ждущий (их больше всего на экране), потом остальные враги, люди, портреты.

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

## 1. Панели комнат — 12 штук, 1280×720

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

## 2. Враги — атласы 7×7

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`, «Enemies»). Режет
`tools/art/build_bestiary_assets.py`. Один новый чат ChatGPT на атлас. Роли:
**Image 1** — дизайн персонажа (её референс или одобренный первый кадр);
**Image 2** — `tools/studio/refs/elian_style_idle.png`: масштаб, контур, темнота палитры ТОЛЬКО,
не его броня и не меч. После атласа — убрать `"sprite": {"like": …}` в
`drafts/chapter_2/data/enemies/chapter_2.json`.

| id | Кто | Рост (от героя, 44) | material | Ряды, на что смотреть | Сейчас стоит |
|---|---|---|---|---|---|
| `watchman` (босс) | Старый сторож маяка в выцветшем дозорном плаще поверх кольчуги, алебарда, на поясе фонарь; лицо в тени капюшона, седая борода | 56–60 | mail | idle — стоит, опершись на алебарду, смотрит вдаль; attack — **долгий** отвод алебарды назад (2–3 кадра замаха), удар; attack_alt — поднимает фонарь, тот разгорается (луч рисует игра); special — «долгое ожидание»: алебарда над головой, неподвижно, потом рубит; death — опускается на колено, не падает | `knight_of_ash` |
| `waiting_townsman` | Горожанин в домашней одежде, сутулый, пустой взгляд; idle **сидя на пороге** | 40–44 | cloth | idle — сидит; walk — медленно, шаркая; attack — встаёт и неловко бьёт кулаком (замах виден); hurt; death — садится обратно и замирает | `possessed_villager` |
| `gate_warden` | Привратник в старой форме городской стражи, шлем-шапель, алебарда, плащ цвета охры | 46–48 | mail | idle — стоит на посту; attack — длинный замах алебардой сверху | `fallen_guard` |
| `drowned` | Утопленник: мокрая одежда моряка, водоросли, синевато-серая кожа, с него капает; тянет руки | 42–44 | flesh | attack — руки вверх и назад, хватает; attack_alt — бросок вперёд (лунж) | `possessed_villager` (тонирован) |
| `drowned_bosun` | Утопший боцман: широкий, в рваной куртке, якорная цепь в кулаках, якорь за спиной | 54–58 | flesh | attack — якорь поднимается над головой, бьёт широко; attack_alt — отводит цепь назад, бросает прямо | `fallen_champion` |
| `sea_wraith` | *(не обязательно)* Дух красного прилива: полупрозрачная волна с лицом, винно-красный | 40 | spirit | сейчас честно перекрашенный `wraith` — можно оставить | `wraith` |

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, по одному кадру idle.

## 3. Люди — листы NPC и портреты

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет для диалогов — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли те же: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png` (масштаб/контур/темнота).

| id | Кто | Поза idle | interact | Сейчас стоит |
|---|---|---|---|---|
| `lazarus` | Нищий у дороги: худой, в лохмотьях, босой, на плечах тряпица; лежит на боку у камня | лежит, медленно дышит | приподнимается на локте | `severin_v2` |
| `lazarus_quay` | Тот же Лазарь, **сидя** на скамье (тот же лист, отдельная полоса idle) | сидит | поднимает голову | `severin_v2` |
| `jonah` | Пророк: всклокоченная борода, власяница, посох; сидит на краю крыши, ноги свешены | сидит, смотрит вниз на город | встаёт, указывает посохом | `matthew_v2` |
| `naomi` | Вдова в тёмном платке, немолодая, прямая спина, в руках масляная лампа | сидит на скамье, лампа на коленях | поднимает лампу выше | `villager_v2` |
| (портрет) `watchman` | Сторож крупно: капюшон, борода, свет фонаря снизу | — | — | — |

## 4. Чем собрать черновые комнаты сейчас

Пока панелей нет, Конструктор (`docs/ROOM_COMPOSER.md`, `composed_rooms.json`) может собрать
проходимый черновик из картин главы I — чтобы проверить ритм «пустых» и «настоящих» комнат.
Заменители (поле `stand_in` в `drafts/chapter_2/rooms.json`, валидатор проверяет, что они есть):

| Комната главы II | Картины главы I | Почему |
|---|---|---|
| `seir_road` | `village_night` | дорога у стены деревни, мало уступов |
| `seir_gate` | `graveyard_arches` | арки = проход ворот, верхний ярус для тайника |
| `seir_street` | `graveyard_cross` + `catacombs_1` | длинная улица с двумя уровнями |
| `seir_square` | `church` | открытый зал с высокой точкой справа |
| `seir_roofs` | `graveyard_tree` | вертикаль |
| `seir_canal`, `seir_breakwater` | `swamp_red` | красная вода уже нарисована |
| `seir_quay` | `swamp_moon` | вода под луной, длинный ровный берег |
| `seir_wrecks` | `swamp_crypt` | остовы над водой |
| `seir_warehouses` | `catacombs_2` | тесно и низко |
| `seir_lighthouse_stair` | `catacombs_3` | двухэкранная вертикаль |
| `seir_lighthouse` | `preacher_nave` | одноэкранная арена босса |

## 5. Проверка перед pull request

- `make validate`: валидатор проверяет и черновик; как только появляется сцена
  `scenes/rooms/seir_*.tscn`, она перестаёт быть «ждущей картины» и проверяется как любая.
- `reach_test.gd -- seir_<id>`, `stairs_test.gd`, `void_fall_test.gd` на каждую новую комнату.
- Бестиарий: каждая полоса против своей клетки (валидатор), рост против героя.
