# Глава VII — что нарисовать

*Заказ картин главы «Гордыня» (docs/CHAPTER7.md): ничего ещё не нарисовано. Рисует Codex CLI
(`codex exec`, встроенная генерация картинок) по промптам ниже, потом обычный конвейер; что
Codex сделает слабо — заказ художнице (её ChatGPT, навык `ashes-art`). Последняя глава кампании:
кроме 12 панелей, здесь пять картин для сцен концовок — сад за вратами Эдема.*

## Состояние

| Что | Статус | Что стоит пока |
|---|---|---|
| 12 панелей 1280×720 (`assets/levels/hall_*.png`) | **не нарисовано** | ничего: комнат нет в игре, план — `drafts/chapter_7/rooms.json`; валидатор считает их «ждущими картин» |
| 5 картин концовок (`assets/cutscenes/ch7_*.png`) | **не нарисовано** | сцены концовок главы I (`elian_gallows_*`, `church_to_ashes`, `prolog_1_walk_a`) |
| Атласы `seraph`, `measuring_angel`, `register_scribe`, `cherub` + головы `cherub_heads` | **не нарисовано** | `ophanim` (серафим, тонирован), `fallen_guard` (мерщик), `cultist` (писец), `knight_of_ash` (Херувим) |
| `wheel`, `hail_spirit`, `archive_scribe` | **рисовать не нужно** — варианты (`extends` + `sprite.like` + tint): `ophanim_seal`, `wraith`, `register_scribe` | — |
| `mirror_elian`, `proud_mirror` | **рисовать не нужно** — кадры Элиана (`elian_frames.tres`) + tint + краевой свет шейдера меток | — |
| Портреты врагов (7) и людей (Енох, Люцифер, старец, Херувим) | **не нарисовано** | портреты `ophanim`, `matthew_v2`, `severin_v2` |
| Листы людей `elders`, `enoch`, `lucifer` | **не нарисовано** | `matthew_v2` (Енох), `severin_v2` (старцы), `stranger` (Люцифер) |
| Пластины глубины (`depth/<room>_backfill.png`), `FAR_WINDOWS` | **не нарисовано** | проёмы стоят неподвижно |
| Передний план (`front_layers.json`) | **не нарисовано** | нет |
| Мраморные панели тайников (`reveals`, 3) | **не нарисовано** | тайники стоят открыто |

Порядок: панели в порядке ночи (1, 5, 6, 10 первыми — там сцены), атлас Херувима, картины
концовок, листы людей, потом остальное.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: нарисовано, а не из тайлов; читаемость прежде красоты;
нижняя пятая часть фона тёмная и тихая — там тела. Глава VII — единственная, где почти нет ночи,
и этим страшна:

- **Свет.** Ровный, белый, без источника и **без теней**: ничто не отбрасывает тени, нет
  солнца, нет лучей. Воздух — молочно-золотой. Тень есть только у Люцифера (лист NPC, не
  панель). Молнии (7, 8а) — единственный резкий свет.
- **Громкий цвет** (CAMPAIGN §10): бело-золотое и стекло. Золото — в венцах, тростях, ободах,
  жилах мрамора; стекло — море стеклянное (полупрозрачный пол с отражением), светильники.
  Пламенный меч и огненные камни — **бело-оранжевые**, не красные. Красный в главе не занят
  ничем (кровь и соблазн).
- **Камень.** Белый мрамор с золотыми жилами, облако как камень (плотные кучевые глыбы с
  тёсаными гранями — на них стоят), ступени без конца вверх. Пол — тёмный полированный камень
  (чёрно-зелёный мрамор), в котором отражается светлое: так нижняя пятая часть остаётся тёмной
  без теней.
- **Порядок.** Симметрия, повтор, мерные деления: колонны через равный шаг, плиты пола с
  насечками мер, полки архива одинаковой высоты. Ни грязи, ни разрушения — только 7–8б: град,
  трещины от молний.
- **Ни трона, ни фигуры.** Ни одна панель не показывает престол, сидящего, руку или лицо в
  свете. Лестница уходит за верхний край; ковчег — под покровом; за вратами — сад.
- **Сад** (картины концовок): рассвет — первый в игре настоящий рассвет; росистая трава, старые
  деревья, низкий туман, тёплое розово-золотое небо. Красиво без иронии.

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent stone sizes. A heavenly hall of white marble veined with gold, stone made
> of dense cloud with cut faces, gold fittings, still glass. An even, sourceless, milky-gold
> light with NO cast shadows anywhere and no sun or light rays — calm and unsettling. Strict
> symmetry and measured repetition: columns at equal steps, floor slabs notched with
> measuring marks. The floor band is dark polished green-black marble that reflects the light
> above it, so the bottom fifth stays dark. Red appears nowhere. Gentle contrast so enemies and
> hero remain legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. Entrance at the left edge; a real dark doorway or
> passage at the far right (about 97 percent across) for the game's exit gate. Every ledge,
> balcony or stair a person could stand on is drawn flat-topped with a readable edge and is
> supported by architecture, no floating platforms. Keep the main landmarks away from 35
> percent and 65 percent of the width. No throne, no seated figure, no face or hand in the
> light. The bottom fifth stays dark and quiet. Opaque canvas, artwork to every edge. No
> characters, no people, no text, no letters, no labels, no UI, no watermark, no border.

## 1. Панели комнат — 12 штук, 1280×720

Каждая — `assets/levels/<id>.png`, 16:9 (Codex/ChatGPT рисует 1536×1024 или 1792×1024 —
кадрировать и масштабировать в студии; размер в промпт не писать). Генератор расширит её до 1600
швами на 35 % и 65 % (`_quilt_band`): ориентиры — подальше от них, иначе назвать в `FOCAL_RANGES`.
**Высота:** все комнаты — один экран, как Сеир (720); «вертикальные» (1, 8а) поднимают уступы до
верхней четверти. Арена босса (10) — один экран, ровный пол во всю ширину. Если лестнице старцев
захочется второго экрана — это составная комната (`composed_rooms.json`, сетка 1×2) и 13-я
картина `hall_elders_stair_top`; по умолчанию — нет.

Роли во всех промптах панелей: **Image 1** — `assets/levels/seir_lighthouse.png` (интерьер:
масштаб камня, толщина уступов — ТОЛЬКО это, не маяк) или `assets/levels/graveyard_arches.png`
для открытых комнат (2, 8б, 9, 10). **Image 2** — её референс места, если выбран.

| # | id | Primary request + Composition | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `hall_elders_stair` | A vast white marble staircase climbing from lower left toward the top edge, its top lost beyond the frame; on both sides of the stair, rows of empty white-and-gold thrones on stepped terraces, golden crowns lying scattered on the steps. **Floor:** a continuous walkable floor along the bottom quarter across the whole width. **Ledges:** a broad landing in the middle third at about 55 percent of the height; a second landing in the right third at about 30 percent; throne terraces as flat-topped steps between them; the stair itself drawn as flat treads. A small square marble wall panel with a carved crown, set into the middle landing's back wall (a hidden niche). **Openings:** two tall arched windows of milky sky in the upper left third. Exit: a dark arched passage at the far right on the floor level. | старцы (6 фигур на престолах вдоль лестницы — лист NPC; остальные престолы пусты); колёса и мерщик на правой площадке; тайник `note_crown` за панелью на средней площадке |
| 2 | `hall_outer_court` | An open outer court under a white sourceless sky, paved, without measuring marks — the only unmeasured stone in the hall; low cloud-stone parapets; in the background, a painted crowd of tiny kneeling and standing people of all nations, grey and indistinct, far behind a colonnade. On the right, the tall gilded door of the inner court with a niche beside it. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** a cloud-stone parapet in the left third at about 60 percent of the height; a raised paved terrace in the middle-right at about 45 percent, reached by three flat steps. **Openings:** the whole upper half is open sky over the colonnade. Exit: the dark doorway of the inner court at about 97 percent across. | серафим в небе, колёса над террасой; тайник `note_court_tally` в нише у двери (≈ 90 %) |
| 3 | `hall_measured_temple` | Inside the measured temple: a long nave of white columns at exactly equal steps, every floor slab notched with gold measuring marks, a golden measuring reed laid along a ledge, a square altar of gold in the middle distance (empty, no fire). **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** a gallery between columns in the left third at about 50 percent; a gallery in the right third at about 50 percent; a narrow cornice over the altar at about 35 percent in the middle third (keep the altar centred near 50 percent, clear of the seams). **Openings:** high clerestory windows of milky sky in the top fifth. Exit: a dark doorway at the far right. | три мерщика на полу и галереях, писец на правой галерее |
| 4а | `hall_gallery_of_lamps` | A high gallery with seven great golden lampstands burning with still white-gold flames, set at equal steps along the back wall; an airy space with cloud-stone walkways between them. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** cloud-stone walkways at about 60 percent (left third) and 40 percent (right third), a short bridge in the middle third at about 50 percent; flat tops. Lamps between 10 and 30 percent and 70 and 90 percent of the width (none on the seams). **Openings:** none to the sky — a vaulted gold ceiling. Exit: a dark passage at the far right. | серафимы в воздухе, писцы на мостках |
| 4б | `hall_sea_of_glass` | A floor that is a sea of glass like crystal: a wide, perfectly still transparent surface reflecting the white hall above, faint gold veins of fire under the glass; thin marble islands and a low balustrade. **Floor:** the glass itself is a continuous walkable floor along the bottom quarter, drawn flat with a crisp top edge. **Ledges:** two low marble islands with flat tops at about 65 percent of the height, in the left and right thirds; a balustrade walk at about 45 percent in the middle third. **Openings:** an open sky arch across the top third. Exit: a dark arch at the far right. | отражения встают из пола: 300, 700, 1050; гордое отражение у выхода (≈ 1150) |
| 5 | `hall_archive` | The archive: shelves of scrolls from floor to the top edge in equal bays, ladders, a reading lectern with a single burning lamp under an arch in the right half, long writing desks with bent scribes' empty stools. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** a library gallery running the left and middle thirds at about 45 percent; an upper gallery in the right third at about 25 percent, reached by a ladder-stair drawn as flat steps; one shelf bay on the upper gallery visibly loose (a hidden cache). **Openings:** none to the sky; a round oculus of milky light in the ceiling, middle third. Exit: a dark doorway at the far right. | Енох сидит у аналоя (≈ 820); место отдыха — аналой; три писца архива за столами; тайник `note_register` за полкой на верхней галерее |
| 6 | `hall_stones_of_fire` | A causeway of large flat stones glowing white-orange from within, set in a dark marble floor with thin molten seams between them; the hall around is empty and bright and shadowless; a single far stone on the right is larger, like a plinth. **Floor:** the stones form a continuous walkable floor along the bottom quarter; the molten seams between them are narrow (hazards), never wider than a hero's stride. **Ledges:** two raised stones in the left and middle thirds at about 62 percent; the plinth stone in the right third at about 55 percent. **Openings:** a high open sky in the top third. Exit: a dark passage at the far right beyond the plinth. | Люцифер на камне-постаменте (≈ 1000); врагов нет; огонь камней — `lights.json`, `lava`-зоны |
| 7 | `hall_ark_sanctum` | The heavenly temple opened: a great curtain drawn aside in the far middle, and in the even light stands the ark of the covenant under a heavy blue-and-gold covering cloth — covered, nothing on it, nothing above it, no figure, no wings, no throne. Lightning in high windows, hailstones on a cornice. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** side galleries at about 50 percent in the left and right thirds; a cornice at about 30 percent in the left third. The ark stands on the floor at about 50 percent of the width, slightly lifted on three flat steps (name it in FOCAL_RANGES). **Openings:** tall windows of storm-lit sky in the top third, left and right. Exit: a dark doorway at the far right. | серафимы над галереями, мерщик и колесо на полу; ковчег — ориентир, не трогают |
| 8а | `hall_thunders` | A tall storm tower of cloud-stone and marble: lightning outside the open arches, cracked gold fittings, vertical climb. **Floor:** a walkable floor along the bottom quarter in the left half; in the right half the floor continues one step lower. **Ledges:** a staircase of flat cloud-stone ledges zigzagging up: left third at 65 percent, middle third at 48 percent, right third at 32 percent, middle third again at 20 percent; each supported by a buttress. **Openings:** large open arches of black storm sky with lightning in the left and right thirds. Exit: a dark passage at the far right on the floor level. | колёса и серафим на уступах, гордое отражение наверху (≈ 640, 20 %) |
| 8б | `hall_hail_gallery` | An open gallery along the outside of the hall: a long marble walk with a low balustrade, great hailstones lying on it and bouncing, a storm sky beyond, clouds below the walk. **Floor:** the gallery walk is a continuous walkable floor along the bottom quarter; it is solid the whole way (no fall). **Ledges:** two roofed bays with flat roofs at about 55 percent in the left and right thirds; a broken balustrade step in the middle at about 70 percent. **Openings:** the whole upper half is storm sky. Exit: a dark doorway back into the hall at the far right. | духи града в небе, мерщик на полу |
| 9 | `hall_flaming_way` | The way of the tree of life: a long path of white stone between two low walls of standing white-orange flame, ending at the right in a dark passage; on the far left a stone basin where a clear spring begins and runs as a thin stream along the path. **Floor:** a continuous walkable floor along the bottom quarter. **Ledges:** a raised stone terrace in the left third at about 60 percent; a flat-topped flame-wall coping in the middle-right at about 45 percent. **Openings:** an open dawn-tinted sky in the top third. Exit: a dark passage at the far right. | место отдыха — чаша истока (≈ 120); мерщики, отражения, серафим |
| 10 | `hall_eden_gate` | The gate of Eden: two tall closed gates set in a living hedge of white-orange flame at the right half, light leaking through the seam between the gates; beyond the hedge, the tops of dark garden trees. A wide flat marble threshold. **Floor:** one flat walkable floor across the whole width along the bottom quarter, for a boss fight; one screen tall. **Ledges:** two low flat marble steps at about 70 percent in the left and right thirds, no others. **Openings:** an open sky of first dawn in the top third. Exit: the seam between the gates, at about 92–97 percent across (the door overlays it). | Херувим перед вратами (≈ 900); выход — створки |

### 1б. Картины концовок — 5 штук, 1280×720 (`assets/cutscenes/`)

Не уровни — картины сцен (`panel`); полы и уступы не нужны, но каждой нужно правило в
`data/backdrops.json` (валидатор). Стиль — тот же пиксель, но **рассвет**: тёплое
розово-золотое небо, роса, туман у земли; нижняя пятая часть тёмная.

| id | Primary request |
|---|---|
| `ch7_garden_dawn` | Behind the opened gate of Eden: a garden at first dawn, dewy grass, old dark trees, low mist, a stream; at the centre an old tree with spreading branches. No throne, no figure, no light rays from above — only dawn. The opened gate stands at the left edge. |
| `ch7_end_heaven` | The same garden in perfect order, trimmed and still; under the old tree a small child sits drawing a sun on a flat stone with a stub of charcoal; a tall calm robed messenger kneels beside the child with one hand reaching for the charcoal. The messenger's face is hidden by the hood. |
| `ch7_end_abyss` | The garden wall broken open, the gates flung wide, a flaming sword lying unlit in the grass; a small child draws a big sun on the garden wall with charcoal, alone; far beyond the wall, thin smoke on the horizon. |
| `ch7_end_man` | Seen from the garden gate: a lone figure in a grey cloak walking away down a slope toward a plain where people begin their morning — small fields, a few roofs, a cart; the sky above is empty and pale, nothing in it. |
| `ch7_end_fourth` | In the middle of the dawn garden, the old tree; from one branch hang three ropes braided together into a single noose, empty and still. Dew on the grass, mist. Quiet, not horrific. |

Пример промпта панели целиком (`hall_archive`; остальные — так же, своей строкой):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark
> fantasy pixel-art platformer, chapter VII "The Hall of Heaven".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> pixel density ONLY — not its architecture, not its night palette.
> **Primary request:** The archive of the hall of heaven: shelves of scrolls from the floor to the
> top edge in equal bays, ladders, a reading lectern with a single burning lamp under an arch in
> the right half, long writing desks with empty stools.
> **Composition:** a continuous walkable floor along the bottom quarter across the whole width; a
> library gallery with a flat top running across the left and middle thirds at about 45 percent
> of the height; an upper gallery in the right third at about 25 percent, reached by a stair of
> flat steps; one shelf bay on the upper gallery visibly loose; a round oculus of milky light in
> the ceiling in the middle third; the lectern near 64 percent of the width is fine but keep
> other landmarks off 35 and 65 percent; the entrance open at the left edge and a real dark
> doorway at the far right, about 97 percent across.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

## 2. Враги — атласы 7×7

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`, «Enemies»). Каждый ряд атаки —
**сначала замах** (2–3 кадра, читаемых силуэтом), потом удар, потом возврат. Роли:
**Image 1** — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7);
**Image 2** — `tools/studio/refs/elian_style_idle.png` (масштаб, контур, плотность — не броня).
Клетку задаёт `GAME_CELLS` в `build_bestiary_assets.py`, полосы — `sprite` в `data/enemies/<id>.json`.

| id | Кто | Рост (герой 44) | material | Ряды и на что смотреть | Сейчас стоит |
|---|---|---|---|---|---|
| `seraph` | Серафим: шесть горящих бело-золотых крыльев, двумя закрыто лицо, двумя ноги; тела почти не видно | 46–50 (с крыльями 70 в ширину) | feather | idle — парит, крылья мерно; attack — **замах**: шесть крыльев раскрываются веером, в середине копится свет (3 кадра), луч рисует игра; attack_alt — крылья смыкаются коконом (2 кадра), вспышка кругом; special — повтор attack; death — крылья гаснут по одному | `ophanim` (тонирован) |
| `measuring_angel` | Ангел-мерщик: высокий, худой, белые одежды с золотой каймой, лицо спокойное и пустое, золотая трость выше его роста | 54–58 | gold | attack — **трость отводится назад горизонтально** (3 кадра), удар плашмя; attack_alt — трость ставится к полу вертикально, «отмер» (2 кадра), выпад вперёд; special — стоит, трость по полу (меряет); death — опускается на колени, трость падает ровно | `fallen_guard` |
| `register_scribe` | Писец реестра: согбенный, в белом, перо за ухом, раскрытый свиток в руках; вокруг кружат 2–3 листа | 40–42 | cloth | attack — **свиток раскрывается вверх** (2–3 кадра), листы срываются; attack_alt — толчок свитком (замах назад виден); special — пишет, склонившись (поза ждущего писца архива); death — листы осыпаются, он садится | `cultist` |
| `cherub` (босс) | Херувим: четыре крыла (два подняты, два закрывают тело), человеческие руки под крыльями, ноги прямые с копытами тельца (Иез. 1:7), бронза и золото; голова — **отдельно** (ниже); меч в руке — бело-оранжевое пламя | 76–84 | gold | idle — меч медленно обращается в руке; walk — тяжёлый шаг; attack — **круговой взмах**: меч поднят над головой, клинок белеет (3 кадра), оборот в обе стороны, возврат; attack_alt — укол / прыжок (отвод к бедру, 2 кадра); special — **поворот лица** (тело выпрямляется, крылья раскрыты, 7 кадров — под голову) и град (удар копытом); hurt; death — опускается на колено, меч опущен остриём в пол, крылья сложены | `knight_of_ash` |
| `cherub_heads` | Головы Херувима: человек, лев, вол, орёл — **4 ряда × 7**: idle 4 кадра + attack 3 кадра (рык льва, взгляд орла разгорается) | голова ≈ 20 | — | одна точка крепления (`head_at`) во всех рядах; профиль вправо; без нимба | — |

Варианты без новой картинки (`extends` + `sprite.like` + `tint`): `wheel` — `ophanim_seal`
(у него нет ряда атаки: замах читается по свету обода, `telegraph_fx` glow; если не читается —
дорисовать полосу attack 48×48: обод сжимается и вспыхивает), `hail_spirit` — `wraith` (`#e8f0ff`),
`archive_scribe` — `register_scribe`. Отражения — кадры Элиана.

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, кадр idle: `seraph`,
`measuring_angel`, `register_scribe`, `wheel` (крупно обод с глазами), `hail_spirit`,
`mirror_elian` (лицо Элиана в стекле, бледное золото, светящийся край), `proud_mirror` (то же,
золото, взгляд прямо), `cherub` (четыре лица в одном кадре: человек в фас, лев и вол в профиль по
сторонам, орёл над — Иез. 1:10).

## 3. Люди — листы NPC и портреты

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли: **Image 1** — её дизайн, **Image 2** —
`tools/studio/refs/elian_style_idle.png`.

| id | Кто | idle | interact / special | Сейчас стоит |
|---|---|---|---|---|
| `elders` | Старец: седой, в белых одеждах, золотой венец, сидит на престоле (престол — на панели, не на листе) | сидит прямо, венец на голове | interact — снимает венец и бросает вверх; четвёртая полоса `special` — падает ниц (3 кадра) и встаёт | `severin_v2` |
| `enoch` | Енох: старик в простой некрашеной одежде, без венца, перо за ухом, сидит у аналоя, пальцы в чернилах | сидит, пишет | поднимает голову, перо замирает | `matthew_v2` |
| `lucifer` | Люцифер: почти прекрасный, симметричный, светлая кожа, сложенные белые крылья с едва тёмными кромками, без нимба, простая светлая одежда; **под ним лежит тень** — единственная в главе, нарисована на каждом кадре | стоит неподвижно, руки опущены | поворачивает голову к герою; уход — тень остаётся на кадр дольше тела | `stranger` |
| (портрет) `elders` | Старец крупно: венец в руках | — | — | — |
| (портрет) `enoch` | Енох крупно, свет лампы снизу, чернила на пальцах | — | — | — |
| (портрет) `lucifer` | Лицо — спокойное, чуть печальное; тень от него падает в кадр | — | — | — |

Голоса (`SPEAKER_VOICES`) и ковчег портретов не имеют — никогда.

## 4. Как рисовать

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`,
3–4 минуты на картинку, папка — в scratchpad, не в репозитории. Роли: панели — `seir_lighthouse.png`
(интерьеры) или `graveyard_arches.png` (открытые); атласы — `enemy_atlases/fallen_guard.png` +
`tools/studio/refs/elian_style_idle.png` (второй `-i`); портреты — `enemies_atlas.png` /
`people_atlas.png`.

Затем:
1. Панель → `tools/rooms/trace_panel.py <путь.png> <id>` → по нумерованной картинке выбрать
   настоящие уступы → строка `hall_<id>` в `painted_rooms.py` (полы, уступы, лестницы, враги,
   люди, тайники, `hazards` у 6) → `generate_rooms.py` (`check_reach` на генерации).
2. Атлас → `assets/sprites/enemy_atlases/<id>.png` + строка в `GAME_CELLS` →
   `build_bestiary_assets.py` (режет целые фигуры; клетка — в `tree.json`). Головы Херувима —
   своя запись с `head_at`.
3. Все выходы — через `patched()` (правки студии); строка в `assets/CREDITS.md` на каждую картину
   («generated with Codex CLI image generation, project-owned»).
4. `assets/levels/<id>.lights.json` — на нарисованные огни (там, где они есть: светильники 4а,
   лампа 5, камни 6, свет ковчега 7, огонь пути 9, щель врат и изгородь 10). Ровный свет — не
   лампы: `Ambient` комнаты светлее обычного (`#e8e4dc`), без `GlowLight` по стенам.
5. `RoomLayers.FAR_WINDOWS` и пластины `depth/<room>_backfill.png`:

| Комната | Проёмы в небо (скользят) | Неподвижные |
|---|---|---|
| `hall_elders_stair` | два арочных окна слева | — |
| `hall_outer_court` | всё небо над колоннадой | — |
| `hall_measured_temple` | верхние окна | — |
| `hall_gallery_of_lamps` | — | — (свод) |
| `hall_sea_of_glass` | арка неба | отражение в стекле — **неподвижно** |
| `hall_archive` | — | окулюс (свет, не вид) |
| `hall_stones_of_fire` | верхнее небо | — |
| `hall_ark_sanctum` | окна с молниями слева и справа | — |
| `hall_thunders` | обе арки бури | — |
| `hall_hail_gallery` | всё верхнее небо | — |
| `hall_flaming_way` | небо рассвета | — |
| `hall_eden_gate` | небо рассвета над изгородью | кроны сада за изгородью |

6. `data/backdrops.json` — правило на каждую комнату (семья `hall`: `flame` — для белых огней
   тоже, `flame_floor`), зоны:

| Комната | Зоны |
|---|---|
| `hall_elders_stair` | `glow` (венцы на ступенях), `haze` (верх лестницы), `stars` (искры в окнах) |
| `hall_outer_court` | `haze` (толпа народов), `sway` (знамёна на колоннаде) |
| `hall_measured_temple` | `glow` (насечки мер на полу), `haze` |
| `hall_gallery_of_lamps` | `glow` ×7 (светильники), `pulse` (свод) |
| `hall_sea_of_glass` | `water` (стекло — только золотые жилы под ним), `glow` |
| `hall_archive` | `glow` (лампа аналоя), `sway` (листы на полках), `haze` (окулюс) |
| `hall_stones_of_fire` | `lava` (швы между камнями), `glow` (камни), `haze` |
| `hall_ark_sanctum` | `sway` (завеса, покров ковчега), `glow` (свет вокруг ковчега), `pulse` |
| `hall_thunders` | `haze` (облака), `stars` (искры молний), `pulse` |
| `hall_hail_gallery` | `haze`, `falls` (облачный водопад под галереей) |
| `hall_flaming_way` | `lava` (стены пламени — только «расплав» течёт), `water` (ручей), `glow` |
| `hall_eden_gate` | `lava` (изгородь огня), `glow` (щель врат), `sway` (кроны сада, `tree`) |
| картины концовок | `sway` (кроны, трава), `haze` (туман), `water` (ручей); `ch7_end_fourth` — `sway` верёвок, медленно |

7. Передний план (`front_layers.json`, docs/DEPTH.md) — куски из самих картин: колонны 3 (два, по
   краям), престолы 1 (край левого ряда), полки 5 (стойка у входа), язык пламени 9 и 10 (тёмного
   ключа нет — режется по альфе; проверить `depth_shot.gd` против светлого фона), балюстрада 8б.
   Тёмный ключ здесь работает плохо: фон светлый — брать куски по альфе.
8. Тайники — `make_secret_walls.py`: мраморная панель с вырезанным венцом (1, средняя площадка),
   ниша у двери двора (2), полка на верхней галерее (5). Стена режется из самой панели.

## 5. Проверка перед pull request

- `make validate` (полосы против клеток, правило оживления на каждую комнату и картину, глифы).
- `reach_test.gd -- hall_<id>`, `stairs_test.gd`, `void_fall_test.gd` на каждую новую комнату;
  `hall_hail_gallery` — пол сплошной, края нет; `hall_stones_of_fire` — швы — лава, не край карты.
- Бестиарий: рост против героя (Херувим 76–84, мерщик 54–58), у каждого ряда атаки виден замах.
- Свет: ни одной нарисованной тени на панелях (кроме листа Люцифера); красного нет.
- Ни трона, ни фигуры в свете, ни лица у ковчега — на всех 17 картинах.
- `depth_shot.gd` / `backdrop_life_shot.gd` на 4б и 10 — стекло и изгородь читаются.
