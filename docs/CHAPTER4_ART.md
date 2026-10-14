# Глава IV — заказ картин

*Картины главы «Алчность» (docs/CHAPTER4.md): Тир, город, который откупился. Это заказ:
двенадцать панелей, атласы врагов, листы людей, портреты и несколько мелочей (лампа, монета,
пурпур), с промптами, по которым их рисует Codex CLI (`codex exec`, встроенная генерация) — или
художница в своём ChatGPT (навык `ashes-art`, `.claude/skills/ashes-art/SKILL.md`). У всего,
что ещё не нарисовано, есть заместитель.*

## Состояние

| Что | Статус | Что стоит пока |
|---|---|---|
| 12 панелей 1280×720 (`assets/levels/tyre_*.png`) | **5 из 12**: дамба, счётный дом, тёмный квартал, светлая пристань, красильни — комнаты собраны, `check_reach` держит | остальные семь (ворота, рынок ламп, ворота богача, подвалы, галеры, лестница дворца, трон) ждут Codex; до них ночь `tyre` не проходит валидатор |
| Атласы `tyre_guard`, `cutpurse`, `debt_wraith`, `dim_star`, `woe_eagle`, `tyre_treasurer`, `prince_of_tyre` | **не нарисовано** | `sprite.like` + `tint` чужих полос (§2, последний столбец) |
| `dye_drowned` | **не нужен атлас** — честно перекрашенный `drowned` (`#a070b8`) | — |
| Стрелки светлой пристани | **не нужен** — `ash_archer` главы I как есть | — |
| Портреты врагов (7) и людей (Закхей, Лидия) | **не нарисовано** | портрет ближайшего заместителя; Лазарь — `lazarus.png` главы II |
| Листы тел людей (`zacchaeus`, `lydia`, `lazarus_tyre`) | **не нарисовано**; резчик готов (`tools/art/build_people_sheets.py`) | `matthew_v2` (Закхей), `villager_v2` (Лидия), `severin_v2` (Лазарь) |
| Лампа (`tyre_lamp`: крюк, погасшая, горящая) | **есть** (`assets/props/tyre_lamp.png`) | — |
| Снаряд `coin` (`coin_flight_v3.png`) | **есть** — рисует `tools/art/make_coin_flight.py` | — |
| Тело жидкости `dye` (`body_dye.png`) | **не нарисовано** | `body_water.png` с цветами `dye` из `liquids.json` |
| Псы у ворот богача (`tyre_dogs`, декор) | **не нарисовано** | без них |
| Пластины глубины (`depth/<room>_backfill.png`), `FAR_WINDOWS`, передний план, стены тайников | **частично**: проёмов вдаль у пяти комнат нет (`FAR_WINDOWS` пуст), тайник счётного дома — кирпичная стена (`secret_wall_tyre_counting`) | остальные тайники — с панелями |

Порядок: панели (без них нет комнат) → лампа и монета (без них механики не видно) → атлас Князя
→ остальные атласы → листы людей → глубина и передний план.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: тёмный готический пиксель-арт, нарисованный, а не из
тайлов; ночь; читаемость прежде красоты; нижняя пятая часть тёмная и тихая. Что меняется в Тире
(CAMPAIGN §10):

- **Громкий цвет — золото ламп в чёрном.** Ночь Тира чернее, чем в Сеире: треть луны и звёзд
  погасла, и на небе это видно — луна с откушенным тёмным краем, звёзд меньше, чем должно быть,
  одна треть неба пустая. Всё тёплое на картине — купленный свет: бронзовые лампы на крюках и
  столбах, окна богатых домов, огонь под котлами красилен. Тёплого света без хозяина нет.
- **Бедные кварталы — без света.** Ни одного горящего окна, пустые крюки для ламп на стенах.
  Тёмный квартал рисуется почти одним силуэтом: читаются края уступов, дверные проёмы, бельё — но
  не цвет.
- **Пурпур красилен** — тёмный, винно-лиловый (`#3a1040`…`#9a5ab0`), не красный: красный остаётся
  за кровью и соблазном. Пурпур есть в двух местах: чаны и ткани красилен, мантии богатых (Князь,
  казначей). Больше ничего пурпурным не красить.
- **Материал** — тёсаный известняк (светлый, тёплый, крупные ровные блоки), кедр (тёмно-рыжие
  балки, резные двери), бронза (лампы, ворота, решётки, позеленевшая у моря). Город богатый и
  целый: ничего не разрушено, всё начищено — там, где светло.
- **Море** — чёрное, гладкое; в нём отражаются только лампы, луны почти нет.

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent stone sizes. A rich merchant city on an island at night, in a night darker
> than it should be: the moon has a dark bite taken out of its edge and a third of the sky has no
> stars. Dressed pale limestone in large even blocks, dark red-brown cedar beams and carved doors,
> bronze lamps, gates and grilles with green sea-patina. The ONLY warm light is bought light:
> bronze oil lamps on hooks and posts and the windows of the rich, gold in black. Poor streets
> have no light at all — dark silhouettes, readable edges. Where dye appears it is a dark murex
> purple, never red. Gentle contrast so enemies and hero remain legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. Entrance at the left edge; a real dark doorway or passage
> at the far right (about 97 percent across) for the game's exit gate. Every surface a person
> could stand on is drawn as a flat-topped ledge with a readable edge and a visible support —
> no floating platforms. Keep landmarks away from 35 percent and 65 percent of the width (the
> game widens the picture there). The bottom fifth stays dark and quiet. Opaque canvas, artwork
> to every edge. No characters, no people, no animals, no text, no letters, no numbers, no
> labels, no UI, no watermark, no border.

## 1. Панели комнат — 12 штук, 1280×720

Каждая — `assets/levels/<id>.png`, 16:9 (ChatGPT рисует 1536×1024 или 1792×1024 — студия
кадрирует; размер в промпт не писать). Все — в два экрана высотой (720 px картины на 360 px
экрана), кроме тронного зала: он **в один экран** — весь бой в нижней половине, наверху только
свод и окна. Высоты ниже — доля высоты панели **сверху**; «пол на 78 %» значит верх пола в 78 %
высоты от верхнего края. Генератор расширит картину до 1600 швами около 35 % и 65 % ширины
(`_quilt_band`) — ориентиры дальше от них или в `FOCAL_RANGES`.

Роли во всех промптах панелей: **Image 1** — игровой стиль: `assets/levels/graveyard_arches.png`
для улиц и открытых мест; для интерьеров (счётная палата, подвалы, лестница, тронный зал) —
`assets/levels/seir_lighthouse_stair.png` (масштаб камня, толщина уступов, темнота — ТОЛЬКО это).
**Image 2** — референс места, если она его выберет, иначе не прикладывать.

| # | id | Primary request + Composition | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `tyre_causeway` | A long stone causeway running across a black, glassy sea toward an island city whose walls and towers glitter with gold lamps far away on the right. **Floor:** the causeway deck is one continuous walkable floor along the bottom quarter (top at 76 %), with a low parapet; the sea shows only behind and below the parapet, never as a gap in the floor. **Ledges:** a flat-roofed stone toll booth in the middle third (its roof a flat ledge at 58 %, centred near 50 % of the width, steps up its left side); a second, smaller booth roof in the right third at 64 %. **Landmark:** a dead sycamore-fig tree in the left third (its trunk at 18–24 % of the width) with one thick, nearly horizontal branch at 50 % height. **Sky:** the upper half is open night sky, the moon with a dark bite out of its edge at about 80 % across; the left third of the sky has no stars. Bronze lamps burning on each booth. Exit: the dark archway of the city's outer gate at 97 %. | Закхей сидит на толстой ветке смоковницы (≈ 21 %, ветка 50 %). Три лампы будок горят — `lights.json`. Орлы над дорогой. |
| 2 | `tyre_gate` | Inside the island city's sea gate: a deep vaulted gate passage of pale dressed limestone, toll benches, a bronze portcullis raised high, scales for weighing goods. **Floor:** continuous along the bottom quarter (top at 78 %). **Ledges:** an upper gallery of the toll house, a flat stone walkway at 42 % across the left and middle thirds (from 4 % to 58 % of the width), reached by a straight stone stair rising from the floor in the left third (8–24 %); at the gallery's left end a small toll booth whose doorway is bricked up (the cache). **Openings:** none to the sky except a thin barred slot high in the vault. Two bronze lamps burning either side of the inner arch; two empty lamp hooks on the gallery wall. Exit: the inner arch into the city, dark, at 97 %. | Тайник `note_light_tariff` — замурованная будка в левом конце галереи. Две лампы на продажу — на крюках галереи (≈ 30 % и 52 %). |
| 3 | `tyre_lamp_market` | A covered market street of lamp-sellers: arcades of limestone columns, cedar awnings, stalls with rows of unlit bronze oil lamps hanging from hooks, coils of wick, oil jars. One stall in the middle (at 44–56 % of the width) holds a single lamp on its counter. **Floor:** continuous along the bottom quarter (top at 79 %). **Ledges:** an upper arcade walkway, flat, at 46 % across the right third (72–100 %), reached by a stone stair rising from the floor at 70–78 %; a flat cedar awning top at 56 % over the left stalls (6–28 %) with a visible beam under it. **Openings:** a strip of night sky between the awnings at the top, from 20 % to 80 % — few stars. Every lamp UNLIT. Exit: a dark arcade passage at 97 %. | Шесть ламп на продажу: одна на прилавке посередине (первая даром), остальные на крюках арок по обе стороны. Карманники в тени арок, духи под навесами. |
| 4 | `tyre_counting_house` | The great counting house: a tall hall with long ledger desks, counting boards, bronze balances, shelves of bound ledgers, an unlit bronze chandelier hanging high on chains. **Floor:** continuous along the bottom quarter (top at 80 %). **Ledges:** a mezzanine in the left third, flat, at 44 % (0–30 %), carried on cedar beams, reached by a ladder-steep stone stair in the left third; at its back an iron-barred strongroom with a bricked-up inner door (the cache); a clerks' gallery in the right third, flat, at 52 % (72–96 %), on stone corbels, reached from the floor by a stair at 74–84 %. **Openings:** two tall narrow windows high in the back wall (at 24 % and 78 % of the width) showing black sky. Exit: a dark doorway at 97 % on the floor. | Тайник `note_tyre_ledger` — за решёткой кладовой на левом антресоле. Казначей у столов посередине. Три лампы на продажу на колоннах. |
| 5а | `tyre_dark_quarter` | The poor quarter: narrow crooked lanes of rough limestone and mud-brick houses stacked up a slope, outside stairs, flat roof terraces, washing lines, empty iron lamp hooks on the walls — and not one lit window anywhere. Close, cramped, almost a silhouette. **Floor:** continuous along the bottom quarter (top at 80 %). **Ledges:** a flat roof terrace at 58 % in the left third (4–30 %), a higher one at 38 % in the middle third (40–60 %), a third at 52 % in the right third (72–94 %); each reached by an outside stone stair drawn on the wall, each terrace with a parapet edge. **Openings:** only a thin strip of starless sky at the very top. Four empty lamp hooks on walls at 12 %, 28 %, 50 % and 82 % of the width. Exit: a dark low passage under a house at 97 %. | Четыре пустых крюка — лампы (40 эссенции, или даром с `zacchaeus_down`). Тусклая звезда — над средней террасой. |
| 5б | `tyre_bright_quay` | The bright quay of the merchants: a broad limestone quay lined with bronze lamp posts, every one burning; bales of purple cloth and cedar logs; the gilded stern of a great merchant ship moored behind; the black harbour water mirrors the lamps. **Floor:** the quay is walkable along the bottom quarter (top at 77 %), with ONE gap of open water about 60 px wide at 72–77 % of the width, a mooring bollard at its left lip; the quay resumes at the same height after it. **Ledges:** a raised customs platform, flat-topped stone with steps on both ends, at 60 % across the middle third (40–60 %); the ship's flat rail-deck in the left third at 50 % (6–30 %), reached by a gangplank from the quay. **Sky:** open upper half, the bitten moon at about 20 %. Exit: a dark warehouse arch at 97 %. | Шесть ламп горят — `lights.json`. Стражи на платформе и на пристани, лучники на палубе. Падение в воду — смерть. |
| 6 | `tyre_rich_gate` | The street front of a rich man's house: a tall bronze-studded cedar gate (at 48–60 % of the width) at the top of six wide limestone steps, warm gold light behind tall upper windows; a stone bench at the foot of the steps (at 40 %); a household shrine niche in the wall at 75 % with a bronze lamp and a libation bowl. **Floor:** the street, continuous along the bottom quarter (top at 80 %); the six steps rise from it to a flat landing before the gate at 72 %. **Ledges:** a flat balcony with a stone balustrade at 40 % across the middle third (36–62 %), reached by a side stair in the left third (8–24 %); a garden wall top at 56 % in the right third (80–92 %). **Sky:** upper left, the bitten moon at 15 %, and an old fig tree's crown leaning over the garden wall. Exit: a dark side passage at 97 %. | Лазарь (с флагом) на скамье у ступеней, псы рядом. Место отдыха — ниша-алтарь (≈ 75 %). Две лампы у ворот горят. |
| 7 | `tyre_dyeworks` | The murex dye works on the waterfront: three large square stone vats sunk into the floor and filled with dark purple dye, drying racks hung with long lengths of purple cloth, heaps of pale murex shells, a brick furnace with a bronze cauldron in the left third (5–12 %) — its fire the only warm light — and steam. **Floor:** continuous along the bottom quarter (top at 79 %), except the three vats sunk into it at 15–27 %, 42–52 % and 75–87 % of the width (each about 30 px deep, purple liquid to the brim, stone lips flush with the floor — wadeable, not a drop). **Ledges:** a flat cedar walkway on posts at 55 % across the middle third (38–62 %), with ladders at both ends; a flat shed roof at 48 % in the right third (88–96 %). **Sky:** the upper third open, few stars, steam drifting. Exit: a dark loading door at 97 %. | Лидия у печи, левее первого чана (≈ 30 %). Утопленники пурпура — в чанах. Три лампы на продажу на столбах настила. |
| 8а | `tyre_vaults` | Cellars under the harbour embankment: brick barrel vaults, iron-bound strongboxes, stacked amphorae, a bronze grille door half open, water dripping. Low, close, very dark. **Floor:** continuous along the bottom quarter (top at 80 %). **Ledges:** a brick shelf-gallery, flat, at 46 % across the left and middle thirds (0–58 %), reached by a stone stair in the left third (10–26 %), its edge on brick piers; a second short shelf at 58 % in the right third (74–92 %). **Openings:** none — no sky. Four empty lamp hooks on piers at 15 %, 45 %, 55 % and 85 %. Exit: a dark stair-mouth at 97 %. | Четыре лампы по 25 (даром с `lydia_gave`). Казначей на верхней полке. |
| 8б | `tyre_galleys` | Across the decks of three moored war galleys lashed side by side in the harbour: oars shipped, masts with furled purple sails, bronze rams, rope. **Floor:** the decks, each flat: the first deck at 66 % (0–30 %), the second at 62 % (34–62 %), the third at 68 % (66–100 %); wide flat gangplanks join them at deck height; between the hulls, below the decks, black harbour water (a fall). **Ledges:** a flat stern castle on the middle galley at 44 % (44–58 %), with a ladder; a yard-arm is NOT a ledge — draw it high and thin. **Sky:** open upper half, rain, the palace on its rock far right with lit windows. Exit: a dark doorway in the quay wall at 97 % at third-deck height. | Три лампы по 20 на мачтах (даром с `lydia_gave`). Орлы над палубами, звезда над кормой. |
| 9 | `tyre_palace_stair` | The palace's grand stair: cedar and limestone flights climbing a tall hall, bronze balustrades, tall arched windows looking down over a dark city with only a few gold windows lit. Two screens tall. **Floor:** a short entrance floor at the bottom left (top at 82 %, 0–30 %). **Stair:** flight one rises from the floor to a broad flat landing at 60 % in the middle third (38–60 %); flight two rises to a landing at 40 % in the right third (70–84 %); flight three climbs on to a flat top landing at 22 % at 86–100 %, where the exit is. Every flight drawn as real steps with flat treads. On the middle landing: a bronze laver on lion's feet (rest point) and a small arched niche bricked up (the cache). **Openings:** two tall windows at 22 % and 78 % of the width (sky and the city below). Exit: a dark doorway on the top landing at 97 %. | Место отдыха — умывальник на средней площадке (≈ 50 %). Тайник `note_lamplighter_letter` — ниша там же. Четыре лампы по 25 на поворотах. |
| 10 | `tyre_throne` | The throne hall above the sea, **one screen tall**: a flat polished limestone floor along the bottom quarter, full width (top at 78 %), with no steps or gaps; a low flat-topped dais in the right third (80–96 %, its top 5 % above the floor) with an empty cedar throne inlaid with bronze; four bronze lamp stands on the floor (at 20 %, 45 %, 55 %, 80 %); two lamp hooks by the entrance on the left wall. Above the fight: columns and a great row of arched windows over the black sea along the upper half (FAR windows), the bitten moon in one of them. Nothing to stand on above 70 % except the dais. Exit: a dark doorway behind the dais at 97 %. | Князь перед престолом (≈ 75 %). Четыре лампы горят (его), две у входа — на продажу. |

Промпт панели целиком (пример для `tyre_dark_quarter`; остальные — так же, со своей строкой):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark
> fantasy pixel-art platformer, chapter IV "Tyre, the city that bought its light".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> darkness ONLY — not its architecture.
> **Primary request:** The poor quarter of a rich island city at night: narrow crooked lanes of
> rough limestone and mud-brick houses stacked up a slope, outside stairs, flat roof terraces,
> washing lines, empty iron lamp hooks on the walls — and not one lit window anywhere.
> **Composition:** a continuous walkable floor along the bottom quarter, its top at 80 percent of
> the height. Three flat roof terraces with parapet edges, each reached by an outside stone stair
> drawn on the wall: one at 58 percent height in the left third (from 4 to 30 percent of the
> width), one at 38 percent in the middle third (40 to 60 percent), one at 52 percent in the right
> third (72 to 94 percent). Only a thin strip of starless sky at the very top. Four empty iron
> lamp hooks on the walls at 12, 28, 50 and 82 percent of the width. The entrance is open at the
> left edge; a dark low passage under a house at the far right, about 97 percent across, is the
> exit. Nothing important at 35 or 65 percent of the width.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

## 2. Враги — атласы 7×7

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`, «Enemies»). Режет
`tools/art/build_bestiary_assets.py` (строка в `GAME_CELLS`, клетка — в
`data/enemy_archetypes/tree.json`). Один новый разговор на атлас. Роли: **Image 1** —
`assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7, поля вокруг фигуры); **Image 2** —
`tools/studio/refs/elian_style_idle.png` (масштаб, контур, темнота палитры ТОЛЬКО). **В каждом
ряду атаки виден замах — 2–3 кадра, где оружие отведено, прежде чем ударить.** Темнота не
отменяет замаха: игра подсветит его сама (CHAPTER4 §2), но рисунок должен читаться и без света.

| id | Кто | Рост (герой 44) | material | Ряды и на что смотреть | Пока стоит |
|---|---|---|---|---|---|
| `prince_of_tyre` (босс) | Князь Тира: человек средних лет, полный достоинства, в трёх тяжёлых пурпурных мантиях одна поверх другой, золотое шитьё; на голове — корона-лампа: бронзовый венец с толстым стеклянным фонарём, в нём бьётся маленькая белая звезда; в руке — длинный бронзовый скипетр с лампой в навершии | 58–62 (с короной) | gold | idle — стоит прямо, подбородок вверх, свет короны на лице снизу; walk — медленно, мантии волочатся; attack — скипетр отведён далеко за плечо (3 кадра замаха), удар сверху-вперёд; attack_alt — поднимает горсть монет над головой (2 кадра), бросает веером (монеты в полёте — игры); special — запрокидывает голову, корона разгорается добела (3 кадра, луч рисует игра); hurt; death — **опускается на колени**, корона скатывается с головы — не падает навзничь | `blind_preacher`, tint `#e0c090` |
| `tyre_guard` | Страж Тира: позолоченная чешуйчатая броня, высокий шлем с гребнем, круглый бронзовый щит с маяком Тира, алебарда | 50–52 | gold | idle — щит вперёд; attack — алебарда отведена назад для укола (2 кадра), колет; attack_alt — алебарда поднята над головой (3 кадра), рубит сверху; щит в обеих атаках **уходит в сторону** — видно, что он открыт | `fallen_guard`, tint `#e8c870`, как `shield_bearer` |
| `cutpurse` | Карманник: худой, босой, в тёмном рваном плаще с капюшоном, нож прижат к предплечью; глаза блестят | 40–42 | cloth | idle — пригнулся; walk — крадётся; attack — нож отведён к бедру (1–2 кадра), короткий удар; attack_alt — сжимается пружиной (2 кадра), прыжок вперёд; death — роняет кошель (монеты — частицы игры) | `cultist`, tint `#6a6070` |
| `debt_wraith` | Дух долга: полупрозрачный исхудалый должник, весь обмотан цепочками монет, вместо лица — пустой развязанный кошель; холодно-золотой | 40 (парит) | spirit | idle — висит, монеты покачиваются; attack — поднимает обе руки с горстью монет (2–3 кадра), выбрасывает; special не нужен (копия attack); death — монеты осыпаются, тело тает | `wraith`, tint `#e0c070` |
| `dim_star` | Тусклая звезда: колючий кристалл бело-золотого света в треснувшей бронзовой оправе с обрывком цепочки — будто сорван с витрины | 28–32 | spirit | idle — медленно вращается, мерцает; attack — разгорается добела (3 кадра нарастания) — **это и есть замах луча**; hurt — трещина вспыхивает; death — оправа ломается, свет гаснет точкой | `ophanim_seal`, tint `#fff0c0` |
| `woe_eagle` | Орёл горя: огромный тёмный орёл, перья цвета сажи, белые глаза, клюв раскрыт в крике | тело 30, размах 72 | feather | idle — парит, широкие взмахи; attack — **вскидывает крылья и кричит** (2–3 кадра, клюв открыт — это замах), бросок вниз-вперёд; death — падает, роняя перья | `raven`, `scale` 1,6 |
| `tyre_treasurer` (элита) | Казначей Тира: тучный, в пурпуре и золотых цепях, за спиной окованный сундук на ремнях, в руке тяжёлая счётная доска | 52–56 | gold | attack — доска поднята над плечом (2 кадра), бьёт; attack_alt — горсть монет над головой (2 кадра), бросок; special — **стучит кулаком в сундук за спиной** (созыв, 2 кадра замаха); death — садится на сундук | `gate_warden`, tint `#c8a0d0` |

`dye_drowned` атласа не получает: `"extends": "drowned"`, `sprite.like` drowned, tint `#a070b8`.

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, по кадру idle (Князь — лицо
крупно, свет короны снизу, звезда видна в стекле).

### Мелочи

| Что | Файл | Размер | На что смотреть |
|---|---|---|---|
| Лампа Тира | `assets/props/tyre_lamp.png` | кадры 24×40, 6 штук: пустой крюк; погасшая лампа; горящая (4 кадра пламени) | бронзовая масляная лампа на кованом крюке; свет — `GlowLight` игры, на рисунке только пламя |
| Монета | `assets/sprites/projectiles/coin_flight_v3.png` | 4 кадра 96×128, как прочие `*_flight_v3` | золотая монета ребром → плашмя → ребром (вращение), тонкий тёплый ореол |
| Пурпур | `assets/fx/liquids/body_dye.png` | как `body_water.png` | тёмно-лиловая муть с прожилками, без блеска — `tools/art/make_liquids.py` |
| Псы | `assets/decor/tyre_dogs.png` | 2 кадра 48×24 | два худых пса, лежат, один поднимает голову |

## 3. Люди — листы NPC и портреты

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png`.

| id | Кто | Поза idle | interact | Пока стоит |
|---|---|---|---|---|
| `zacchaeus` | Начальник мытарей: маленький, ниже Элиана на голову, в добротном тёмном кафтане мытаря, на поясе кошель и восковая табличка со стилом; лицо острое, внимательное | **сидит верхом на ветке**, болтает ногой, смотрит вниз | что-то быстро пишет на табличке | `matthew_v2` |
| `lydia` | Торговка пурпуром: крепкая женщина лет сорока, платок, кожаный фартук, руки по локоть тёмно-лиловые от краски, в руке длинное весло для чана | помешивает чан веслом | поднимает на весле кусок пурпурной ткани, смотрит на свет | `villager_v2` |
| `lazarus_tyre` | Лазарь главы II, **сидя** на ступенях с псами (тот же человек: худой, в лохмотьях, босой) | сидит, рука на голове пса | поднимает голову | `severin_v2` (или лист `lazarus` главы II, если он уже нарисован) |
| (портрет) `zacchaeus` | лицо снизу вверх — он на дереве, свет его табличного фонарика | — | — | — |
| (портрет) `lydia` | лицо в пару от чана, лиловые руки в кадре | — | — | — |

## 4. Как рисовать

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`,
по 3–4 минуты на картинку. Роли: панели — `assets/levels/graveyard_arches.png` (улицы) или
`assets/levels/seir_lighthouse_stair.png` (интерьеры); атласы — `assets/sprites/enemy_atlases/fallen_guard.png`
(раскладка 7×7) + `tools/studio/refs/elian_style_idle.png` (масштаб, контур); портреты —
`enemies_atlas.png` / `people_atlas.png`, как в главе II.

Конвейер (как Сеир):
1. Панель → `python3 tools/rooms/trace_panel.py <путь.png> <id>` (через `patched()`), по
   нумерованной накладке выбрать настоящие уступы; вход слева, выход справа.
2. Строка `"tyre_<id>": dict(...)` в `tools/rooms/painted_rooms.py` — полы, уступы, лестницы
   (`ramps`), враги, люди, пропы ламп и тайников, `dark`, `liquids` (чаны красильни:
   `("dye", x, y, w, h, {"painted": True})`), `void_kill_y` для воды гавани; `check_reach` при
   генерации доказывает дверь и каждого ходока.
3. `python3 tools/rooms/generate_rooms.py`; ориентиры у швов — в `FOCAL_RANGES` (луна дамбы
   ≈ 0,78–0,84; смоковница 0,16–0,26; ворота богача 0,46–0,62; печь красильни 0,03–0,13; престол
   0,78–0,98).
4. `<id>.lights.json` — на нарисованные огни: лампы будок и пристани, окна богатых, печь
   красильни, лампы престола. **Только горящие на картине**: пустые крюки света не дают, купленная
   лампа приносит свой `GlowLight` пропа.
5. `RoomLayers.FAR_WINDOWS` — проёмы в небо, которые скользят с камерой: небо дамбы, пристани,
   галер, ворот богача, красилен; окна лестницы и тронного зала. Пластины —
   `assets/levels/depth/<id>_backfill.png` (небо с откушенной луной, город вдали: золотые точки
   богатых, чёрное пятно бедных). У тёмного квартала, ворот города, рынка и подвалов — нет.
6. Атлас → `enemy_atlases/<id>.png` + строка `GAME_CELLS` → `python3 tools/art/build_bestiary_assets.py`.
7. Стены тайников — `tools/art/make_secret_walls.py` по трём местам: замурованная будка на
   галерее ворот (`tyre_gate`), решётка-кладовая на антресоли счётной палаты
   (`tyre_counting_house`), арочная ниша средней площадки (`tyre_palace_stair`); пропы
   `secret_wall_tyre_gate`, `secret_wall_tyre_counting`, `secret_wall_tyre_stair` с `reveals`.
8. Всё — через `patched()`; строка в `assets/CREDITS.md` на каждую картину (Codex, генерация,
   лицензия как у глав I–II).

### Правила `data/backdrops.json` (зоны «Оживления», ≤ 24 на комнату)

Общее: каждое нарисованное пламя мерцает само (`families` — лампы Тира попадут в `flame`).
Темнота комнаты (`dark`) не трогает зон: оживает то, что видно.

| Комната | Зоны |
|---|---|
| `tyre_causeway` | `water` (только блики ламп в море), `stars` (две трети неба; левая треть пуста), `glow` (будки), `haze` (дымка над водой) |
| `tyre_gate` | `glow` (лампы арки), `haze` (пыль в проходе) |
| `tyre_lamp_market` | `sway` (навесы, связки фитилей), `stars` (полоса неба), `haze` |
| `tyre_counting_house` | `sway` (люстра на цепях — медленно), `haze` (пыль в лучах окон) |
| `tyre_dark_quarter` | `sway` (бельё), `haze` — ни одного `glow` |
| `tyre_bright_quay` | `water` (гавань под лампами), `glow` (столбы), `sway` (паруса, флаги) |
| `tyre_rich_gate` | `glow` (окна дома, лампа ниши), `sway` (смоковница за стеной; `"tree"` — если подойдёт стиль `data/foliage.json`), `stars` |
| `tyre_dyeworks` | `sway` (полотна на рамах), `glow` (печь), `haze` (пар над чанами), `pulse` (угли под котлом) |
| `tyre_vaults` | `haze` (сырость), `falls` (капель со свода — тонко) |
| `tyre_galleys` | `water` (гавань между корпусами), `sway` (свёрнутые паруса, канаты), `glow` (окна дворца вдали) |
| `tyre_palace_stair` | `glow` (лампы на поворотах), `stars` (окна), `haze` |
| `tyre_throne` | `water` (море в окнах), `stars`, `glow` (лампы престола) — во второй фазе игра гасит их сама |

### Передний план (`tools/rooms/front_layers.json`, docs/DEPTH.md)

Ключ тёмный — только там, где за куском светлее (небо, дымка, пар); проверить `depth_shot.gd`.

| Комната | Кусок |
|---|---|
| `tyre_causeway` | край парапета, столб будки |
| `tyre_gate` | зубья поднятой решётки |
| `tyre_lamp_market` | висящие лампы и край навеса |
| `tyre_counting_house` | край конторки, чаша весов |
| `tyre_dark_quarter` | бельё на верёвке, угол стены |
| `tyre_bright_quay` | тюки, кнехт |
| `tyre_rich_gate` | ветви смоковницы |
| `tyre_dyeworks` | свисающее пурпурное полотно (на пару — читается) |
| `tyre_vaults` | арка свода, амфоры |
| `tyre_galleys` | снасти, вёсла |
| `tyre_palace_stair` | балясины перил |
| `tyre_throne` | колонны (только по краям кадра) |

## 5. Проверка перед pull request

- `make validate` (полосы против клеток, глифы, правила `backdrops.json` на каждую комнату).
- `reach_test.gd -- tyre_<id>`, `stairs_test.gd`, `void_fall_test.gd`, `exits_test.gd` на каждую
  новую комнату; `smoke_test.gd` проходит ночь `tyre`.
- `darkness_test.gd`: замах каждого врага главы в тёмной комнате светится.
- Глазами: `room_overview_shot.gd` (вся комната при `dark` 0 и при своём `dark`), `combat_fx_shot.gd`
  (смерть и снаряд каждого врага — монета вращается), `depth_shot.gd`, `backdrop_life_shot.gd`,
  `bestiary_screenshot.gd` (рост против героя).
- `python3 tools/check_generators.py`; `make import` перед тем, как верить картинке.
- Строки в `assets/CREDITS.md`.
