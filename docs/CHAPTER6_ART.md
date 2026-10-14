# Глава VI — заказ картин

*Картины главы «Зависть» (docs/CHAPTER6.md): обитель на Евфрате, монахи, цепи, четверо связанных.
Панели и атлас босса нарисованы; остальное — заказ. Рисует Codex CLI (`codex exec`, встроенная генерация
картинок) по промптам ниже, как Сеир (`CHAPTER2_ART.md`); слабое — художнице (её ChatGPT, навык
`ashes-art`). Источник правды для палитры — `docs/CAMPAIGN.md` §10.*

## Состояние

| Что | Статус | Что стоит пока |
|---|---|---|
| 12 комнат: 11 панелей 1280×720 + колокольня из двух (`euphrates_bell_tower` + `panels/euphrates_bell_tower_top`) — 13 картин | **нарисовано** (Codex), трассировано в `painted_rooms.py`, расширено `generate_rooms.py`; колокольня — живая составная | — |
| Атлас `four_bound` | **нарисовано** (Codex), полосы `four_bound_v2_*` | — |
| Атласы `flagellant`, `censer_monk`, `chained_penitent`, `horseman`, `river_wraith`, `fettered_angel`, `lion_horse` | **не нарисовано** | `cultist` (тон `#c8b8a0`), `preacher_acolyte`, `possessed_villager` (тон `#b8a898`), `fallen_champion`, `wraith` (тон `#9fb8a8`), `elder_wraith` (тон `#cfe6ff`), `fallen_champion` (тон `#e0b070`), `knight_of_ash` (тон `#cfe6ff`) |
| Портреты врагов (8) | **не нарисовано** | портреты подменных |
| Листы людей `saul`, `euphrates_reveller`, `witness` | **не нарисовано** | `matthew_v2`, `villager_v2`, `severin_v2` (лёжа — первый кадр `death`) |
| `malchus_far` | лист Малха из главы III | — |
| Портреты людей: `saul`, `mighty_angel`, `reveller`, `bound_hour` / `_day` / `_month` / `_year` | **не нарисовано** | `matthew`, `ophanim`, `villager`, `ophanim` (тоном) |
| Проп `chain_ring.png` (3 кадра 32×32) | **не нарисовано** | `rubble` без кадров |
| Снаряд `incense_flight_v3.png` (4 кадра 96×128) | **не нарисовано** | `ash_flight_v3` |
| Пластины глубины (`depth/<room>_backfill.png`), `DEPTH_WINDOWS` | **нет** | проёмы стоят |
| Передний план (`front_layers.json`) | **нет** | — |
| Замурованные стены у тайников (`reveals`) ×3 | **нет** | тайники открыто |

Порядок: панели (без них нет комнат) → атласы (босс и элита первыми) → листы людей и портреты →
кольцо, ладан → глубина и передний план → стены тайников.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: тёмный готический пиксель-арт, нарисованный, а не из тайлов;
ночь; читаемость прежде красоты; нижняя пятая часть тёмная и тихая — там тела. Что меняется на
Евфрате:

- **Громкий цвет главы — золото алтаря** с четырьмя рогами (тёплое, тяжёлое, не жёлтое) и **железо
  цепей** (чёрно-серое с холодным бликом). Больше золото ничем не занято: ни лампы, ни нимбы не
  золотые — лампы монахов тёплые, оранжево-охристые и маленькие.
- **Земля** — речной ил, сырцовый кирпич (тёплая охра, выкрошенные швы, солома в кирпиче), известняк
  обители (светлее кирпича, тёсаный), тёмная вода — почти чёрная, с зеленоватым отливом ила.
- **Свет.** Два и только два: **лампады монахов** — тёплые точки в нишах, у столов, на цепочках
  кадил; **свет ангелов в цепях** — холодный, бело-голубой (`#cfe6ff`), ровный, без мерцания. Чем
  ниже к руслу, тем меньше тёплого и больше холодного. Красный остаётся за кровью и соблазном — его в
  главе нет, кроме тусклого ржавого на нагрудниках всадников.
- **Цепи везде.** Кольца в стенах на разной высоте, цепи на полу, свисающие с балок, обрывки у
  колоколов. Нарисованные цепи — декор; цепи, которые держат тела, рисует игра (Line2D) — значит
  **не рисовать цепь, ведущую к месту, где будет стоять враг**: только кольцо.
- **Река.** Евфрат — широкий, медленный, тёмный; берег из ила и тростника. Под обителью — русло:
  свод из кирпича и камня, вода сочится сверху, на полу лужи.
- **Монахи** — без лиц на картинах (капюшоны); людей на картинах нет вообще, кроме ангела с книжкой
  (комната 1), который — часть пейзажа.

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent brick and stone sizes. A monastery on the great river Euphrates at night:
> warm ochre mud brick with straw in it, pale dressed limestone, river silt, dark still water with a
> green-black sheen. Iron chains and wall rings everywhere, black-grey with a cold glint. The only
> warm lights are small monks' oil lamps in niches; the only other light is a cold, even, pale
> blue-white glow. Gold appears only on the four-horned altar. No red anywhere. Quiet, devout,
> oppressive; gentle contrast so enemies and hero remain legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. A continuous walkable floor along the bottom quarter unless
> the request says otherwise. Entrance at the left edge; a real dark doorway or passage at the far
> right (about 97 percent across), standing on a floor, for the game's exit gate. Every ledge,
> balcony, landing and stair drawn flat-topped with readable edges, attached to a wall, column or
> rock under it — no floating platforms. Keep landmarks away from 35 percent and 65 percent of the
> width. Do not draw chains running to an empty spot of floor; draw only the wall rings there. The
> bottom fifth stays dark and quiet. Opaque canvas, artwork to every edge. No characters, no people,
> no monks, no text, no letters, no labels, no UI, no watermark, no border.

## 1. Панели комнат — 13 картин, 1280×720

Каждая — `assets/levels/<id>.png` (верх колокольни — `assets/levels/panels/euphrates_bell_tower_top.png`),
16:9 (размер в промпт **не** писать — студия кадрирует). Генератор расширит до 1600 швами
(`_quilt_band`) у 35 % и 65 % ширины: ориентиры держать подальше или назвать в `FOCAL_RANGES`
(предложено в таблице). Высоты ниже — **доля высоты панели от верха** (0 % — верх, 100 % — низ).
После картины: `tools/rooms/trace_panel.py`, `<id>.lights.json`, `RoomLayers.FAR_WINDOWS`, правило в
`data/backdrops.json` (§4).

Картинки-роли: **Image 1** — стиль: `assets/levels/graveyard_arches.png` (масштаб камня, толщина
уступов, темнота — ТОЛЬКО это); для интерьеров (3–10) — `assets/levels/seir_lighthouse_stair.png` или
`seir_warehouses.png`. **Image 2** — её референс места, если выберет (Месопотамия: сырцовые стены,
монастыри Тур-Абдина, Мар-Маттай), иначе не прикладывать.

| # | id | Primary request + Composition | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `euphrates_bank` | The muddy bank of a wide dark river at night under a storm. Composition: a continuous walkable mud-and-silt floor along the bottom quarter from the left edge to about 58 percent; then a shallow ford of still dark water from 58 to 80 percent, its surface at about 80 percent of the height; the bank rises again from 80 percent to the right edge with a crumbling mud-brick arch, a real dark passage, at about 97 percent. One raised flat-topped mud-brick embankment in the left third, top at about 62 percent, reached by a low earthen slope. Reeds along the water. Huge in the far depth, between 42 and 60 percent of the width, a colossal faint angel stands with one foot on the river and one on the far bank, an open small book in its raised hand, its face a pale glow under the clouds; the whole sky across the top third is an opening to storm clouds with lightning far off. | Ангел — пейзаж, не тело: `FOCAL_RANGES` (540, 770). Сцена `little_book`: камера к [640, 230]. Духи реки над бродом, всадник на берегу справа. Брод — `water` (плавание, не смерть). Небо — `FAR_WINDOWS`. |
| 2 | `euphrates_town` | A street of a mud-brick town at a river ford, during a night feast: long tables with cloths, jugs and bread outside the houses, strings of small lanterns between flat roofs, garlands, wrapped gifts piled on doorsteps. Composition: continuous cobbled floor along the bottom quarter; the open middle of the street (40–60 percent) is bare cobbles, nothing standing there; a flat-topped roof terrace in the left third, top at about 52 percent, reached by an outside mud-brick stair; a wooden awning in the middle third, top at about 66 percent, on posts; a flat roof in the right third at about 50 percent. A narrow strip of night sky between the roofs at the top. At about 97 percent on the right, a dark town gate passage toward the monastery. | Свидетели лежат посередине (600–700, на полу) — **тела не рисовать**, это спрайты. Пирующие у столов слева и справа. Малх уходит вправо по улице. Бичующиеся на полу и под навесом. |
| 3 | `euphrates_gate` | Inside the gate of a fortified monastery: a thick mud-brick and limestone wall, the deep arched gate passage at the left edge (entrance), a packed-earth courtyard floor along the bottom quarter. In the right third, a porter's lodge built against the wall with a flat-topped wooden balcony at about 45 percent, reached by a stone stair rising from the middle third; on the balcony, a bricked-up doorway in the lodge wall. Two iron wall rings low on the courtyard wall. Oil lamps in niches beside the gate. A real dark doorway into the cloister at about 97 percent on the floor. | Тайник `note_chain_roll` — за замурованной дверью на балконе (стена — `make_secret_walls.py`). Бичующиеся во дворе, кадильщики на балконе и у лестницы. |
| 4а | `euphrates_cloister` | A monastery cloister: an arcade of round mud-brick arches on stone columns along the back, a garth with a dead fig tree and a stone well seen through the arches, the night sky above the garth. Composition: continuous flagstone floor along the bottom quarter; an upper gallery walkway running along the top of the arcade at about 40 percent, flat-topped, from the left edge to about 45 percent and again from 55 percent to the right edge (a real gap in the middle where the roof fell); wooden stairs up to the gallery at both ends. Keep the fig tree at about 20 percent and the well at about 80 percent. A dark doorway at about 97 percent on the floor. | Развилка — без истории. Бичующиеся на полу и галерее, кадильщик на галерее, всадник в саду (на полу). Небо над садом — `FAR_WINDOWS`. |
| 4б | `euphrates_scriptorium` | A monastery scriptorium: tall wooden shelves of scrolls and codices, writing desks with books chained to them, a lectern, small oil lamps. Composition: floor along the bottom quarter; three tiers of flat-topped plank walkways along the shelves: at about 70 percent (left and middle thirds), at about 50 percent (middle and right thirds), at about 30 percent (left third), joined by wooden ladders and short stairs drawn against the shelves. No windows, no sky. One iron ring on the wall by a desk at floor level in the middle third. A dark low doorway at about 97 percent on the floor. | Развилка — без истории. Прикованный переписчик у кольца (якорь), кадильщики на ярусах. |
| 5 | `euphrates_refectory` | A monastery refectory: one very long table with benches running across the room, bread laid out and untouched, clay cups, a reader's pulpit on the wall in the left-middle with a narrow stair to it (pulpit top at about 50 percent), a raised abbot's dais in the right third (top at about 72 percent, two steps), a large domed bread oven in the right third against the wall with a lamp burning on it. Small high arched windows with night outside. A cellar hatch in the floor at the left third, closed. Floor along the bottom quarter. A dark doorway at about 97 percent. | Место отдыха — у печи ≈ [980, 590]. Саул у помоста (NPC). Бичующиеся и кадильщик в левой трети (у погреба). Окна — маленькие, `FAR_WINDOWS` по желанию. |
| 6 | `euphrates_bell_tower` (низ) | The base of a square monastery bell tower, seen in cross-section: stone and mud-brick walls, bell ropes hanging down from above through the ceiling, iron rings on the walls at several heights. Composition: floor along the bottom quarter with the entrance at the left edge; flat-topped stone landings joined by straight stairs along the walls: a landing in the right third at about 75 percent, a landing in the left third at about 50 percent, a landing across the middle third at about 25 percent, and from it a stair going up out of the top edge in the right third (it continues in the upper panel). Two iron rings on the wall beside the lower landings. Lamps in niches. No exit on this panel's right edge — the way continues up. | Нижняя клетка составной комнаты (`composed_rooms.json`, `col 0, row 1`). Прикованные у колец (якоря), кадильщики на площадках. |
| 6 | `panels/euphrates_bell_tower_top` (верх) | The top of the same bell tower: three bronze bells in a heavy timber frame, the belfry's arched openings to a stormy night sky on both sides. Composition: the stair from below arrives through the floor in the right third; a flat-topped stone landing across the bottom at about 80 percent; a timber walkway under the bells in the left third at about 55 percent, reached by a ladder; a top walkway at about 30 percent running from the middle third to the right edge, ending in a real dark doorway at about 97 percent (the way out onto the roof). One iron ring high on the wall under the bells; a bricked-up niche beside the bells at the 55 percent walkway. | Верхняя клетка (`col 0, row 0`). Скованный ангел у кольца под колоколами. Тайник `note_seven_thunders` — замурованная ниша у колоколов. Арки — `FAR_WINDOWS`. Колокола — `FOCAL_RANGES` или вне швов. |
| 7 | `euphrates_altar_court` | An open monastery court around a golden altar with four horns at its corners, standing on a stepped stone dais in the centre; the altar's gold is the brightest thing in the chapter. Composition: flagstone floor along the bottom quarter; the dais in the middle third, its flat top at about 70 percent with two broad steps each side; a colonnade along the back with a flat-topped upper walk in the left third at about 45 percent and in the right third at about 45 percent, stairs up to each; the night sky over the court as an opening across the top. Two iron rings on the colonnade's base. Keep the altar between 44 and 58 percent. A dark doorway going down at about 97 percent on the floor. | Алтарь — `FOCAL_RANGES` (560, 745); сцена `voice_from_the_horns`, камера к рогам. Конь с львиной головой у помоста. Прикованные у колец. Небо — `FAR_WINDOWS`. |
| 8а | `euphrates_crypt_of_chains` | A low vaulted crypt under the monastery whose walls are hung with chains and iron rings at many heights, empty shackles, old prayer cloths. Composition: floor along the bottom quarter; a flat-topped stone shelf (an old tomb ledge) in the middle third at about 60 percent; another in the right third at about 45 percent, reached by worn steps; seven iron rings on the walls and piers at floor level and at the shelves. Cold pale light from cracks; one or two monks' lamps. A dark doorway at about 97 percent. | Развилка — без истории (кольца — не история). Пять прикованных, два скованных у колец (якоря), кадильщик на полке. |
| 8б | `euphrates_cistern` | A large underground cistern: rows of stone columns rising from dark still water, a vaulted ceiling. Composition: a stone walkway as floor along the bottom quarter at the left (0–30 percent) and at the right (70–100 percent); between them the water, its surface at about 82 percent; three flat-topped column plinths standing out of the water in the middle at about 68 percent, a jump apart; a narrow ledge along the back wall at about 40 percent over the middle third. A dark doorway at about 97 percent on the right walkway. | Развилка — без истории. Вода — `water`, глубокая (плавание). Духи реки над водой. |
| 9 | `euphrates_river_stair` | A long stair cut down through mud brick and rock into a dry riverbed beneath the monastery, water seeping down the walls. Composition: entrance at the left edge on a flat landing at about 35 percent; a broad stair descending to the right to a middle landing across the middle third at about 55 percent, with a votive niche in the wall holding a small oil lamp and a clay bowl, and beside it a bricked-up niche; a second stair descending from the middle landing to the floor in the right third along the bottom quarter, wet and dark; a dark arched passage at about 97 percent at the bottom. Below the first landing on the left, solid rock (no void). | Место отдыха — у киота ≈ [640, 360]. Тайник `note_novice_envy` — замурованная ниша рядом. Всадники и элита внизу, прикованный у кольца на средней площадке. |
| 10 | `euphrates_bound` | A wide low vault in the dry bed of the river under the monastery: the river runs above it, dark water dripping from a long crack in the vault. Four great pillars of stone banded with gold stand across the chamber, an iron ring and broken chain at the foot of each. One screen tall, a flat continuous floor along the bottom quarter across the whole width with shallow puddles; no ledges in the middle; two small low rock steps at the far left and far right at about 72 percent. The pillars at about 12, 44, 56 and 88 percent of the width. Cold pale blue-white light from the pillars' rings. A dark passage at about 97 percent, low on the floor. | Босс-арена. Якоря `bound_phases` — у колец столбов (≈ [150, 600], [565, 600], [715, 600], [1125, 600] в панели; пересчитать в пиксели комнаты после швов). Столбы — `FOCAL_RANGES` (100, 200), (520, 760), (1070, 1180). |

Промпт панели целиком (пример для `euphrates_altar_court`; остальные — так же, со своей строкой):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark fantasy
> pixel-art platformer, chapter VI "The Sixth Trumpet — the abbey on the Euphrates".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> darkness ONLY — not its architecture.
> **Primary request:** An open monastery court around a golden altar with four horns at its
> corners, standing on a stepped stone dais in the centre; the altar's gold is the brightest thing in
> the picture.
> **Composition:** flagstone floor along the bottom quarter, continuous from the left edge to the
> right edge; the dais in the middle third, its flat top at about 70 percent of the height from the
> top, two broad steps each side; a colonnade along the back with a flat-topped upper walk in the left
> third at about 45 percent and in the right third at about 45 percent, a stone stair up to each; the
> night sky over the court as an opening across the top fifth. Two iron wall rings on the colonnade's
> base. The altar between 44 and 58 percent of the width. A real dark doorway leading down at about 97
> percent across, standing on the floor.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

## 2. Враги — атласы 7×7

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk, attack,
attack_alt, special, hurt, death (`ART_DIRECTION.md`). Режет `tools/art/build_bestiary_assets.py`
(клетка — `GAME_CELLS`, полосы — `sprite` в `data/enemies/<id>.json` и `tree.json`). Роли:
**Image 1** — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7, поля вокруг тела);
**Image 2** — `tools/studio/refs/elian_style_idle.png` (масштаб, контур, темнота ТОЛЬКО). Каждый ряд
атаки показывает замах — 2–3 кадра до удара. **Цепей к прикованным не рисовать** (их рисует игра):
только ошейник / путы с коротким обрывком звена.

| id | Кто | Рост (герой 44) | material | Ряды — на что смотреть | Сейчас стоит |
|---|---|---|---|---|---|
| `flagellant` | Монах во власянице, сброшенной с плеч; спина в рубцах (тёмные полосы, не кровь); плеть-девятихвостка | 44–46 | cloth | idle — стоит, плеть висит; attack — **плеть уходит за плечо** (2 кадра), хлещет сбоку, хвосты веером; attack_alt — **плеть над головой** (3 кадра), бьёт сверху далеко; special — бьёт себя по спине (поза для подписи, не атака); death — на колени, лицом вниз | `cultist` тоном |
| `censer_monk` | Монах в глубоком капюшоне, кадило на цепочке, вьётся дым | 42–44 | cloth | attack — **кадило раскачивается** шире (2–3 кадра), выброс клуба вперёд (сам клуб рисует игра — `incense`); special — **кадило над головой**, дым стекает к ногам; death — кадило падает, дым гаснет | `preacher_acolyte` |
| `chained_penitent` | Босой кающийся, ошейник с обрывком звена, худой, бритая голова | 40–42 (сутулый) | flesh | idle — сидит на корточках; walk — тянется вперёд; attack — удар руками (замах виден); attack_alt — **присел, тело тянется вперёд, руки назад** (лунж; натяжение цепи покажет игра); special — **натяжение**: тело вперёд, ошейник тянет назад, лицо вверх (по кругу) | `possessed_villager` тоном |
| `horseman` | Всадник на тёмном коне; нагрудник тусклых цветов огня, гиацинта и серы (ржавый, сине-чёрный, серно-жёлтый), шлем, копьё | 64–70 (конь в холке ~40), длина ~90 | plate | idle — конь переступает; walk — шаг; attack — **копьё отведено назад** (2 кадра), укол; attack_alt — **конь на дыбы, копьё опускается** (3 кадра), бросок вперёд (лунж); death — конь падает на бок | `fallen_champion` |
| `river_wraith` | Дух реки: серо-зелёный полупрозрачный ком ила и тростника с лицом | 40 | spirit | attack — **тростник на нём встаёт дыбом, свет собирается** (2 кадра), брызги вперёд | `wraith` тоном (`extends`) — можно оставить |
| `fettered_angel` | Малый ангел: крылья связаны верёвкой, повязка на глазах, бледное тело, холодный свет | 46 (летает) | feather | idle — висит, крылья подрагивают в путах; attack — удар крылом (замах); attack_alt — **крылья натягивают путы, лицо светлеет** (3 кадра) — луч рисует игра; special — натяжение; death — путы падают, тело гаснет | `elder_wraith` тоном |
| `lion_horse` (элита) | Конь с львиной головой: грива как дым и огонь (оранжево-серный, не красный), из ноздрей дым, хвост — змея с головой | 56–60 в голове, длина ~96 | flesh | attack — **голова опущена, в пасти разгорается** (3 кадра), огонь вперёд (короткий, рисует игра — `beam`); attack_alt — **хвост-змея поднимается над спиной, разевает пасть** (2–3 кадра), бьёт **назад**; special — **бьёт копытом, опускает голову** (лунж); death — ложится, грива гаснет | `fallen_champion` тоном |
| `four_bound` (босс) | Ангел в цепях: высокий, крылья скованы железом, глаза завязаны тканью, руки в кандалах с обрывками звеньев; холодный свет из-под повязки. Один для всех четырёх — фазы различает тон и длина цепи | 60–64 | feather | idle — стоит, голова поднята; walk — тяжёлый шаг; attack — **цепь наматывается на кулак** (2 кадра), удар; attack_alt — **повязка светлеет, голова откинута** (3 кадра; и рывок, и луч); special — **натяжение / рывок всех цепей**: тело выгнуто, руки назад, крылья в железе раскрыты (по кругу — так стоят трое у столбов); hurt; death — опускается на колено, не падает (он побеждён, не убит) | `knight_of_ash` тоном |

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, кадр idle.

## 3. Люди — листы NPC и портреты

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет для диалогов — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png`.

| id | Кто | Поза idle | interact | Сейчас стоит |
|---|---|---|---|---|
| `saul` | Авва Саул: высокий, худой, седая борода, чёрная ряса, на поясе связка железных ключей; глаза запали — сорок лет без сна | стоит у стола, руки на посохе | снимает связку ключей с пояса | `matthew_v2` |
| `euphrates_reveller` | Пирующий горожанин: праздничная одежда из грубой ткани, венок, кубок в руке, сытое лицо | стоит, покачиваясь, поднимает кубок | протягивает подарок | `villager_v2` |
| `witness` | Свидетель, мёртвый: власяница, босые ноги, след верёвки на шее; **лежит** на мостовой (idle — один лежачий кадр, второй вариант — тот же, отражённый, другой тон бороды) | лежит | — (не говорит) | `severin_v2` (кадр `death`) |
| `malchus_far` | — | — | — | лист Малха (глава III) |
| (портрет) `saul` | Саул крупно, свет лампы снизу, ключи блестят | — | — | — |
| (портрет) `mighty_angel` | Лицо ангела с книжкой: огромное, светлое, спокойное, облака и радуга за головой (Откр. 10:1), тусклые цвета | — | — | — |
| (портрет) `reveller` | Пирующий крупно, венок, вино на подбородке | — | — | — |
| (портреты) `bound_hour`, `bound_day`, `bound_month`, `bound_year` | Тот же ангел в повязке, четыре раза: узел повязки, обрывок цепи и свет различаются; Час — моложе, Год — старше, повязка истёрта | — | — | `ophanim` тоном |

`SPEAKER_HORNS` портрета не имеет — у голоса нет тела.

## 4. Как рисовать

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`,
3–4 минуты на картинку, один запуск — одна картинка. Роли: панели — `assets/levels/graveyard_arches.png`
(улица и берег), для интерьеров — `assets/levels/seir_lighthouse_stair.png` / `seir_warehouses.png`;
атласы — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7) + `tools/studio/refs/elian_style_idle.png`
(масштаб, контур); портреты — `assets/portraits/enemies_atlas.png` / `people_atlas.png`.

Затем конвейер (всё через `patched()`, правки студии — `tools/art/studio_overrides.py`):

1. Панель → `tools/rooms/trace_panel.py <путь.png> <id>` → по нумерованной картинке выбрать
   настоящие уступы → таблица в `tools/rooms/painted_rooms.py` (полы, уступы, лестницы, `spawns`,
   `props` с кольцами `chain` и тайниками, `npcs`, `hazards` / `liquids`, `intro_cutscene` /
   `outro_cutscene`, `music`, `door`, `player`) → `tools/rooms/generate_rooms.py` (`check_reach`
   на генерации).
2. Колокольня — составная: `tools/rooms/composed_rooms.json` `"euphrates_bell_tower"` с
   `cells` [{`painting`: `panels/euphrates_bell_tower_top`, `col` 0, `row` 0}, {`painting`:
   `euphrates_bell_tower`, `col` 0, `row` 1}], координаты — в пикселях готовой комнаты (1280×1440),
   `"live": true`, когда пройдёт `check_reach`; правило фона `composed/euphrates_bell_tower`.
3. Огни: `assets/levels/<id>.lights.json` — лампады (тёплые, малые), алтарь (золото, ровный),
   кольца у столбов и скованных (холодные `#cfe6ff`, без мерцания).
4. `RoomLayers.FAR_WINDOWS`: небо над берегом (1), полоса неба (2), сад (4а), арки колокольни (6
   верх), небо двора (7). Пластины — `assets/levels/depth/<room>_backfill.png`.
5. Атлас → `enemy_atlases/<id>.png` + строка в `GAME_CELLS` → `build_bestiary_assets.py` (режет и
   пишет клетку в `tree.json`; валидатор сверяет полосы с клеткой).
6. Проп `assets/props/chain_ring.png` (3 кадра 32×32: кольцо с висящим звеном / искра / раскрытое) и
   снаряд `assets/sprites/projectiles/incense_flight_v3.png` (4 кадра 96×128: клуб ладанного дыма с
   тлеющей крупицей, тёплый серо-охристый) — промпт тот же блок стиля, на прозрачном фоне.
7. Стены тайников — `tools/art/make_secret_walls.py` вырезает из картины: `secret_wall_euphrates_gate`
   (балкон сторожки, 3), `_bell` (ниша у колоколов, 6 верх), `_stair` (ниша у киота, 9).
8. Кредит — строка в `assets/CREDITS.md` (Codex, дата, промпт в этом файле).

**Оживление** (`data/backdrops.json`, семья — новая `abbey`, пламя ламп — `flame`; ≤ 24 зоны):

| Комната | Зоны |
|---|---|
| `euphrates_bank` | `water` (брод), `sway` (тростник ×3), `glow` (лицо ангела, `#dfe8ff`, слабо, медленно), `haze` (над рекой), `stars` нет — буря |
| `euphrates_town` | `sway` (гирлянды и фонарики ×3), `glow` (столы, тёплый) |
| `euphrates_gate` | `glow` (лампы у ворот) |
| `euphrates_cloister` | `sway` (смоковница), `stars` (над садом), `haze` (сад) |
| `euphrates_scriptorium` | `haze` (пыль в свете ламп ×2) |
| `euphrates_refectory` | `glow` (печь, тёплый), `haze` (над столом) |
| `euphrates_bell_tower` | `sway` (верёвки колоколов ×3, колокола — медленно), `pulse` (кольца, холодный), `haze` |
| `euphrates_altar_court` | `glow` (алтарь — золото, ровно, `strength` 0,2), `pulse` (рога, медленно), `stars` |
| `euphrates_crypt_of_chains` | `sway` (висящие цепи ×4, амплитуда мала), `pulse` (трещины, холодный) |
| `euphrates_cistern` | `water` (вся вода), `falls` (капель с потолка ×2), `haze` |
| `euphrates_river_stair` | `falls` (сочится по стенам ×3), `glow` (киот) |
| `euphrates_bound` | `falls` (трещина свода), `water` (лужи), `pulse` (кольца столбов, холодный — с `life_rage` разгорается) |

**Передний план** (`tools/rooms/front_layers.json`, docs/DEPTH.md; тёмный ключ читается только на
светлом — проверить `depth_shot.gd`): берег — тростник; город — край стола с кувшином, гирлянда;
галерея — колонна аркады; скрипторий — край полки; трапезная — край стола и скамьи; колокольня —
верёвка колокола; двор — колонна; склеп — висящая цепь; цистерна — колонна из воды; русло — ничего
(арена читается вся).

## 5. Проверка перед pull request

- `make validate` (полосы против клеток, стиль `incense` анимирован, правила фона на каждую комнату,
  знаки в CJK-подмножестве).
- `reach_test.gd -- euphrates_<id>` на каждую комнату (кольца `chain` и тайники достижимы),
  `stairs_test.gd`, `void_fall_test.gd`, `exits_test.gd`, `smoke_test.gd` (ночь `euphrates`).
- `backdrop_life_test.gd` (зоны лежат на картине), `depth_test.gd`, `layers_test.gd`.
- Бестиарий: рост против героя (44), у каждой атаки виден замах; у прикованных и Четверых нет
  нарисованной цепи — только ошейник / кандалы.
- `make import` после смены картин, иначе игра рисует старую текстуру через новую клетку.
