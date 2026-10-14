# Глава III — заказ картин

*Картины главы «Третья труба · Гнев» (docs/CHAPTER3.md). Ничего ещё не нарисовано: этот файл —
заказ. Рисует Codex CLI (`codex exec`, встроенная генерация картинок) по промптам ниже, как
рисовал Сеир; то, что у него выйдет слабо, уходит художнице (её ChatGPT, навык `ashes-art`,
`.claude/skills/ashes-art/SKILL.md`). Пока картины нет, глава играется на заглушках — они названы
в каждой строке.*

## Состояние

| Что | Статус | Чем заменено пока |
|---|---|---|
| 12 панелей 1280×720 `assets/levels/marah_*.png` | **не нарисовано** | ничем: комната без картины не входит в игру; ночь `marah` не вписывается в `game.json`, пока не готовы все 12 и не зелёны reach / stairs / void / smoke |
| Атласы `host_spearman`, `host_archer`, `host_sentinel`, `legion_brute`, `host_standard_bearer`, `legion_centurion`, `wormwood` | **не нарисовано** | `"extends"` + `sprite.like` + `tint` (CHAPTER3.md §8): `gate_warden`, `ash_archer`, `wraith`, `shield_bearer`, `gate_warden` ×1,15, `fallen_champion`, `ophanim` |
| `legion_possessed`, `wormwood_shade` | **не рисовать** — варианты на старых полосах | `possessed_villager` (тёплая сажа), `wraith` (зелёный) |
| Портреты врагов (7) и босса | **не нарисовано** | портрет того, чью полосу он берёт |
| Листы тел людей (`malchus`, `marah_scout`, `malchus_hanged`, `rizpah`, `parley_bannerbearer`, `parley_centurion`) | **не нарисовано** | `severin_v2` (Малх), `villager_v2` (разведчик, повешенный Малх — его лист с полосой `hanged`), `nun_v2` (Рицпа), `stranger_v2` (Знаменосец, тон белый), `knight_of_ash_v2` (Сотник, тёплый) |
| Портреты людей (Малх, Рицпа, Знаменосец, Сотник, Полынь) | **не нарисовано** | `severin`, `nun`, `stranger`, `knight_of_ash`, `ophanim` |
| Полоса горькой воды `assets/fx/liquids/body_bitter.png` | **не нарисовано** (генератор) | `body_bog.png` |
| Стили снарядов `host_arrow`, `wormwood`, `wormwood_ember` | **не нарисовано** | полосы `lance`, `wraith`, `ember` с тоном |
| Пластины глубины (`depth/<room>_backfill.png`) | **не нарисовано** | без них проёмы стоят |
| Передний план (`front_layers.json`) | **не нарисовано** | без него |
| Замурованные стены у 3 тайников (`reveals`) | **не нарисовано** | тайник стоит открыто |

Порядок: сначала 12 панелей (без них нет главы), затем атлас Полыни и обеих армий (копейщик,
громила — их больше всего на экране), затем люди (их видно в сценах), затем глубина и передний
план.

## 0. Библия стиля главы

Всё из `docs/ART_DIRECTION.md` остаётся: тёмный готический пиксель-арт, нарисованный, а не из
тайлов; ночь; читаемость прежде красоты; нижняя пятая часть фона тёмная и тихая — там тела.
Что меняется в Мерре (`CAMPAIGN.md` §10):

- **Долина войны, а не город.** Глина, мел, обугленное дерево, шатровое полотно, колья, окопы,
  колесницы, осадная башня. Земля бледная — мел и выжженная глина, — под холодной ночью она
  читается серо-лиловой. Камень только у источника и в колодцах.
- **Вода — горькая полынная зелень.** Абсентовая, мутная, неподвижная или медленная; зелень
  тусклая (`#3d4a26` в глубине, `#b8c48a` на поверхности), не ядовито-неоновая. Больше зелёный
  в главе ничем не занят: трава выгорела.
- **Два огня.** Костры Воинства — **белые**, холодные, бело-голубые, ровные, как свечи под
  стеклом; костры Легиона — **тёплые**, оранжево-янтарные, дымные. На картине обе стороны видны
  по свету ещё до врагов. Звёздный огонь Полыни — бело-голубой, ярче всех, только в верховье.
- **Знамёна без знаков.** Воинство — белёное полотно, Легион — **умбра и сажа, никогда не
  красное** (красный — Сеир и кровь). Ни крестов, ни пентаграмм, ни букв.
- **Повешенные** — только как малые далёкие силуэты на столбах у горизонта; на переднем дереве
  виселицы — пустая петля (разведчика и Малха рисует игра телами NPC). Ни крови на картине, ни
  ран.
- **Не руины города, а следы боя.** Сломанные копья, брошенные щиты, колёса, ямы, выжженные
  круги; дым на горизонте. Всё недавнее: «здесь дерутся каждый день».

Общий блок для промптов панелей (подставлять в каждый как `Style:` и `Constraints:`):

> **Style:** carefully authored dark fantasy pixel art, discrete crisp pixels and restrained
> dithering, coherent stone and clay sizes. A war valley at night along a bitter river: pale
> chalk and burnt clay ground under cold blue-violet night light, charred wood, tent cloth,
> stakes, broken spears and shields. Water, where visible, is dull absinthe green, murky and
> still. Two kinds of fire: white, cold, blue-white steady flames on one side; warm amber smoky
> fires on the other. Banners are plain bleached white cloth or plain umber and soot cloth, with
> no symbols. No red anywhere except a tiny ember. Hanged figures only as tiny distant
> silhouettes on posts at the horizon, never close. Gentle contrast so enemies and hero remain
> legible.
>
> **Constraints:** strict orthographic side elevation, camera perpendicular to the scene, no
> perspective floor, no vanishing point. A continuous walkable floor line as stated in the
> request. Entrance at the left edge, a real dark doorway, gap or passage at the far right
> (about 97 percent across) for the game's exit gate. Ledges a person could stand on drawn as
> flat-topped ledges with readable edges, no floating platforms. Keep the main landmarks away
> from 35 percent and 65 percent of the width unless the request says otherwise. The bottom
> fifth stays dark and quiet. Opaque canvas, artwork to every edge. No characters, no people
> except tiny distant silhouettes where stated, no text, no letters, no symbols on banners, no
> labels, no UI, no watermark, no border.

## 1. Панели комнат — 12 штук, 1280×720 (не нарисованы)

Каждая — `assets/levels/<id>.png`, 16:9 (размер в промпт **не** писать: Codex рисует 1536×1024,
студия кадрирует). Генератор расширит её до 1600 швами (`_quilt_band`) на 35 % и 65 % ширины:
ориентиры держать подальше от них или назвать в `FOCAL_RANGES` (`generate_rooms.py`). Высоты
уступов — доля высоты панели от **низа** (0,5 = середина). «Два экрана» — комната в 2 экрана
высотой (`height` 1440 после генератора), панель рисуется как обычно, но с вертикальной
композицией: уступы снизу доверху, выход наверху справа. Босс — один экран, ровный пол.

Картинки-роли: **Image 1** — `assets/levels/graveyard_arches.png` (масштаб камня, толщина уступов,
темнота — ТОЛЬКО это); для интерьеров (шатёр, колодцы) — `assets/levels/seir_warehouses.png`.
**Image 2** — референс места, если выбран, иначе не прикладывать.

| # | id | Primary request + Composition | Где люди и вещи (для трассировки) |
|---|---|---|---|
| 1 | `marah_gallows` | A lone gallows tree on a chalk bluff above a river ford at night; one thick branch with an empty noose; a rough cairn of stones among its roots; far behind, the valley with tiny white fires on the left horizon and warm fires on the right, and tiny hanged silhouettes on distant posts. **Composition:** a continuous walkable floor along the bottom quarter; the bluff rises as one flat-topped shelf in the middle third at 0.42 height, reached by a low step at 0.25 in the left third; the tree stands at about 50 percent, its crown in the upper half (name it in FOCAL_RANGES); open night sky across the upper half; entrance at the left edge, a dark path down between rocks at the far right (about 97 percent). | Малх и разведчик под веткой на уступе (середина); стража Воинства — левая треть пола, одержимые — правая; тайник `marah_cache_rizpah_names` — кладка камней у корней (уступ, справа от ствола). |
| 2 | `marah_ford` | A wide shallow river ford of murky absinthe-green water at night; broken spears standing in the water, a half-sunk shield, stepping stones; white fires on the far left bank, warm fires on the far right bank. **Composition:** the water lies over a continuous floor along the bottom quarter (the floor is the riverbed, knee-deep water above it); three flat stepping-stone ledges at 0.3 height in the left, middle and right thirds, kept off 35 and 65 percent; a sandbar shelf at 0.45 in the right third; open sky over the whole upper half; entrance at the left edge on a muddy bank, a dark gap in the reeds at the far right (about 97 percent). | Воинство — левая половина, Легион — правая; вода по колено по всему полу. |
| 3а | `marah_host_bank` | The Host's camp on the riverbank: bleached white tents, weapon racks of spears, a tall white-flamed brazier on a pole, a wooden watch platform; everything clean, ordered, cold-lit. **Composition:** a continuous walkable floor along the bottom quarter; the watch platform is a flat wooden deck at 0.5 height in the right third with a ladder; tent ridges are not walkable; a low earthen rampart shelf at 0.3 in the left third; open sky over the upper half above the tents; entrance at the left edge, a dark tent alley at the far right (about 97 percent). | Лучники на помосте справа и на валу слева; страж — в небе над шатрами. |
| 3б | `marah_legion_bank` | The Legion's camp on the opposite bank: soot-stained hide tents, warm amber fires in pits, a stockade of sharpened stakes, a cart turned on its side, smoke. Cramped and warm-lit. **Composition:** a continuous walkable floor along the bottom quarter; the overturned cart is a flat-topped ledge at 0.28 in the left third; a timber walkway along the stockade at 0.48 in the right third; a strip of murky green water at the left edge of the floor; low smoky sky in the upper third only; entrance at the left edge from the water, a dark gap in the stockade at the far right (about 97 percent). | Громилы на полу у огня, одержимые везде; тень полыни над водой слева. |
| 4 | `marah_field` | A battlefield at night between the lines: trampled pale ground, scattered broken spears and shields, a large flat rock in the left third with sackcloth spread over it and a tiny fire in a ring of stones, crows on stakes; far posts with tiny hanged silhouettes along the horizon. **Composition:** a continuous walkable floor along the bottom quarter; the rock is a flat-topped shelf at 0.3 height in the left third (about 15–28 percent across); a low earth bank at 0.35 in the right third; wide open sky over the upper half, the horizon low; entrance at the left edge, a dark gap between trench posts at the far right (about 97 percent). | Рицпа на скале слева; место отдыха — у скалы на полу; вороны на кольях. |
| 5 | `marah_trench` | Zigzag trenches cut into white chalk, seen in cross-section, two storeys deep: plank revetments, firing steps, a parapet with sandbags at the top, a collapsed dugout with a boarded doorway on the middle level. **Two screens tall.** **Composition:** a continuous walkable trench floor along the bottom tenth; firing steps as flat ledges at 0.22 (left third) and 0.38 (right third); a middle trench floor at 0.52 across the middle third; a higher step at 0.68 in the left third; the parapet top at 0.84 runs across the right two thirds and reaches the exit; a narrow sky strip above the parapet only; entrance at the left edge at the bottom, the exit a dark gap in the parapet at the top right (about 97 percent). | Лучники на бруствере; сотник на средней траншее; тайник `marah_cache_two_orders` — заколоченная землянка на средней траншее (левая треть). |
| 6 | `marah_parley` | Inside a truce tent between the lines: a long low table in the middle with two stools, the left half of the tent is bleached white cloth lit by a white lamp, the right half is soot-stained hides lit by a warm lamp; a central tent pole; entrances flap open at both ends. **Composition:** a flat continuous floor along the bottom fifth; the table and stools stand at about 50 percent (name it in FOCAL_RANGES); a low wooden dais at 0.25 in the left third and another in the right third; no sky — the tent roof fills the upper third; entrance flap at the left edge, a dark open flap at the far right (about 97 percent). | Знаменосец за столом слева, Сотник справа; стража у входов. |
| 7 | `marah_siege` | A siege line: burnt war chariots, a half-burnt wooden siege tower standing against a broken earthen rampart, scattered wheels and spears, smoke. **Two screens tall.** **Composition:** a continuous walkable floor along the bottom tenth; a burnt chariot as a flat ledge at 0.2 in the left third; the siege tower in the right third with three flat floors at 0.35, 0.55 and 0.75 joined by ladders; the rampart top at 0.62 in the left third reachable from a ruined ramp; open sky between tower and rampart in the upper half; entrance at the left edge at the bottom, the exit a dark gap behind the tower's top floor at the far right (about 97 percent, at 0.75). | Знаменосец-элита на полу у колесниц; стражи над башней; лучники на этажах башни. |
| 8а | `marah_bitter_wells` | Underground cisterns cut in rock: deep square basins of murky absinthe-green water, stone walkways between them, a shaft of pale light from a hole above, wooden buckets on ropes. **Composition:** a stone walkway floor at 0.22 height interrupted by two water basins (left-middle and right-middle, each with a visible stone bottom at 0.05 so a body can swim, not fall); stone ledges at 0.45 in the left and right thirds; an arch in the middle third; no sky except the light shaft opening at the top middle; entrance at the left edge, a dark stone passage at the far right (about 97 percent). | Тени встают из бассейнов; одержимые на мостках; лучник на правом уступе. |
| 8б | `marah_dry_bed` | A dry riverbed: cracked pale mud, bleached boulders, a dead tree, the old high-water line on a clay cliff, open sky. **Composition:** a continuous walkable floor along the bottom quarter; two flat boulders as ledges at 0.3 in the left third and 0.32 in the right third; a clay terrace at 0.5 along the right third; wide open sky over the upper half; entrance at the left edge, a dark cleft in the cliff at the far right (about 97 percent). | Стражи в небе; лучники на террасе; громила внизу. |
| 9 | `marah_springs_path` | A switchback path climbing a chalk hillside toward a glowing white-blue light beyond the top; a shepherd's stone fold with a dry stone trough on the lowest terrace, a small hut with a blocked doorway on the middle terrace, scattered thorn bushes. **Two screens tall.** **Composition:** a continuous floor along the bottom tenth; terraces as flat ledges at 0.25 (whole left half, with the fold and trough at about 20 percent), 0.45 (right third, the hut), 0.62 (left third), 0.8 (right two thirds, reaching the exit); open sky in the upper half, brightening toward the top right; entrance at the left edge at the bottom, the exit a dark gap between rocks at the top right (about 97 percent, at 0.8). | Место отдыха — корыто на нижней террасе; тайник `marah_cache_shepherd_tally` — заваленная дверь хижины (средняя терраса); тени у кустов. |
| 10 | `marah_wormwood_spring` | The spring at the head of the valley: a round stone basin of murky absinthe-green water in the centre with a fallen star half-sunk in it (a cracked stone shell with blue-white fire inside, steam rising), two low flat rocks on either side, the chalk walls of a hollow around, the night sky above lit white-blue. **One screen tall, boss arena.** **Composition:** a flat continuous floor along the bottom fifth across the whole width (the basin is a shallow depression in that floor, its water level with the floor); two low flat-topped rocks at 0.3 height, one in the left third (about 18 percent) and one in the right third (about 82 percent); the star and basin at 50 percent (name it in FOCAL_RANGES); open sky over the upper half; entrance at the left edge, a dark gap at the far right (about 97 percent). | Полынь над чашей (игра рисует её телом; на картине — только скорлупа в воде, чтобы ей было куда «сесть»); скалы — сухие острова при подъёме воды. |

Ширина развилки (`marah_ford` → берега, `marah_siege` → колодцы / русло) на картинах не видна:
дверь справа одна, вопрос задаёт игра.

Промпт панели целиком (пример для `marah_field`; остальные — так же, со своей строкой):

> Use case: stylized-concept. Asset type: production background panel for a side-view dark
> fantasy pixel-art platformer, chapter III "Marah, the third trumpet".
> Image 1 is the game's style reference: match its pixel scale, stone size, ledge thickness and
> darkness ONLY — not its architecture.
> **Primary request:** A battlefield at night between two armies' lines: trampled pale chalk
> ground, scattered broken spears and dropped shields, a large flat rock in the left third with
> a sackcloth spread over it and a tiny fire in a ring of stones, crows on sharpened stakes; far
> along the low horizon, tiny posts with tiny hanged silhouettes; white cold fires far to the
> left, warm amber fires far to the right.
> **Composition:** a continuous walkable floor along the bottom quarter; the rock is one
> flat-topped shelf at 30 percent of the height, between 15 and 28 percent across; a low earth
> bank, flat-topped, at 35 percent height in the right third; wide open night sky over the upper
> half; nothing important at 35 or 65 percent of the width; entrance at the left edge, a dark gap
> between trench posts at the far right, about 97 percent across.
> **Style:** …(общий блок)… **Constraints:** …(общий блок)…

## 2. Враги — атласы 7×7 (не нарисованы)

Каждый — `assets/sprites/enemy_atlases/<id>.png`, сетка 7×7, ряды сверху вниз: idle, walk,
attack, attack_alt, special, hurt, death (`ART_DIRECTION.md`, «Enemies»). **В каждом ряду атаки
первые 2–3 кадра — замах** (то, что описано в CHAPTER3.md §6 как замах; без них удар не
читается). Режет `tools/art/build_bestiary_assets.py` (`GAME_CELLS` — клетка и масштаб; полосы —
`sprite` в `data/enemies/<id>.json` и `data/enemy_archetypes/tree.json`). Роли:
**Image 1** — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7, ТОЛЬКО сетка);
**Image 2** — `tools/studio/refs/elian_style_idle.png` (масштаб, контур, тёмная палитра — не его
броня).

| id | Кто | Рост (герой 44) | material | Ряды, на что смотреть | Сейчас стоит |
|---|---|---|---|---|---|
| `host_spearman` | Ревнитель-человек в белёной кольчуге, белый табард без знака, открытый шлем, копьё с маленьким белым огоньком на острие | 46–48 | mail | attack — копьё отводится к плечу, укол; attack_alt — остриё опускается к земле, присед, выпад вперёд; death — падает на колени, копьё стоит | `gate_warden` (`#e8ecf4`) |
| `host_archer` | Лучник в белом плаще с капюшоном, длинный лук, колчан | 44 | cloth | attack — тетива к уху, наконечник вспыхивает белым (2 кадра), выстрел дважды; walk — пятится; hurt | `ash_archer` |
| `host_sentinel` | Ангел-посланник: высокий, вместо лица — белое ровное пламя, крылья как сложенные белые полотнища, ступни не касаются земли | 52 (в полёте) | feather | idle — парит; attack — пламя стягивается в ладони (луч рисует игра); attack_alt — бросок копьеца; death — гаснет, полотнища опадают | `wraith` (`#e8f0ff`) |
| `legion_brute` | Падший громила: обгоревшие латы, рога сломаны, щит из створки ворот, топор | 54–56 | plate | idle — за щитом; attack — топор **долго** уходит за плечо, широкий удар; attack_alt — щит отводится, толчок; death — падает вперёд на щит | `shield_bearer` (`#c8a080`) |
| `host_standard_bearer` (элита) | Высокий ревнитель в латах поверх белой ризы, древко с белым огнём на вершине вместо знамени | 56–58 | mail | attack — древко отводится обеими руками, удар; special — вонзает древко в землю, огонь вспыхивает (зов) | `gate_warden` ×1,15 |
| `legion_centurion` (элита) | Падший сотник: чёрные латы с медью, красивое лицо без глаз, короткий меч, круглый щит | 54 | plate | attack — рубящий; attack_alt — щит вперёд, корпус назад, рывок; special — меч поднят обеими руками, удар в землю | `fallen_champion` (`#c09060`) |
| `wormwood` (босс) | Упавшая звезда: ядро бело-голубого огня в треснувшей каменной скорлупе, с краёв сходит пар, внизу — капли горькой воды; без лица, без рук | 80–90 | gold | idle — пульсирует; attack — втягивает свет, ядро белеет (угли); attack_alt — в скорлупе открывается щель (луч); special — тускнеет и сжимается (вспышка); hurt — трещины светятся; death — скорлупа раскалывается, огонь уходит вниз, в воду | `ophanim` (`#d8ecff`) |

`legion_possessed` и `wormwood_shade` — без нового атласа: `possessed_villager` с тёплой сажей и
`wraith` с зелёным тоном. Если художнице понравится — тень полыни можно дорисовать: зелёный дух с
белым огоньком внутри, как капля, с которой стекает вода.

Портрет каждого для бестиария — `assets/portraits/<id>.png`, 192×192, по одному кадру idle; у
Полыни — ядро крупно, трещины, пар.

## 3. Люди — листы NPC и портреты (не нарисованы)

Лист — три полосы (`idle`, `walk`, `interact`), клетки 48×48, как `assets/sprites/villager_v2_*`.
Портрет для диалогов — `assets/portraits/<id>.png`, 192×192 (`avatar` у NPC и `speakers` в
`data/dialogue_looks.json`). Роли: **Image 1** — её дизайн или `villager_v2_idle.png` (клетка),
**Image 2** — `tools/studio/refs/elian_style_idle.png`.

| id | Кто | Поза idle | interact | Сейчас стоит |
|---|---|---|---|---|
| `malchus` | Палач: немолодой, крепкий, кожаный фартук, засученные рукава, моток верёвки на плече; **рубец вокруг правого уха** (видно в профиль) | стоит, мотает верёвку на локоть | тянет верёвку вниз обеими руками | `severin_v2` |
| `marah_scout` | Разведчик Легиона: молодой, в краденой лёгкой броне, руки связаны, петля на шее, стоит на чурбаке | стоит, качается, голова опущена | падает с чурбака и убегает (полоса `walk` — бег) | `villager_v2` |
| `malchus_hanged` | Тот же Малх, висящий (одна полоса idle, медленно качается; рисовать тихо, без лица) | висит | — | `severin_v2` повёрнутый |
| `rizpah` | Старая женщина в мешковине, седые волосы не покрыты, палка в руке, сидит на скале у маленького огня | сидит, держит палку | встаёт, машет палкой на птиц | `nun_v2` |
| `parley_bannerbearer` | Ангел-знаменосец: высокий, белые одежды, вместо лица — ровный белый свет, руки на столе; крылья сложены за спиной | сидит за столом | встаёт, указывает рукой | `stranger_v2` (белый тон) |
| `parley_centurion` | Падший сотник за столом: тёмные латы с медью, красивое спокойное лицо, глаза тёмные, рог один сломан | сидит, откинувшись | наклоняется вперёд, ладонь на стол | `knight_of_ash_v2` (тёплый тон) |
| (портреты) `malchus`, `rizpah`, `parley_bannerbearer`, `parley_centurion`, `wormwood` | крупно: Малх — рубец на ухе; Рицпа — лицо в свете маленького огня снизу; Знаменосец — белый свет без черт; Сотник — лицо без гнева; Полынь — ядро | — | — | — |

Ангел и падший рисуются одинаково достойно: ни один не уродлив, ни один не светится «добром».

## 4. Как рисовать

Каждая картинка:

`codex exec -m gpt-5.6-sol --skip-git-repo-check -s workspace-write -C <папка> -i <роль.png> - < промпт.txt`

по 3–4 минуты на картинку, одна картинка — один вызов. Роли:

- панели — `assets/levels/graveyard_arches.png`; интерьеры (`marah_parley`, `marah_bitter_wells`) —
  `assets/levels/seir_warehouses.png`;
- атласы — `assets/sprites/enemy_atlases/fallen_guard.png` (раскладка 7×7) и
  `tools/studio/refs/elian_style_idle.png` (масштаб, контур) — два `-i`;
- листы людей и портреты — `tools/studio/refs/elian_style_idle.png` и портрет главы II как роль
  кадра.

Конвейер:

1. Панель → `assets/levels/<id>.png` → `python3 tools/rooms/trace_panel.py <путь.png> <id>` →
   выбрать настоящие уступы по пронумерованному оверлею → строка в `tools/rooms/painted_rooms.py`
   (вход слева, выход справа; `check_reach` при генерации) → `python3 tools/rooms/generate_rooms.py`.
   Горькая вода — `liquids` в `tools/rooms/studio_rooms.json`; в `marah_wormwood_spring` лужа
   именуется `Spring` (её поднимает `flood`, CHAPTER3.md §9).
2. Атлас → `assets/sprites/enemy_atlases/<id>.png` + строка в `GAME_CELLS` →
   `python3 tools/art/build_bestiary_assets.py` → `tree.json`; снять `"extends"` заглушки в
   `data/enemies/<id>.json`.
3. Полоса `body_bitter.png` и стили снарядов — `tools/art/make_liquids.py` (новая запись `bitter`)
   и полосы снарядов там же, где лежат `lance` / `ember`.
4. Всё, что пишет картинку, проходит через `patched()` (`tools/art/studio_overrides.py`).
5. Строка в `assets/CREDITS.md` на каждую картинку (Codex, дата, промпт — по образцу Сеира).

На каждую комнату (предложения; сессия сборки проверяет по картине):

| Комната | `<id>.lights.json` (нарисованные огни) | `FAR_WINDOWS` | Правило `data/backdrops.json` (семья `marah`) | Передний план (`front_layers.json`) |
|---|---|---|---|---|
| `marah_gallows` | далёкие костры: белые слева, тёплые справа | небо — верхняя половина | `sway` на кроне и петле (`"tree"` — сухая крона, мало листьев), `glow` на белых кострах, `stars`, `haze` у брода | камни и сухая трава снизу |
| `marah_ford` | костры обоих берегов | небо | `water` на всей воде, `glow` белые, `haze` над водой | камыш, торчащие копья |
| `marah_host_bank` | белая жаровня на шесте, белые костры | небо над шатрами | `glow` (белое не мерцает само — нужна зона), `sway` на полотнищах шатров | колья, растяжки шатров |
| `marah_legion_bank` | тёплые костры в ямах (мерцают сами) | — (дымное небо — не проём) | `haze` дым, `water` слева, `sway` на шкурах | заострённые колья частокола |
| `marah_field` | огонёк Рицпы, дальние костры | небо | `stars`, `sway` на кольях с воронами, `glow` на огне Рицпы | обломки копий, щит |
| `marah_trench` | редкие тёплые фонари в окопе | полоса неба над бруствером | `haze` меловая пыль, `glow` | мешки с песком, доски |
| `marah_parley` | белая лампа слева, тёплая справа | — | `glow` на обеих лампах, `sway` на полотнищах входов | столб шатра, растяжка |
| `marah_siege` | тлеющие колесницы, пожар в башне | небо между башней и валом | `haze` дым, `glow`, `pulse` на углях башни | колесо колесницы, копья |
| `marah_bitter_wells` | световой колодец сверху | — | `water` в бассейнах, `glow` в луче, `haze` | вёдра на верёвках, капли |
| `marah_dry_bed` | — (только ночь) | небо | `stars`, `haze` у земли | валуны, кости |
| `marah_springs_path` | бело-голубой свет за вершиной | небо, светлеет кверху | `glow` на свечении, `sway` на кустах, `stars` | терновник |
| `marah_wormwood_spring` | ядро звезды, отсвет на мелу | небо | `water` на чаше, `glow` и `pulse` на звезде (бьётся быстрее при `life_rage`), `haze` пар | пар, камни чаши |

Белые огни Воинства и звезды `BackdropLife` сам огнём не считает (он ищет «тёплое и яркое»): у
каждой комнаты, где они есть, — зоны `glow`, иначе они мёртвые (CHAPTER3.md §9).

Замурованные стены (`tools/art/make_secret_walls.py`, `reveals`) у трёх тайников:

| Тайник | Комната | Что вырезать из картины |
|---|---|---|
| `marah_cache_rizpah_names` | `marah_gallows` | кладка камней у корней дерева |
| `marah_cache_two_orders` | `marah_trench` | доски, заколотившие вход в землянку |
| `marah_cache_shepherd_tally` | `marah_springs_path` | камни, завалившие дверь хижины |

Ни одна из них не на шве (35 % / 65 %) — проверить после трассировки.

## 5. Проверка перед pull request

- `make validate` (полосы против клеток, тайники, правило оживления на каждую комнату, CJK-знаки).
- `reach_test.gd -- marah_<id>`, `stairs_test.gd`, `void_fall_test.gd`, `exits_test.gd` на каждую
  новую комнату; `smoke_test.gd` проходит ночь `marah`.
- `backdrop_life_test.gd` (зоны лежат на картине), `depth_test.gd`, `layers_test.gd`;
  `depth_shot.gd` и `backdrop_life_shot.gd` — глазами: белые огни дышат, вода не стоит мёртвой.
- `python3 tools/check_generators.py` — сцены совпадают с таблицами.
- Бестиарий: рост против героя (44), каждый ряд атаки начинается с замаха.
- Глазами: ни одного красного знамени, повешенные — только малые и далёкие, ни одной буквы на
  картине.
