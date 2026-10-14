# Глава V — заказ картин

*Картины главы «Похоть и чревоугодие» (`docs/CHAPTER5.md`): Енгадди, виноградники у источника
под дымом кладезя. Ничего ещё не нарисовано. Этот файл — заказ: каждая панель, атлас, лист людей и
портрет с промптами, по которым их рисует Codex CLI (`codex exec`, встроенная генерация), а где
Codex слаб — художница (её ChatGPT, навык `ashes-art`). Порядок работы — как у Сеира
(`CHAPTER2_ART.md`).*

## Состояние

| Что | Статус | Что стоит пока |
|---|---|---|
| 12 панелей 1280×720 `assets/levels/engedi_*.png` | **нарисовано** (Codex) | — |
| Атласы `locust`, `locust_rider`, `feaster`, `vine_husk`, `pit_smoke`, `abaddon` | **нарисовано** (Codex; у всадника, пирующего и Аваддона ряды атак разведены по клеткам) | — |
| `locust_herald`, `swollen_feaster` | варианты (`extends` + `sprite.like` + тон) — своей картины **не нужно** | атлас всадника / пирующего |
| Портреты врагов (6) | **нарисовано** (`engedi_enemies_atlas.png`) | — |
| Листы людей `ahithophel`, `tirzah` | **не нарисовано** | `severin_v2` (Ахитофел), `villager_v2` (Фирца) |
| Портреты `ahithophel`, `tirzah`, `abaddon` (для диалога) | **нарисовано** (`engedi_people_atlas.png`; Аваддон — `abaddon_face`, в `speakers`) | — |
| Пропы: плоды (смоква, гроздь, гранат, блюдо), оборванные верёвки, ключ кладезя | **не нарисовано** | `barrel_apples` вместо плода, верёвки — без спрайта, ключ — `fx` искры |
| Пластины глубины `depth/engedi_*_backfill.png`, `FAR_WINDOWS` | **не нарисовано** | проёмы стоят |
| Передний план (`front_layers.json`) | **нет** | — |
| Замурованные стены у тайников (`reveals`) | **нет** | тайники стоят открыто |

Порядок: сначала панели 1, 4, 7, 10 (там сцены), потом атласы саранчи и Аваддона (без них глава
не играется), потом остальные панели, листы людей, пластины глубины, передний план, стены.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: тёмный готический пиксель-арт, нарисованный, а не из
тайлов; читаемость прежде красоты; нижняя пятая часть фона тёмная и тихая — там тела. Громкий
цвет главы (CAMPAIGN §10) — **густая зелень и золото венцов саранчи в буром дыму**. Что меняется
в Енгадди:

- **Самое красивое место игры — и целое.** Лоза, смоковницы, гранаты, кипарисы, мох у воды — всё
  живое, сочное, ни одного сухого листа, ни одной обгрызенной ветки. Саранча не трогает зелени
  (Откр. 9:4): красота сада — правда, а не обман. Мучаются только люди, и картина этого не
  показывает: на панелях людей нет.
- **Камень и земля.** Террасы из сухой кладки, тёплый песчаник, скальные уступы пустыни; у
  источника — **белый известняк**, гладкий, почти светящийся; давильня высечена в скале.
- **Свет: закат, которого нет.** Небо — бурый дым, тяжёлый, слоями; солнце за ним — **медное
  пятно**, без лучей, без диска с краем. Ночь главы — не синяя, а коричнево-медная мгла; холодный
  свет есть только у воды источника (бело-зелёный отсвет известняка). Тёплый — свечи и лампы пира,
  медный огонь из кладезя.
- **Золото — только у саранчи.** Венцы, пластины на груди всадников, нимб Аваддона. В пейзаже
  золото не повторять — пусть венцы читаются на зелени издалека.
- **Красный — за кровью и соблазном.** Здесь соблазн — плоды и вино: гранаты и вино давильни
  тёмно-винные, пурпурные, а не алые. Ничего больше красным.
- **Похоть — как желание иметь и съесть, со вкусом.** Изобилие, которое давит: столы, ломящиеся
  от блюд, гроздья, переполненные корзины, кувшины через край. Без наготы, без тел, без намёков
  на тело.
- **Кладезь.** Колодец бездны — круглая шахта в скале, края выложены древним камнем; из неё —
  столб бурого дыма и медный свет снизу. Ближе к кладезю зелень **не вянет** — просто кончается у
  камня.

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent stone sizes. The vineyards of En-gedi, a spring and waterfall in the
> desert, the most beautiful garden in the world and completely untouched: deep lush green vines,
> fig trees, pomegranates and cypresses, every leaf whole and healthy. Dry-stone terraces, warm
> sandstone, and white limestone near the spring. The sky is heavy layered brown smoke rising
> from a bottomless pit; the sun is only a dull copper smudge behind the smoke, no rays, no
> crisp disc. Night here is brown and copper, not blue; only the spring's water and limestone
> carry a cold pale green-white glow. Gold appears nowhere in the landscape. Pomegranates and
> wine are dark wine-purple, never bright red. Abundance that feels heavy: overfull baskets,
> laden branches, jugs brimming. Gentle contrast so enemies and hero remain legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. Entrance at the left edge, a real dark doorway or
> passage at the far right (about 97 percent across) for the game's exit gate. Every ledge a
> person could stand on is drawn as a flat-topped ledge with a readable edge and visible support
> below it, no floating platforms. Keep landmarks away from 35 percent and 65 percent of the
> width. The bottom fifth stays dark and quiet. Opaque canvas, artwork to every edge. No
> characters, no people, no animals, no insects, no text, no letters, no labels, no UI, no
> watermark, no border.

## 1. Панели комнат — 12 штук, 1280×720

Каждая — `assets/levels/<id>.png`, 16:9 (размер в промпт **не** писать: студия кадрирует). Высота
720 — два экрана игры (360): «вертикальная» комната (террасы, лестница в кладезь) использует всю
высоту уступами до самого верха; обычная держит ход в нижних двух третях; арена босса — **один
экран**: плоский пол и всё действие в нижней половине, выше — только небо и скалы без уступов.
Генератор расширит панель до 1600 швами (`_quilt_band`) около 35 % и 65 % ширины: ориентиры —
подальше от них или в `FOCAL_RANGES` (столбец «Фокус» ниже). Доли высоты — от верха панели.

Картинки-роли: **Image 1** — игровой стиль: `assets/levels/graveyard_arches.png` (масштаб камня,
толщина уступов, темнота — ТОЛЬКО это); для интерьеров (пир, соты, давильня, лестница) —
`assets/levels/seir_warehouses.png`. **Image 2** — референс места (фото Эйн-Геди, террасы
Иудейских гор), если она его выберет.

| # | id | Primary request + Composition | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `engedi_smoke_road` | A desert road climbing into the green of En-gedi under the smoke of the pit; one great healthy fig tree heavy with fruit in the LEFT third (trunk at about 20 percent across), sandstone boulders, the first vines on a dry-stone wall. **Floor:** a continuous walkable road along the bottom quarter (top of the road at about 76 percent of the height). **Ledges:** one flat-topped sandstone bank in the RIGHT third (from 72 to 90 percent across) at 62 percent of the height, its face a readable step. **Sky:** the upper half is open sky of layered brown smoke with the copper smudge of the sun at about 82 percent across, 22 percent down. **Exit:** a dark gap between two boulders at the far right, 97 percent across, at road level. | Ахитофел сидит под смоковницей (x ≈ 260); оборванные верёвки на земле под ней; 2 плода на смоковнице (низкие ветви, x ≈ 220, 300). Рой над банкой справа. Фокус: смоковница 180–340, солнце 990–1110. |
| 2 | `engedi_vineyard_gate` | The gate of a walled vineyard: a long dry-stone wall with an arched wooden gate standing open at the right, a square stone watchtower in the middle (Isaiah's vineyard tower) at 45–55 percent across, vines spilling over the wall. **Floor:** a continuous walkable path along the bottom quarter. **Ledges:** the flat coping of the wall, walkable, at 48 percent of the height, running across the left third (8–30 percent across); the watchtower's flat balcony at 34 percent of the height (44–56 percent across), with a ladder of stone steps on its left side up from the wall coping; a second wall coping at 52 percent in the right third (70–88 percent across). **Sky:** open brown smoke above the wall and tower. **Exit:** the dark arch of the gate passage at 97 percent across, at floor level. | Садовники на дорожке, всадник у ворот; 2 плода — грозди на стене (x ≈ 150, 980). Фокус: башня 560–720. |
| 3 | `engedi_terraces` | Vertical vine terraces climbing a mountainside, two screens tall: dry-stone retaining walls stepping up from the bottom left to the top right, each terrace thick with vines on trellis posts, a small stone vintner's hut with a bricked-up door on the third terrace. **Floor:** a continuous walkable floor along the bottom fifth (top at 82 percent of the height). **Ledges (flat-topped terrace walls, each with its wall face drawn below it):** 66 percent of the height across the left and middle thirds (0–55 percent across); 50 percent across the middle and right thirds (40–100 percent); 34 percent across the left and middle thirds (0–60 percent); 18 percent across the right two thirds (45–100 percent). Stone steps cut into each wall at its end, readable as steps. **Sky:** a strip of brown smoke at the very top left. **Exit:** a dark stone doorway in the cliff at the far right, 97 percent across, on the top terrace (18 percent). | Хижина виноградаря с замурованной дверью — на террасе 34 % (x ≈ 300) — тайник `note_vintner_day`; 3 плода — грозди на террасах 66 %, 50 %, 34 %. Рои на 50 % и 18 %, дым кладезя у верха. |
| 4 | `engedi_spring` | The spring of En-gedi: a slender waterfall falling from a cliff in the RIGHT-CENTRE (falls at 74–82 percent across) into a pool of clear pale water ringed by smooth white limestone, maidenhair ferns, a pomegranate tree, mossy stones. The limestone glows faintly cold green-white, the only cold light in the chapter. **Floor:** a continuous walkable limestone floor along the bottom quarter (top at 76 percent), with a shallow painted pool in its middle third (40–58 percent across) only knee deep. **Ledges:** a flat white limestone shelf at 56 percent of the height in the left third (6–28 percent across); a second shelf at 42 percent in the middle third (40–56 percent); a high ledge behind the falls at 30 percent (84–96 percent). **Rest point:** a carved limestone basin on the floor just right of the falls (about 84 percent across). **Sky:** a band of smoke and copper light above the cliff, upper fifth. **Exit:** a dark cave passage behind the falls at 97 percent across, at floor level. | Фирца сидит на известняке у чаши (x ≈ 1020); место отдыха — чаша (x ≈ 1080); двое пирующих у воды слева; 2 плода — гранаты (x ≈ 520). Фокус: водопад 940–1050. |
| 5а | `engedi_orchard` | An orchard of fig and pomegranate trees on two low terraces, branches laden, fallen fruit untouched on the grass, cypresses behind. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** a flat-topped dry-stone terrace at 58 percent of the height in the left third (4–30 percent across); a second at 44 percent in the middle and right thirds (42–60 percent across, then 72–92 percent across), each with a readable wall face. **Sky:** smoke and copper smudge visible between the crowns in the upper third. **Exit:** a dark gap in a hedge of cypress at 97 percent across. | 4 плода — на нижних ветвях (x ≈ 140, 470, 800, 1100); рои под кронами. Фокус: большая смоковница 760–900. |
| 5б | `engedi_arbor` | A long pergola walkway roofed with vines: stone columns carrying timber beams, heavy grape clusters hanging, a lower path under the pergola and a walk along the top of the beams. **Floor:** a continuous walkable path along the bottom quarter. **Ledges:** the flat top of the pergola beams at 42 percent of the height, walkable, from 10 to 45 percent across and from 55 to 92 percent across (a clear gap between); a stone stair of readable steps in the left third climbing from the floor to the beam walk. **Sky:** smoke above the vines, upper quarter. **Exit:** a dark archway at the end of the pergola at 97 percent across, floor level. | 2 плода — грозди (x ≈ 300, 1000) у нижней дорожки; садовники на обоих ярусах, дым кладезя над галереей. |
| 6 | `engedi_feast_hall` | An open-sided feast hall of sandstone columns and heavy hanging cloths, a very long table running across the middle third laden with dishes, figs, honeycombs, jugs of wine and lit candles; benches; abundance that feels heavy, no bodies. Between the columns the smoke and copper sky show. **Floor:** a continuous walkable stone floor along the bottom quarter; the table is background, not a ledge. **Ledges:** a flat gallery at 40 percent of the height in the left third (4–28 percent across) with a bricked-up pantry door on it, and another in the right third (72–94 percent across), each on corbels, reached by stone stairs at their inner ends. **Sky:** three tall openings between columns (about 15, 50 and 85 percent across) to the smoke. **Exit:** a dark doorway at 97 percent across, floor level. | Шестеро пирующих за столом (на полу у стола, x 420–860); 3 плода — блюда на краю стола (x ≈ 450, 640, 830); тайник `note_endless_menu` — замурованная кладовая на левой галерее. Свечи — `lights.json`. Фокус: середина стола 560–720. |
| 7 | `engedi_pit_rim` | The rim of the bottomless pit: the last vines end at ancient stones; beyond the walkable rim, in the background, a vast round shaft drops into copper light and a thick column of brown smoke rises out of it into the sky. A vineyard boundary stone carved with a grape cluster stands on the rim. **Floor:** a continuous walkable rock floor along the bottom quarter, the pit is BEHIND the floor, not a gap in it. **Ledges:** a flat rock shelf at 56 percent of the height in the left third (8–26 percent across); a flat shelf at 50 percent in the right third (74–90 percent across). **Sky:** the upper half: the smoke column in the centre-right and copper glow. **Exit:** a stair cut into the rock going down at the far right, its dark mouth at 97 percent across. | Место отдыха — межевой камень (x ≈ 380); Голос — без тела, глаза над колодцем (сцена, `presence`); всадники на полу, дым над колодцем. Фокус: столб дыма 820–980. |
| 8а | `engedi_hives` | A cliff face honeycombed with locust hives: huge brown-gold combs of hardened wax and chitin grown into the rock, dark cells, drips of dark honey, sandstone. **Floor:** a continuous walkable floor along the bottom quarter with two shallow painted honey pools (20–30 and 52–60 percent across). **Ledges:** flat-topped rock ledges at 60 percent of the height (left third, 6–26 percent), 46 percent (middle third, 40–58 percent) and 32 percent (right third, 72–92 percent), each with rock below. **Sky:** a narrow slot of smoke at the top. **Exit:** a dark tunnel at 97 percent across, floor level. | Рои у сот, глашатай на полу справа. Жидкость `honey` — на нарисованных лужах. |
| 8б | `engedi_wine_press` | A rock-cut wine press: an upper treading floor (a square stone vat) cut in the rock, a channel running down into a lower vat full of dark wine-purple must, baskets of grapes, a stone beam press with its weight-stone. **Floor:** a continuous walkable floor along the bottom quarter; the lower vat of wine is a painted pool in the right-middle (60–80 percent across), shallow. **Ledges:** the flat rim of the upper treading floor at 48 percent of the height in the middle third (38–58 percent across), with rock-cut steps up to it from the left; a flat rock shelf at 56 percent in the left third (6–24 percent). **Sky:** none, a dark rock ceiling with one shaft of smoky light. **Exit:** a dark passage at 97 percent across, floor level. | Садовники у чана, раздувшиеся у корзин. Жидкость `wine` — нижний чан. |
| 9 | `engedi_pit_stair` | Inside the pit: a stair cut into the wall of the shaft spiralling down, seen in cross-section, two screens tall; copper light rising from below, smoke drifting up; the stone is old and worn, one landing has a walled-up niche. Entrance high at the left, exit low at the right. **Floor:** a continuous walkable rock floor along the bottom fifth (top at 82 percent of the height). **Landings (flat-topped, with rock beneath):** 22 percent of the height at the left edge (0–24 percent across) — the entrance; 40 percent across the middle third (36–62 percent); 58 percent across the left third (8–30 percent); 70 percent across the right third (70–92 percent). Readable stone stair flights join each landing to the next and the last to the floor. **Sky:** the round mouth of the shaft at the very top, a disc of smoke and copper (centre, 40–60 percent across, top tenth). **Exit:** a dark tunnel at 97 percent across, at floor level. | Тайник `note_key_page` — замурованная ниша на площадке 40 % (x ≈ 640); рои и дым на площадках, всадник и глашатай на полу. |
| 10 | `engedi_abyss_mouth` | The mouth of the abyss, a boss arena one screen tall: a wide flat sandstone platform over the shaft; behind it the vast round pit dropping into copper fire, smoke rising in columns to a sky where the sun is a copper smudge; green vines still cling to the platform's edges, whole. **Floor:** a perfectly flat continuous walkable floor along the bottom third (top at 66 percent of the height) from edge to edge, no gaps, no ledges in the middle. **Ledges:** only two low flat stone steps at the far left (8–16 percent across, 60 percent of the height) and far right (84–92 percent across, 60 percent). **Sky:** the upper half open, smoke and copper. **Exit:** a dark doorway in the rock at 97 percent across, floor level. | Аваддон спускается в центр (x ≈ 640); ключ ложится у края (x ≈ 900). Фокус: столб дыма и медное пятно 560–720. |

Промпт панели целиком (пример для `engedi_spring`; остальные — так же, со своей строкой из
таблицы):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark
> fantasy pixel-art platformer, chapter V "En-gedi, the garden under the smoke".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> darkness ONLY — not its architecture, not its colours.
> **Primary request:** The spring of En-gedi: a slender waterfall falling from a cliff in the
> right-centre (falls at 74 to 82 percent across) into a pool of clear pale water ringed by smooth
> white limestone, maidenhair ferns, a pomegranate tree, mossy stones. The limestone glows faintly
> cold green-white, the only cold light in the scene.
> **Composition:** a continuous walkable white limestone floor along the bottom quarter (its top at
> 76 percent of the height), with a shallow painted pool only knee deep in its middle third (40 to
> 58 percent across). A flat-topped limestone shelf at 56 percent of the height in the left third
> (6 to 28 percent across); a second flat shelf at 42 percent in the middle third (40 to 56
> percent across); a high flat ledge behind the falls at 30 percent (84 to 96 percent across);
> every shelf has visible rock beneath it. A carved limestone basin stands on the floor just right
> of the falls, about 84 percent across. A band of smoke and copper light above the cliff in the
> upper fifth. A dark cave passage behind the falls at the far right, 97 percent across, at floor
> level, for the exit. Nothing important at 35 or 65 percent of the width.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

После картины: `tools/rooms/trace_panel.py assets/levels/<id>.png <id>`, выбрать настоящие уступы
по пронумерованной накладке, строка в `painted_rooms.py` (вход слева, выход справа; `check_reach`
доказывает дверь и каждого ходока), `FOCAL_RANGES`, `<id>.lights.json`, `FAR_WINDOWS`, правило в
`data/backdrops.json` (§4).

## 2. Враги — атласы 7×7

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`). Режет
`tools/art/build_bestiary_assets.py` (клетка и масштаб — `GAME_CELLS`, полосы — `sprite` в
`data/enemies/<id>.json` и `tree.json`). Один новый разговор на атлас. Роли: **Image 1** — атлас
`assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7, поля, один масштаб во всех
клетках); **Image 2** — `tools/studio/refs/elian_style_idle.png` (масштаб, контур, темнота палитры
ТОЛЬКО — не его броня и не меч); **Image 3** — её дизайн, если есть. **Каждый ряд атаки показывает
замах** (2–3 кадра подготовки до удара) — игра держит его по `windup`.

| id | Кто | Рост (герой — 44) | material | Ряды, на что смотреть | Пока стоит |
|---|---|---|---|---|---|
| `locust` | Саранча кладезя: тело с ладонь, крылья как у стрекозы, **золотой венчик**, крошечное человечье лицо, длинные тёмные волосы, хвост скорпиона | 10–12 (длина 14) | bone | idle — полёт на месте, крылья размыты; walk — полёт вперёд; attack — **подъём** (2 кадра: вверх, хвост поджат) и пике; attack_alt — то же сбоку; special — венчик вспыхивает; hurt; death — крылья ломаются, падает | `raven` (золото, 0,4) |
| `locust_rider` | Боевая саранча: тело как у коня, готового к бою, в железных пластинах; лицо мужчины, женские волосы, львиные зубы, **золотой венец**; крылья сложены вдоль спины, хвост скорпиона. Без седока | 40 (длина 70) | flesh | idle — переступает, крылья дрожат; walk — шаг; attack — **голова назад** и укус; attack_alt — **встаёт на дыбы**, крылья раскрыты (2–3 кадра), бросок; special — **хвост поднимается над спиной** и бьёт вперёд; death — падает на бок, венец катится | `fallen_champion` |
| `feaster` | Пирующий: богатая одежда, тесная, пояс расстёгнут; лицо без выражения, взгляд в блюдо; в руках блюдо. Idle — **сидя, ест** | сидя 30, стоя 44, широкий | flesh | idle — сидит, подносит ко рту; walk — тяжело, переваливаясь; attack — **поднимает блюдо обеими руками над головой** (3 кадра, долго) и бьёт вниз; hurt; death — оседает обратно, лицом в стол | `possessed_villager` |
| `vine_husk` | Садовник, одержимый садом: соломенная шляпа, рубаха, руки и шея обвиты зелёной лозой, глаза — темно, садовые ножницы с длинными лезвиями | 42 | flesh | idle — подстригает воздух; walk; attack — **ножницы над плечом раскрыты** (2 кадра), щелчок; attack_alt — **ножницы за спиной, лоза натянута** (3 кадра), длинный срез вперёд; death — лоза распускается, тело падает, ножницы остаются стоять | `cultist` |
| `pit_smoke` | Дым кладезя: столб бурого дыма с медным огнём внутри, в дыме на миг проступает лицо | 46 | spirit | idle — клубится; walk — дрейф; attack — **втягивается, огонь внутри разгорается** (3 кадра), выдох клуба; attack_alt — то же, два клуба; death — рассеивается, огонь гаснет последним | `wraith` (тон) |
| `abaddon` (босс) | **Аваддон, Губитель.** Высокий падший, почти ангел: прекрасное симметричное лицо, длинные волосы, медно-золотые крылья, доспех из пластин как у саранчи, длинное копьё, **нимб медного золота** за головой. В покое — ангел; неправильное — только в атаке | 70 (с крыльями — 100 в ширину) | gold | idle — парит, крылья медленно; walk — парит вперёд; attack — **копьё отведено за плечо, крылья раскрыты, наконечник вспыхивает** (3 кадра), бросок; attack_alt — **крылья вверх, перья светлеют** (2 кадра), взмах; special — **нимб раскрывается как пасть** (3 кадра: трещина, зубья света, раскрыт), свет копится (луч — игра); hurt; death — опускается на колено на воздухе, крылья падают на пол, нимб закрывается | `fallen_champion` ×1,4, медь |

`locust_herald` и `swollen_feaster` — варианты на этих полосах (`"extends"` + `sprite.like` +
тон: глашатай — золото `#f0c860`, крупнее; раздувшийся — бледнее `#e0d0b0`). Своей картины не
надо.

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, один кадр idle; Аваддону —
два: бестиарий (покой) и диалог (лицо, свет нимба снизу).

Пример промпта атласа (`locust_rider`):

> Use case: game sprite atlas. Image 1 is the layout reference: a 7 by 7 grid, one creature per
> cell, the same scale in every cell, room around it. Image 2 is the scale and outline reference
> ONLY. **Primary request:** a war locust from the pit, side view facing right: a body shaped like
> a horse prepared for battle, armoured in dark iron plates, the face of a man, long dark hair like
> a woman's, lion's teeth, a small crown like gold on its head, long insect wings folded along the
> back, a scorpion's tail. No rider. Rows top to bottom: idle (shifting its weight, wings
> trembling), walk, attack (head drawn back for two frames, then a bite), attack_alt (rearing up
> with wings spread for three frames, then a charge), special (the scorpion tail rising over the
> back for two frames, then a strike forward), hurt, death (falls on its side, the crown rolls).
> **Style:** carefully authored dark fantasy pixel art, crisp pixels, dark outline, iron and
> gold readable against deep green. **Constraints:** transparent background, no text, no grid
> lines drawn, nothing crossing into a neighbour's cell.

## 3. Люди — листы NPC и портреты

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет для диалогов — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png`.

| id | Кто | Поза idle | interact | Пока стоит |
|---|---|---|---|---|
| `ahithophel` | Старый советник: седая борода, богатая когда-то одежда, теперь пыльная; царский перстень; лицо усталое и умное. **Никакой верёвки на нём и в руках** | сидит под деревом, руки на коленях | поднимает голову, смотрит на собеседника | `severin_v2` |
| `ahithophel` (полоса `away`) | тот же, **сидит спиной** к зрителю-дереву, лицом к дороге (для ответа воли) | сидит | — | — |
| `tirzah` | Молодая женщина, простое платье и платок, босые ноги у воды; прямая, тихая; на коленях гранат, которого она не ест | сидит на известняке, смотрит на воду | оборачивается к Элиану | `villager_v2` |
| (портрет) `ahithophel` | крупно: борода, глаза, медный свет дыма сбоку | — | — | `matthew` |
| (портрет) `tirzah` | крупно: платок, профиль к воде, холодный отсвет источника снизу | — | — | `mara` |

Голос у края — без тела и без портрета: глаза в темноте (`presence`), как в главе I.

Пропы (одним листом, `assets/props/engedi_*.png`, 32×32 кадры): смоква, гроздь, гранат, блюдо с
плодами (по 2 кадра: висит / сорван — пусто), **оборванные верёвки на земле** (лежат, концы
растрёпаны; никакой петли, ничего висящего), ключ кладезя (медный, древний, длиной в предплечье).

## 4. Как рисовать

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`
— по одной картинке на вызов, 3–4 минуты; несколько ролей — несколько `-i`. Роли: панели —
`assets/levels/graveyard_arches.png` (для интерьеров — `assets/levels/seir_warehouses.png`);
атласы — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7) и
`tools/studio/refs/elian_style_idle.png` (масштаб, контур); портреты — с
`assets/portraits/enemies_atlas.png` / `people_atlas.png`.

Конвейер:

- панель → `tools/rooms/trace_panel.py <путь.png> <id>` → строка в `tools/rooms/painted_rooms.py`
  (в конец блока глав) → `tools/rooms/generate_rooms.py`; `FOCAL_RANGES` — из столбца «Фокус» §1;
- атлас → `assets/sprites/enemy_atlases/<id>.png` + строка в `GAME_CELLS` →
  `tools/art/build_bestiary_assets.py`; валидатор проверяет полосы против клеток и анимированный
  `projectile_style` у стрелков (`pit_smoke`, `abaddon_lance` — в `data/projectiles.json`);
- всё, что пишет картинку, — через `patched()` (правки студии);
- строка в `assets/CREDITS.md` на каждую картину (сгенерировано, промпт — этот файл);
- `make import`, потом `validate_data.gd`.

**Огни** (`<id>.lights.json`, `GlowLight` на нарисованном огне): пир — свечи стола и лампы
галерей; край, лестница, устье — медный свет из кладезя (широкий, слабый, `#e0a050`); соты —
тусклые медовые отсветы; давильня — луч сверху; дорога, виноградник, террасы, сад — без огней
(свет — дым и медное пятно, `glow`-зона); источник — холодный отсвет известняка (`#cfe8d8`,
слабый).

**`RoomLayers.FAR_WINDOWS`** — проёмы в небо, которые едут с камерой (пластины
`assets/levels/depth/<id>_backfill.png`): небо дороги, ворот, сада смоковниц, галереи лоз, края;
три проёма между колоннами пира; диск устья шахты на лестнице; небо над ареной. Террасы, соты,
давильня — без (небо — узкая щель в камне, пусть стоит).

**`data/backdrops.json`** — семья `garden` (новая: `flame` 0,5, `flame_floor` 0,6) для всех
`engedi_*`; зоны (≤ 24, в пикселях картины):

| Комната | Зоны |
|---|---|
| `engedi_smoke_road` | `haze` по небу (дым ползёт), `glow` на медном пятне (`#d08040`, 0,12, медленно), `sway` + `"tree": "oak"` на кроне смоковницы, `sway` на лозе стены |
| `engedi_vineyard_gate` | `sway` на лозе через стену (две), `haze` неба |
| `engedi_terraces` | `sway` на лозе каждой террасы (4), `haze` у верха |
| `engedi_spring` | `falls` на водопаде, `water` на чаше и луже (только светлая вода), `sway` на папоротниках, `sway` + `"tree": "willow"` на гранате, `glow` известняка (`#cfe8d8`, 0,08) |
| `engedi_orchard` | `sway` + `"tree": "oak"` на 3–4 кронах, `haze` в просветах |
| `engedi_arbor` | `sway` + `"tree": "ivy"` на лозе крыши (две), `sway` на гроздьях |
| `engedi_feast_hall` | `sway` на занавесях, `haze` в проёмах, пламя свечей — само (семья) |
| `engedi_pit_rim` | `haze` столба дыма (широко), `glow` колодца (`#e0a050`, 0,18), `pulse` на камне у края (слабо) |
| `engedi_hives` | `pulse` на сотах (медленно — что-то внутри), `glow` медовых капель |
| `engedi_wine_press` | `water` на чане (тёмное вино колышется), `haze` в луче |
| `engedi_pit_stair` | `glow` снизу (`#e0a050`), `haze` дыма вверх, `stars` — искры в шахте |
| `engedi_abyss_mouth` | `glow` шахты (сильно), `haze` столбов дыма (3), `pulse` колодца, `sway` на лозе у краёв |

**Передний план** (`tools/rooms/front_layers.json`, `docs/DEPTH.md`; вырезать из своей же картины
`tools/rooms/front.py`, тёмный ключ читается только на свету дыма — проверить `depth_shot.gd`):
ветвь смоковницы над дорогой (1); край каменной стены с лозой (2); листья лозы у края кадра снизу
на террасах (3); папоротник и камень у воды (4); стволы деревьев сада (5а); гроздь, свисающая с
балки (5б); две колонны пира (6); каменная губа края (7); край соты (8а); корзина у давильни (8б);
скальный выступ на лестнице (9). На арене (10) — ничего: бой.

**Замурованные стены** (`tools/art/make_secret_walls.py`, проп `secret_wall_engedi_*.json`,
`reveals` — сундук тайника): дверь хижины виноградаря на террасе 34 % (`engedi_terraces`,
`note_vintner_day`); кладовая на левой галерее пира (`engedi_feast_hall`, `note_endless_menu`);
ниша на площадке 40 % лестницы (`engedi_pit_stair`, `note_key_page`). Стену резать из той же
картины — кладка должна совпасть с нарисованной.

## 5. Проверка перед pull request

- `make validate` (полосы против клеток, тексты, глифы, правило оживления на каждую комнату).
- `python3 tools/check_generators.py` — генераторы пишут то, что закоммичено.
- `reach_test.gd -- engedi_<id>` на каждую новую комнату, `stairs_test.gd` (террасы, арбор,
  лестница в кладезь — каждый марш вверх и вниз), `void_fall_test.gd`, `exits_test.gd`.
- Бестиарий: рост против героя (саранча — с ладонь, всадник — по грудь коню, Аваддон — выше
  всех); каждый ряд атаки — с замахом.
- Глазами: `room_overview_shot.gd`, `layer_motion_shot.gd`, `backdrop_life_shot.gd`,
  `depth_shot.gd`, `combat_fx_shot.gd` (смерть и снаряд каждого).
- Сад цел: ни на одной панели нет сухого или обгрызенного листа; золото — только у саранчи;
  красного нет, кроме вина и гранатов (тёмных); на панелях нет людей.
