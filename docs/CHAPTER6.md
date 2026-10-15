# Глава VI — «Шестая труба» · Зависть

*Обитель на Евфрате: монахи сорок лет одной молитвой держат в русле реки четырёх связанных ангелов —
и завидуют им, потому что тех держит Бог. Ангелы завидуют людям: люди выбирают, умирают и бывают
прощены. Глава ещё не построена: этот документ — её план и контракт для сессии сборки. Источник
правды — `docs/CAMPAIGN.md`; там, где этот файл с ним расходится, прав CAMPAIGN. Заказ картин —
`docs/CHAPTER6_ART.md`.*

- Ночь — `euphrates` (`data/game.json` `nights`, §8), префикс комнат `euphrates_`. Чьё: **Небо**.
- Данные главы — в `data/` (враги, люди, диалоги, сцены, тайники, развилки, места отдыха, записи,
  области); дары и знамения — `data/abilities/chapter_6.json`, `data/omens/chapter_6.json`, с
  `"nights": ["euphrates"]`: сдаются только в эту ночь (`Omens.of_night`).
- «Шестая труба» (Откр. 9:13–21, пересказ): голос от четырёх рогов золотого жертвенника велит
  развязать четырёх ангелов, связанных у великой реки Евфрат; они приготовлены на час, и день, и
  месяц, и год — убить третью часть людей. Конница — двести миллионов; у коней головы львиные, из
  пасти огонь, дым и сера, хвосты — как змеи с головами. Прочие люди не раскаялись.
- Откр. 10: ангел, одной ногой на море, другой на земле, с раскрытой книжкой: «возьми и съешь — горько
  во чреве, сладко в устах»; семь громов сказали свои слова, и Иоанну велено запечатать их и не писать.
- Откр. 11:3–12: двух свидетелей убили; их тела лежат на улице, жители радуются и шлют друг другу
  подарки; через три дня с половиной они встают. Зеркало Элиана — он тоже встаёт.

## 1. Карта

```
Берег ─► Город ─► Ворота ─┬─ Галерея ──┬─► Трапезная ─► Колокольня ─► Двор алтаря ─┬─ Склеп цепей ─┬─► Лестница в русло ─► Русло
  │        │         │    └─ Скрипторий ┘        │            │              │       └─  Цистерна   ─┘          │               │
книжка  свидетели  свиток                   авва Саул     запечатанный   голос от рогов                    письмо послушника   Четверо → финал
(выбор)  (выбор)   стражей                 (выбор, отдых)  лист          (лев-конь)                         (отдых)
```

| # | Область | Комната | Люди | Сцена | Кто держит дверь |
|---|---|---|---|---|---|
| 1 | Берег великой реки | `euphrates_bank` | **ангел с книжкой** (нарисован в глубине, говорит) | `little_book` — первый выбор главы | два духа реки, всадник |
| 2 | Город у брода | `euphrates_town` | пирующие (scripted), два свидетеля (лежат), человек с рубцом на ухе (уходит, scripted) | `witnesses_in_the_street` — второй выбор | три бичующихся (крестный ход через пир), дух реки |
| 3 | Обитель | `euphrates_gate` | — | — · тайник `note_chain_roll` | два бичующихся, два кадильщика |
| 4а | Обитель | `euphrates_cloister` | — | — | три бичующихся, кадильщик, всадник во дворе |
| 4б | Обитель | `euphrates_scriptorium` | — | — | три кадильщика, бичующийся, прикованный переписчик |
| 5 | Обитель | `euphrates_refectory` | **авва Саул** | `refectory_arrival` (подпись) · место отдыха | два бичующихся, кадильщик (в погребе, левая треть) |
| 6 | Обитель | `euphrates_bell_tower` (два экрана, составная) | — | — · тайник `note_seven_thunders` | два кадильщика, два прикованных, скованный ангел под колоколами, два духа |
| 7 | Двор алтаря | `euphrates_altar_court` | **голос от рогов** (без тела) | `voice_from_the_horns` | **конь с львиной головой** (элита), два бичующихся, два кадильщика, два прикованных |
| 8а | Двор алтаря | `euphrates_crypt_of_chains` | — | — | пять прикованных, два скованных ангела, кадильщик |
| 8б | Двор алтаря | `euphrates_cistern` | — | — | четыре духа реки, два бичующихся |
| 9 | Русло | `euphrates_river_stair` | — | — · место отдыха · тайник `note_novice_envy` | два всадника, конь с львиной головой, два духа, прикованный |
| 10 | Русло | `euphrates_bound` | **Четверо связанных** (босс) | `the_four_bound` → бой → `ch6_finale` | Четверо |

12 комнат, ночь проходит 10. Развилки — `data/forks/chapter_6.json`, как в Сеире (`Route`): ответ на
вопрос двери — ключ варианта, пропуск — первый путь, ветви сходятся и не несут истории (ни сцены, ни
человека, ни места отдыха). Кольца `chain` — не история, в склепе цепей их семь; тайников в развилках нет.

| Развилка | После | Вопрос | Пути | Сходятся в |
|---|---|---|---|---|
| `euphrates_cloister_fork` | `euphrates_gate` | `fork_euphrates_cloister` | `cloister` (открытая галерея, сад, бичующиеся, всадник) / `scriptorium` (тесно, полки в три яруса, кадильщики) | `euphrates_refectory` |
| `euphrates_depth_fork` | `euphrates_altar_court` | `fork_euphrates_depth` | `crypt` (склеп цепей: прикованные и скованные) / `cistern` (вода, духи реки) | `euphrates_river_stair` |

## 2. Как «цепи» меняют петлю

Сеир учил проходить мимо тех, кто ждёт. Евфрат учит мерить расстояние: здесь у многих есть длина.

- **Цепи** (`"tether": {"length": px}` у врага, новое, §9). Тело прикреплено к якорю — к своему
  месту появления, к точке `anchor` [x, y] или к кольцу-пропу `chain`, если оно стоит ближе 48 px.
  Дальше цепи оно не уходит. Цепь видна: линия железа от кольца до пояса, провисает, пока есть
  запас, и выпрямляется, когда натянута. У конца цепи тело **натягивается** — поза `special` (у
  кого нет — `hurt`), звук `chain_strain`, 0,6–1,0 с без ударов. Это и окно: бей того, кто натянул
  цепь.
- **Рывок к концу цепи.** Лунж прикованного на замахе тянет цепь прямо (линия звенит и светлеет —
  читаемый замах 0,9 с), а на конце цепи обрывается рывком (`chain_snap`, лёгкая тряска) — и тело
  стоит в натяжении. Кто стоит на шаг дальше длины цепи, тот видит удар и не получает его.
- **Ритм.** 1–2 — открытый мир (река, город), враги без цепей; 3–5 — обитель, монахи; 6–9 — цепи
  всё гуще: колокольня учит длине, склеп цепей — лес цепей, лестница в русло — всадники и элита;
  10 — четыре цепи и одна, что растёт.
- **Соблазн.** Ключи аввы (`saul_keys`, выбор соблазна у Саула) отпирают цепи: у кольца —
  подсказка «Отомкнуть» (E, тач — кнопка разговора), и прикованный — **отпущен**: быстрее,
  сильнее, без цепи и сразу охотится (`"freed"` в его JSON). Скованный ангел, отпущенный, не
  дерётся — он уходит вверх по реке и не оборачивается (`"freed": {"leaves": true}`). Отпереть —
  выбор, не побочный удар: без ключей удар по цепи звенит и высекает искры, но ничего не рвёт
  (решение — §9). Отпертое помнят Четверо (`chain_opened`, `fettered_freed`).
- **Цена милосердия.** Отпустить прикованного — значит драться с ним без его цепи. Укрыть свидетелей
  ничего не даёт; взять с их груди дар — фляга (`"flask": 1`). Съесть книжку — горько во чреве и
  ничего в руках, но это единственная улика главы, которую помнят следующие ночи.
- **Дар против механики.** `loosened_chain` (соблазн) — удар по натянутому стоит больше, в том числе
  по Четверым. Знамение `loosed_river` — все цепи длиннее в полтора раза.
- **Босс, построенный на цепи.** Четверо — четыре столба и одно тело в бою: просыпается один, трое
  натягивают свои цепи у столбов. С каждой четвертью здоровья бодрствующего утягивает к его столбу,
  встаёт следующий — и его цепь длиннее (170 → 250 → 330 → 460). Совет: держись дальше цепи, бей,
  когда цепь натянута.

## 3. Как рассказывается история

Как в главах I–II: сцены (`data/cutscenes`) держат игру, подписи (`"blocking": false`) идут поверх
игры, у людей — пузыри на E. Каждая реплика пропускается; выбор, пропущенный с разговором, — выбора
не было. Все тексты — `localization/strings.csv`, 4 языка (§10 — ru и en; uk и zh_CN переводит сессия
сборки, новые знаки — через `make_cjk_font.py`).

Источники (пересказ, не цитата Писания): Откр. 9:13–21 (голос от рогов, четверо у реки, конница,
кони с львиными головами и хвостами-змеями, «не раскаялись»); Откр. 10 (ангел с книжкой, семь
громов, «запечатай»); Откр. 11:3–12 (два свидетеля, подарки, три дня с половиной). Авва Саул назван
по Саулу, который «с того дня подозрительно смотрел на Давида» (1 Цар. 18:9); его отец в свитке
стражей — Кис (1 Цар. 9:1). Человек с рубцом на ухе — Малх (Ин. 18:10): в главе III его могли
пощадить. Свидетели не названы — ни Моисей, ни Илия: игра не толкует, кто они.

**Голос от рогов** — без тела, без портрета, без имени. Он не Божий, и никто в главе этого не обещает:
сам он на вопрос «Ты — Он?» отвечает, что Элиан спрашивает у золота, кто в нём говорит. Монахи слышат
его сорок лет и не слушаются — это их послушание.

**Ангелы не правы оттого, что они ангелы.** Четверо завидуют тому, что у Элиана есть смерть и выбор;
один из них (Год) говорит Люцифера: «Он единственный из нас, кто выбрал» (CAMPAIGN §3). Ни Небо, ни
Бездна в главе не правы.

**Улика главы** (CAMPAIGN §2): `scroll_eaten` — в книжке всё, что каждый сказал о нём (дверь, вопрос,
имя), всё сладкое; последней страницы нет. Книжка повторяет три версии и не выбирает. Ни одна реплика
главы не говорит «значит, правда — эта».

## 4. Сцены

### Книжка (`little_book`, комната 1)
Вход в главу (`"wake": false`, он на ногах). Буря над рекой; в глубине картины — ангел, огромный,
одна нога на воде, другая на берегу, в руке раскрытая книжка (нарисован, не тело; камера — к точке
`[640, 230]`, `presence` — свет его лица). Семь ударов грома (`sound` `thunder` ×7, `flash` после
каждого, `Settings.flash_scale`). Элиан: что сказал гром? Ангел: запечатай, это не тебе. Потом —
«Возьми её и съешь». Выбор (`ch6_little_book`):

| Ответ | Путь | Флаг | Цена / что дальше |
|---|---|---|---|
| «Съесть» | благодать +1 | `scroll_eaten` (**долгий**) | сладко, потом горько; ничего в руки. Помнят Саул, голос от рогов, финал; глава VII — Енох |
| «Что в ней обо мне?» | соблазн +1 | `scroll_asked` | ангел закрывает книжку: «всё — правда, пока во рту». Улики нет |
| «Я уже читал одну» | воля +1 | `scroll_refused` | с `book_read` (глава I, долгий) — ангел о той, под алтарём; без — о приговоре, который читали вслух |

### Свидетели на улице (`witnesses_in_the_street`, комната 2)
Город у брода пирует. На мостовой посреди улицы — два тела со следами верёвки на шее; на груди у
них — подарки, которые жители кладут друг другу. Пирующий (`euphrates_reveller`, scripted) зовёт
к столу: пророки три года с половиной мучили город словом, теперь лежат, хоронить не велено.
Элиан видит следы верёвки — «как у меня». Если **не** `malchus_hanged` (глава III, долгая группа
`[prisoner_cut, malchus_asked, malchus_hanged]`; без неё — тоже) — в глубине улицы уходит вправо
человек с рубцом на ухе (`malchus_far`, scripted, `appear` → `walk` → `vanish`); никто его не
называет. Выбор (`ch6_witnesses`):

| Ответ | Путь | Флаг | Цена / что дальше |
|---|---|---|---|
| «Укрыть их» | благодать +1 | `witnesses_covered` (**долгий**) | плащ на тела; пирующие смеются. Эпилог |
| «Кто их повесил?» | воля +1 | `witnesses_asked` (**долгий**) | без `malchus_hanged` — «человек с рубцом на ухе… платы не взял»; с ним — «нашёлся другой. Верёвка всегда находит руки» |
| «Взять дар с их груди» | соблазн +1 | `witnesses_robbed` (**долгий**) | `"flask": 1` — чужая фляга, тёплая |

### Трапезная (`refectory_arrival`, комната 5) и авва Саул (`npc_saul`, на E)
`refectory_arrival` — подпись поверх игры (`"blocking": false`): длинный стол, хлеб, никто не ест;
под полом слышно цепи. Место отдыха — у печи для хлеба.
На E Саул: сначала ветка привычки главы (`{"habit": path}`), потом `scroll_eaten` («Ты ел из рук
ангела. Я сорок лет прошу у него страницу»), потом `read_chain_roll` (своё имя последним в свитке, под
ним — место). Затем о четверых: отец держал их, и его отец; «каково стеречь тех, кто ближе к Нему, чем
ты будешь когда-нибудь — их хоть держит Он». Выбор (`npc_saul` → `ask`):

| Ответ | Путь | Флаг | Цена / что дальше |
|---|---|---|---|
| «Пусть их стерегут и дальше» | благодать +1 | `saul_obeyed` | ключей нет: цепи главы не отпереть. Финал — подпись |
| «Чему ты завидуешь — их цепям?» | воля +1 | `saul_asked` | Саул отвечает правду и отворачивается; ключей нет |
| «Где ключи от цепей?» | соблазн +1 | `saul_keys` | Саул снимает ключи с пояса: кольца `chain` отпираются (§2, §9). «От тех, что в русле, ключей нет» |

### Голос от рогов (`voice_from_the_horns`, комната 7)
Вход во двор: золотой жертвенник с четырьмя рогами в центре картины. Монахи во дворе замирают
(`Game.cutscene`). Голос (`SPEAKER_HORNS`, без тела; камера — к рогам; `presence` не ставить — у него
нет глаз): «Развяжи четверых, что связаны у великой реки». Элиан: кто говорит? — «От рогов». — «Ты —
Он?» — «Ты спрашиваешь у золота, кто в нём говорит». Час назначен, остались руки; «Голосу всегда нужны
руки». Ветки: `scroll_eaten` («Тебе горько во чреве. Хорошо: не будешь спешить»), `read_seven_thunders`
(«Ты нашёл запечатанное. Не читай. Даже я не читаю»). Выбора нет: голос велит, и это всё. После сцены
просыпается конь с львиной головой у жертвенника.

### Четверо связанных (`the_four_bound`, комната 10)
Сухое русло под обителью: свод, сочится вода, четыре столба из камня и золота, к каждому прикован
ангел с завязанными глазами. Титул: «Четверо связанных — Приготовленные на час, и день, и месяц, и
год». Говорят по очереди (камера — к столбам, `[x, y]` из `bound_phases.anchors`): **Час** — «Ты первый
из пришедших, кто умер»; **День** — им сказали когда, людям — нет; **Месяц** — «Вас прощают. Нас —
исполняют»; **Год** — «Падший? Он единственный из нас, кто выбрал» (CAMPAIGN §3). Ветки по долгой группе
главы V `[pit_locked, key_thrown, key_kept]`: Час говорит строку по ответу (`key_kept` — «у тебя на
поясе ключ глубже наших цепей»). Ветки ночи: `chain_opened` (День: отпертые сильнее), `fettered_freed`
(Месяц: один из наших ушёл и не обернулся), `read_novice_envy` (Год: мальчик хотел нашу цепь). Элиан: «Я
не держу вас». Год: «Никто не держит. Держат молитвы. Их хватает до рассвета». Бой.

### Финал (`ch6_finale`, после Четверых)
Четверо не умирают — побеждён Год, последний: «Ты нас одолел. Цепи — нет». Элиан: что мне с вами
делать? Выбор (`ch6_bound_fall`):

| Ответ | Путь | Флаг | Цена / что дальше |
|---|---|---|---|
| «Оставить их связанными» | благодать +1 | `angels_kept_bound` (**долгий**) | наверху снова поют; монахи остаются стражами, ангелы — завидовать |
| «Отпустить» | соблазн +1 | `angels_loosed` (**долгий**) | цепи падают в воду; они уходят вверх по реке — на час, день, месяц, год |
| «Пусть решат люди» | воля +1 | `angels_left_to_men` (**долгий**) | Элиан поднимается и говорит монахам, где цепи; утром у входа в русло стоят все — никто не спускается первым |

Затем подписи (по флагам, как `ch2_finale`): свидетели — «Через три дня с половиной, говорят, они
встали» и строка без говорящего «Они встали. Как ты.»; по `witnesses_covered` / `_asked` / `_robbed`;
Саул (`saul_obeyed` / `saul_asked` / `saul_keys`); книжка (`scroll_eaten`); строка пути (`path`); титул
«Глава VI — Обитель осталась на реке» (`CHAPTER_VI`, `CHAPTER_VI_END`); рассвет — «продолжение следует»
(`RUN_TO_BE_CONTINUED`, до E4).

### Тайники
Как в Сеире: сундук за замурованной стеной (`make_secret_walls.py`, по стене на тайник —
`secret_wall_euphrates_gate` / `_bell` / `_stair`, `reveals` — свой сундук), запись в «Записях»
бестиария, Пепел один раз. Ни одного — в комнатах развилок.

| Запись | Комната | Пепел | Флаг | Кто читает |
|---|---|---|---|---|
| `note_chain_roll` — свиток стражей цепей: имена и годы у цепи, отец Саула Кис — сорок четыре; имя Саула последним, годы не вписаны; под ним — пустая строка, разлинованная заранее | `euphrates_gate` (сторожка, верхний уступ) | 15 | `read_chain_roll` | `npc_saul` |
| `note_seven_thunders` — лист из переплёта: чистый пергамент, посредине целая печать, края обуглены, как от молнии; кто-то держал его так долго, что остались пальцы | `euphrates_bell_tower` (под колоколами, верхний экран) | 20 | `read_seven_thunders` | `voice_from_the_horns` |
| `note_novice_envy` — письмо послушника авве: спускался к ним, они светятся холодно, «я завидую их цепи — её держит Он»; «не ищите меня у цепей — ищите там, где цепь кончается» | `euphrates_river_stair` (ниша на средней площадке) | 15 | `read_novice_envy` | `the_four_bound` |

Сундуки — `data/props/euphrates_cache_chain_roll.json`, `_seven_thunders.json`, `_novice_envy.json`
(как `seir_cache_orpah_log`: `essence` 30, `ash`, `note`, `effect.set_flags`). Записи —
`data/notes/ch6_notes.json`, `place` — id области (§7).

## 5. Выборы и кто их помнит

| Флаг | Кто пишет | Кто читает |
|---|---|---|
| `scroll_eaten` — **долгий** | `ch6_little_book` | `npc_saul`, `voice_from_the_horns`, `ch6_finale`; VII — Енох |
| `scroll_asked` / `scroll_refused` | `ch6_little_book` | `little_book` (свой ответ); ночь — больше никто (предупреждение валидатора «написан, не прочитан» — снять, прочитав их в `ch6_finale`: строка книжки по каждому) |
| `[witnesses_covered, witnesses_asked, witnesses_robbed]` — **долгие** | `ch6_witnesses` | `ch6_finale`; эпилог (VII) |
| `[angels_kept_bound, angels_loosed, angels_left_to_men]` — **долгие** | `ch6_bound_fall` | `ch6_finale`; VII — старцы, финал; эпилог |
| `saul_obeyed` / `saul_asked` | `npc_saul` | `ch6_finale` |
| `saul_keys` | `npc_saul` | **код**: проп `chain` (`opens_with`, валидатор считает это чтением флага); `ch6_finale` |
| `read_chain_roll` | тайник `euphrates_cache_chain_roll` | `npc_saul` |
| `read_seven_thunders` | тайник `euphrates_cache_seven_thunders` | `voice_from_the_horns` |
| `read_novice_envy` | тайник `euphrates_cache_novice_envy` | `the_four_bound` |
| `chain_opened` | **код**: `Enemy.loose` (`FLAGS_SET_IN_CODE`) | `the_four_bound` |
| `fettered_freed` | **код**: `Enemy.loose`, когда `freed.leaves` (`FLAGS_SET_IN_CODE`) | `the_four_bound` |
| `book_read` — долгий (глава I) | тайник `altar_book` | `ch6_little_book` (`scroll_refused`) |
| `[prisoner_cut, malchus_asked, malchus_hanged]` — долгие (глава III) | `ch3_*` (CHAPTER3) | `witnesses_in_the_street` (`malchus_far` — `unless malchus_hanged`), `ch6_witnesses` (ответ `asked`) |
| `[pit_locked, key_thrown, key_kept]` — долгие (глава V) | `ch5_*` (CHAPTER5) | `the_four_bound` (Час) |

В `data/game.json` `flags_kept` глава дописывает (в конец, не трогая чужого):
`"scroll_eaten"`, `["angels_kept_bound", "angels_loosed", "angels_left_to_men"]`,
`["witnesses_covered", "witnesses_asked", "witnesses_robbed"]`. Читает чужие долгие: `book_read`,
группу Малха, группу кладезя. Прочие флаги — флаги ночи.

## 6. Враги

Все замахи — в данных и на картинке (атлас рисует замах, §2 `CHAPTER6_ART.md`). Числа — чуть выше
Сеира (утопленник 44 hp, боцман 170, Сторож 1100).

| id | Кто | Поведение | Атаки (замах, с) | material | Совет |
|---|---|---|---|---|---|
| `flagellant` | Бичующийся: монах во власянице, спина в рубцах, плеть-девятихвостка | `walker`, hp 66, speed 56, aggro 420, essence 18 | плеть сбоку `melee` range 64 reach 92 dmg 14 cd 1,9 (**0,75**: плеть уходит за плечо) · удар сверху `melee` range 80 reach 110 dmg 20 cd 3,4 recover 0,8, `attack_alt` (**1,05**: плеть поднята над головой, хвосты висят) | cloth | `TIP_FLAGELLANT` |
| `censer_monk` | Кадильщик: монах в капюшоне, кадило на цепочке, дым | `caster`, keep_away 150, hp 54, speed 50, aggro 460, essence 20 | ладан `ranged` style **`incense`** (новый) range 320 dmg 11 cd 2,8 speed 140, `projectile_motion` `home` amount 1,2, `volley` 2 gap 0,45 (**0,9**: кадило раскачивается, дым гуще) · облако `nova` trigger_range 70 radius 84 dmg 12 cd 4,5 color `#c8b890`, `special` (**1,2**: кадило над головой, круг дыма на полу) | cloth | `TIP_CENSER_MONK` |
| `chained_penitent` | Прикованный кающийся: босой, ошейник, цепь к кольцу | `walker` + **`tether` {length 130}**, hp 84, speed 60, aggro 380, essence 22; **`freed`** {speed 1,35, damage 1,25, cooldown 0,8} | рывок `lunge` range 190 dmg 17 cd 3,0 lunge_speed 380 lunge_time 0,38 recover 0,9, `attack_alt` (**0,9**: присел, цепь натягивается прямо, звенит) — на конце цепи обрывается, натяжение 0,8 с · удар `melee` range 30 reach 40 dmg 11 cd 1,8 (**0,6**) | flesh | `TIP_CHAINED_PENITENT` |
| `horseman` | Всадник из конницы: тёмный конь, нагрудник цвета огня, гиацинта и серы (тусклые ржавый, сине-чёрный, серно-жёлтый), копьё | `walker`, hp 100, speed 62, armor 0,15, aggro 520, size 16, essence 26 | натиск `lunge` range 320 dmg 22 cd 3,6 lunge_speed 460 lunge_time 0,5 recover 1,0 (**1,1**: конь встаёт на дыбы, копьё опускается) · копьё `melee` range 50 reach 80 dmg 15 cd 2,0 (**0,75**: копьё отведено назад) | plate | `TIP_HORSEMAN` |
| `river_wraith` | Дух реки: серо-зелёный, тянет за собой ил и тростник | `flyer`, hp 46, speed 70, aggro 460, essence 16 (пока `"extends": "wraith"`, `sprite.like` `wraith`, tint `#9fb8a8`) | брызги `ranged` style `wraith` color `#9fc8b8` range 300 dmg 11 cd 2,4 speed 190 (**0,8**: свет в нём собирается, тростник встаёт дыбом) | spirit | `TIP_RIVER_WRAITH` |
| `fettered_angel` | Скованный: малый ангел, крылья связаны, кольцо в стене, холодный свет | `flyer` + **`tether` {length 110}**, hp 76, speed 54, aggro 380, essence 0, light `#cfe6ff`; **`freed`** {`leaves`: true} | свет `beam` range 220 length 200 thickness 18 duration 0,4 dmg 16 cd 3,4 color `#cfe6ff` (**1,0**: крылья натягивают путы, лицо светлеет) · крыло `melee` range 40 reach 56 dmg 12 cd 1,9 (**0,7**) | feather | `TIP_FETTERED_ANGEL` |
| `lion_horse` (**элита**, `tags` `elite`) | Конь с львиной головой: грива-пламя, из пасти дым и сера, хвост — змея с головой | `walker`, hp 280, speed 66, armor 0,1, aggro 500, size 18, essence 60 | огонь из пасти `beam` range 170 length 150 thickness 26 duration 0,6 dmg 20 cd 3,8 color `#ffb050` (**1,0**: голова опущена, в пасти разгорается, дым из ноздрей) · хвост **сзади** `melee` **`"behind": true`** (новое) range 60 reach 80 dmg 18 cd 2,4, `attack_alt` (**0,8**: хвост-змея поднимается над спиной, шипит) · натиск `lunge` range 280 dmg 22 cd 4,0 lunge_speed 420 lunge_time 0,45 recover 1,0, `special` (**1,0**: бьёт копытом) | flesh | `TIP_LION_HORSE` |
| `four_bound` (**босс**, `tags` `boss`, `angel`) | Четверо связанных: четыре ангела с завязанными глазами у четырёх столбов; одно тело в бою (§9) | `walker` + **`tether`** + **`bound_phases`** (новое), hp 1600, speed 58, armor 0,15, stagger 0, aggro 900, size 18, essence 260, ash 20, light `#cfe6ff`; `epithet` `BOSS_EPITHET_FOUR_BOUND` | см. ниже | feather | `TIP_FOUR_BOUND` |

**Четверо: фазы.** Одна полоска здоровья (`boss_hp_changed`). Атаки разведены по фазам `from_hp` /
`until_hp` (уже работает в `_choose_attack`). Цепь бодрствующего — `bound_phases.lengths`; смена — 1,6 с
(тело утягивает к его столбу по цепи, поза `special`; урон проходит, но здоровье не переходит
следующий порог в смене). На конце цепи — натяжение 1,0 с без ударов.

| Фаза | `from_hp` → `until_hp` | Кто | Цепь | Атаки (замах, с) |
|---|---|---|---|---|
| I | 1,0 → 0,75 | **Час**, тон `#dfe8ff` | 170 | удар цепью `melee` range 70 reach 96 dmg 24 cd 2,0 recover 0,6 (**0,85**: цепь наматывается на кулак) · рывок `lunge` range 200 dmg 22 cd 3,0 lunge_speed 420 lunge_time 0,4 recover 0,9, `attack_alt` (**0,9**: цепь выпрямляется) |
| II | 0,75 → 0,5 | **День**, тон `#e8f0ff` | 250 | удар цепью (тот же) · холодный свет `beam` range 420 length 380 thickness 22 duration 0,5 dmg 22 cd 3,6 color `#cfe6ff`, `attack_alt` (**1,1**: повязка на глазах светлеет, луч рисуется заранее) |
| III | 0,5 → 0,25 | **Месяц**, тон `#d8e4f8` | 330 | огни `ranged` style `halo` color `#cfe6ff` range 420 dmg 12 cd 2,6 `projectiles` 3 spread 30, `volley` 2 gap 0,5 (**0,8**: крылья раскрыты, насколько пускают путы) · рывок `lunge` range 300 (**0,9**) |
| IV | 0,25 → 0 | **Год**, тон `#f0f4ff` | 460 | все четыре цепи `nova` trigger_range 110 radius 120 dmg 38 cd 5,0, `special` (**1,4**: трое у столбов рвут цепи разом, пол дрожит) · свет `beam` length 520 thickness 36 dmg 42 cd 5,0 (**1,4**) · удар цепью (**0,85**) |

Советы (ключи `TIP_*`, все говорят правду о JSON):

| Ключ | ru | en |
|---|---|---|
| `TIP_FLAGELLANT` | Плеть достаёт дальше, чем кажется. Ушла за плечо — шаг назад за её конец; поднялась над головой — успеешь войти под руку. | The scourge reaches further than it looks. When it goes back over the shoulder, step past its end; when it rises overhead, you have time to get under the arm. |
| `TIP_CENSER_MONK` | Ладан летит медленно и поворачивает за тобой — уходи кувырком в последний миг. Кадило над головой — дым у ног: отойди. | The incense flies slowly and turns after you — roll away at the last moment. Censer overhead means smoke at his feet: step away. |
| `TIP_CHAINED_PENITENT` | Цепь видна от кольца до ошейника. Стой на шаг дальше — рывок оборвётся, и он постоит в натяжении. Тогда бей. Отпертый ключом — без цепи и злее. | The chain shows from ring to collar. Stand a step beyond it — the lunge stops short and he hangs on the chain. Strike then. Unlocked, he has no chain and more spite. |
| `TIP_HORSEMAN` | Конь встаёт на дыбы — сейчас натиск по прямой. Уйди с линии или перекатись сквозь; после натиска он долго разворачивается. | When the horse rears, a straight charge is coming. Get off the line or roll through it; after the charge he is slow to turn. |
| `TIP_RIVER_WRAITH` | Тростник на нём встаёт перед броском. Бей, когда спускается к тебе, — сверху он почти не двигается. | The reeds on it stand up before it throws. Strike when it comes down to you — up high it hardly moves. |
| `TIP_FETTERED_ANGEL` | Его держит кольцо в стене. Свет бьёт на длину его цепи и чуть дальше — встань сбоку. Отпертый, он не дерётся: он уходит. | A ring in the wall holds it. The light reaches the length of its chain and a little more — stand to the side. Unlocked, it does not fight: it leaves. |
| `TIP_LION_HORSE` | Огонь из пасти — только вперёд и недалеко. Не заходи за спину: хвост — змея, и он поднимается над спиной перед укусом. | The fire from its mouth goes forward and not far. Don't circle behind it: the tail is a serpent, and it rises over the back before it bites. |
| `TIP_FOUR_BOUND` | Держись дальше цепи — она видна от столба. Когда цепь натянута, он стоит в рывке и не бьёт: бей тогда. С каждой четвертью цепь длиннее. | Stay beyond the chain — you can see it from the pillar. When it is taut he hangs on it and cannot strike: hit him then. Each quarter, the chain is longer. |

## 7. Дары, знамения, места отдыха, области

**Дары** — `data/abilities/chapter_6.json`, по два на путь, у каждого `rarity`, все с
`"nights": ["euphrates"]` (`Omens.of_night`: в другие ночи их нет в колоде):

| id | Путь | Редкость | Механика |
|---|---|---|---|
| `kept_vigil` (Отстоянная стража) | благодать | rare | `parry_window` +0,08 (кап 0,15; обычный «Терпение сторожа» — +0,06) |
| `bread_of_the_refectory` (Хлеб трапезной) | благодать | common | `max_hp` +15, `clear_heal` +8 |
| `loosened_chain` (Ослабленная цепь) | соблазн | rare | **новый стат `taut_damage`** +0,6: удар по телу на натянутой цепи (в натяжении) стоит на 60 % больше (кап 1,0; §9) |
| `covet` (Зависть) | соблазн | common | `lifesteal` +0,05 (кап 0,15) |
| `unbound` (Несвязанный) | воля | rare | `dash_cooldown` ×0,65, `speed` ×1,08 (кувырок, а «Быстрые ноги» — бег) |
| `scourged_back` (Иссечённая спина) | воля | common | `wrath_after_hit` +0,35 |

**Знамения** — `data/omens/chapter_6.json`, каждое — сделка, только в ночь `euphrates`:

| id | Правила | Смысл |
|---|---|---|
| `hour_day_month_year` | `promote_chance` 0,25, `promote` {`horseman`: `lion_horse`}, `ash` 1,3 | конница приготовлена к сроку: всадники встают элитой, Пепла больше |
| `seven_thunders` | `enemy_sight` 0,6, `skill_cooldown` 1,4, `ash` 1,25 | в громе никто не слышит: враги видят хуже, но и твой навык молчит дольше |
| `loosed_river` | **новое правило `tether_length`** 1,5, `essence` 1,25 | река ослабила цепи: каждая длиннее в полтора раза, эссенции больше |

**Места отдыха** — `data/rest_points/chapter_6.json`:

| id (комната) | `at` (панель, px) | Что на картине |
|---|---|---|
| `euphrates_refectory` | ≈ [980, 590] | печь для хлеба в правой трети, под ней каменная лавка; на печи — лампада |
| `euphrates_river_stair` | ≈ [640, 360] (средняя площадка) | ниша-киот с масляной лампой и глиняной чашей, вырезанная в сырцовой стене |

**Области** — `data/chapters/chapter_6.json` (`chapter` `CHAPTER_VI`):

| id | title | Комнаты | color | sound |
|---|---|---|---|---|
| `euphrates_bank` | `AREA_EUPHRATES_BANK` | bank | `#a8b8b0` | `bell` |
| `euphrates_town` | `AREA_EUPHRATES_TOWN` | town | `#c8b090` | — |
| `euphrates_abbey` | `AREA_EUPHRATES_ABBEY` | gate, cloister, scriptorium, refectory, bell_tower | `#d8c8a0` | `bell` |
| `euphrates_altar` | `AREA_EUPHRATES_ALTAR` | altar_court, crypt_of_chains, cistern | `#e8c870` | — |
| `euphrates_riverbed` | `AREA_EUPHRATES_RIVERBED` | river_stair, bound | `#cfe6ff` | `bell` |

**Музыка** (только существующие настроения): bank `road`, town `village_night`, gate / cloister /
scriptorium / refectory / altar_court `church`, bell_tower / crypt_of_chains `graveyard`, cistern /
river_stair `dead_bridge`, bound `boss_ophanim`.

**Жидкости**: `water` (существующий вид) — река у берега (комната 1, справа внизу, падение в неё — не
смерть, плавание), цистерна (8б, глубокая), лужи в русле (10, мелкие — тормозят). Новых видов нет.

## 8. Как глава входит в игру

Запись ночи в `data/game.json` `nights` — ровно как в CAMPAIGN §6:

```json
{"id": "euphrates", "after": "engedi", "after_dawns": 5, "opening": {"wake": false}, "rooms": [
  "res://scenes/rooms/euphrates_bank.tscn",
  "res://scenes/rooms/euphrates_town.tscn",
  "res://scenes/rooms/euphrates_gate.tscn",
  "res://scenes/rooms/euphrates_cloister.tscn",
  "res://scenes/rooms/euphrates_scriptorium.tscn",
  "res://scenes/rooms/euphrates_refectory.tscn",
  "res://scenes/rooms/euphrates_bell_tower.tscn",
  "res://scenes/rooms/euphrates_altar_court.tscn",
  "res://scenes/rooms/euphrates_crypt_of_chains.tscn",
  "res://scenes/rooms/euphrates_cistern.tscn",
  "res://scenes/rooms/euphrates_river_stair.tscn",
  "res://scenes/rooms/euphrates_bound.tscn"
]}
```

Пока E3 (`after`) не влит, работает `after_dawns`. Плюс `flags_kept` (§5).

Файлы:

- `data/enemies/`: `flagellant`, `censer_monk`, `chained_penitent`, `horseman`, `river_wraith`,
  `fettered_angel`, `lion_horse`, `four_bound` (.json); их ряды в `data/enemy_archetypes/tree.json`.
- `data/projectiles.json` — стиль `incense` (§9).
- `data/props/chain.json` (новый вид пропа, §9), `euphrates_cache_*.json` ×3,
  `secret_wall_euphrates_gate.json` / `_bell.json` / `_stair.json`.
- `data/npcs/`: `saul`, `euphrates_reveller` (scripted), `witness_left` / `witness_right` (scripted,
  лежат), `malchus_far` (scripted; тело — лист Малха из главы III).
- `data/dialogues/ch6.json`: `fork_euphrates_cloister`, `fork_euphrates_depth`, `ch6_little_book`,
  `ch6_witnesses`, `npc_saul`, `ch6_refectory`, `ch6_horns`, `ch6_bound`, `ch6_bound_fall`,
  `ch6_finale_*`, `note_chain_roll`, `note_seven_thunders`, `note_novice_envy`.
- `data/cutscenes/`: `little_book`, `witnesses_in_the_street`, `refectory_arrival`,
  `voice_from_the_horns`, `the_four_bound`, `ch6_finale`.
- `data/forks/chapter_6.json`, `data/rest_points/chapter_6.json`, `data/chapters/chapter_6.json`,
  `data/notes/ch6_notes.json`; `data/dialogue_looks.json` `speakers` для `SPEAKER_SAUL`,
  `SPEAKER_MIGHTY_ANGEL`, `SPEAKER_HORNS` (без портрета), `SPEAKER_BOUND_HOUR` / `_DAY` / `_MONTH` /
  `_YEAR`, `SPEAKER_REVELLER`.
- `data/abilities/chapter_6.json`, `data/omens/chapter_6.json`; `drafts/chapter_6/rooms.json` (план).
- `tools/rooms/painted_rooms.py` — 11 таблиц `euphrates_*`; `tools/rooms/composed_rooms.json` —
  `euphrates_bell_tower` (1×2, `"live": true`); `FOCAL_RANGES`, `data/backdrops.json`,
  `RoomLayers.FAR_WINDOWS`, `<id>.lights.json` — по `CHAPTER6_ART.md`.
- `localization/strings.csv` — §10 и все ключи имён/описаний, 4 колонки.

Тесты, которые должны пройти:
`validate_data.gd` · `reach_test.gd -- euphrates_<id>` по каждой комнате (кольца `chain` и тайники —
достижимы) · `stairs_test.gd` · `void_fall_test.gd` · `exits_test.gd` · `smoke_test.gd` (проходит ночь
`euphrates`) · `tether_test.gd` (новый, §9) · `kept_flags_test.gd` (E1: долгие флаги главы) ·
`gift_test.gd` (`taut_damage`) · `omen_test.gd` (`tether_length`) · `elite_cache_test.gd`,
`variants_test.gd` (`river_wraith` пока вариант) · `backdrop_life_test.gd`.

## 9. Чего не хватает (код)

Общие крючки — по несколько строк в `enemy.gd`, `player.gd`, `prop.gd`, `validate_data.gd`; всё новое — в
`scripts/enemies/tether.gd` (CAMPAIGN §8).

1. **`scripts/enemies/tether.gd`** (`class_name Tether`, узел-ребёнок врага с ключом `"tether"`):
   - `"tether": {"length": px, "anchor": [x, y]?, "strain": s?}`; якорь — `anchor` (пиксели комнаты,
     `room.to_global`), иначе ближайший проп `chain` в `ANCHOR_SNAP` = 48 px, иначе точка появления.
   - Хозяин (`_simulated`): после `move_and_slide` в `Enemy._physics_process` — `_tether.hold(self)`:
     если расстояние > длины — тело на окружность, исходящая составляющая скорости — 0. Ходок
     держится пола (только по x), летун — по кругу.
   - Преследование: цель `_chase` / `_keep_distance` зажимается в круг цепи; если игрок дальше
     длины + досягаемости — тело встаёт **в натяжении** (`State.STRAIN` или флаг поверх `HOLD`):
     поза `strain` → `special` → `hurt`, звук `chain_strain` (через `MIX`), без ударов, `strain` с
     (по умолчанию 0,6, у прикованного 0,8, у босса 1,0); дальнобойные атаки работают и из натяжения.
   - Лунж: в `_physics_process` в STRIKE лунж обрывается на конце цепи (`chain_snap`,
     `Juice.shake(2)`), затем натяжение. Замах лунжа выпрямляет цепь (Line2D от провисшей к прямой,
     светлеет) — читаемый.
   - `is_taut()` — для `taut_damage` и совета.
   - Цепь рисуется каждым пиром (Line2D, 8 точек, провис по запасу, железо `#5a5a62`, блик), z как у
     тела; позиция и так синхронна. `Net.attach_sync` — свойство `tethered` (bool).
   - Знамение: длина × `Vials.rules().get("tether_length", 1.0)`.
2. **`Enemy.loose()`** (хозяин; онлайн — `_net_loose` рядом с `_net_strike`): снять цепь, наложить
   `"freed"` {`speed`, `damage`, `cooldown` — множители} и сразу `aware`; `freed.leaves` — тело
   уходит вверх (`appear`-подобный твин 1,2 с, `Fx.sparkle`), ни эссенции, ни счёта, и **Room
   перестаёт его ждать** (`Room.holds_door` — как ждущего; `EventBus.enemy_left` или флаг
   `left` перед `queue_free`). Ставит `Game.flags.chain_opened`, для `leaves` — и `fettered_freed`
   (`FLAGS_SET_IN_CODE`); `Profile.count("chains_opened")` (не во дворе).
3. **Проп `chain`** (`scripts/props/prop.gd`, `kind: "chain"`, `data/props/chain.json`): кольцо в
   стене/полу (`assets/props/chain_ring.png`, 3 кадра: висит, искра, открыто), не коллайдер.
   - Удар без ключей — звон (`block`), искры, ничего не рвётся. **Решение:** цепь отпирают только
     ключи (`"opens_with": "saul_keys"` — валидатор читает как чтение флага). Иначе её рвали бы
     случайно — автоатака, подсечка, удар по прикованному рядом с кольцом, — и отпустить стало бы
     побочным эффектом боя, а не выбором; CAMPAIGN §4 говорит «разорванная по выбору (ключи аввы)».
   - С ключами — группа `interactable`, подсказка `PROMPT_UNLOCK_CHAIN` над кольцом (E / тач-кнопка
     разговора, как проклятый сундук); E → хозяин `loose()` прикованного к этому кольцу; онлайн
     открывший шлёт `_net_open`. Открытое кольцо — кадр 3, цепь лежит.
   - Кольца в бою у Четверых не отпираются: у столбов нет пропа `chain` (якорь — `bound_phases`).
4. **`"bound_phases"`** у босса (в `tether.gd`, по образцу `seal_phase` Офанима):
   `{"anchors": {"euphrates_bound": [[x,y]×4], "practice_yard": [...]}, "lengths": [170,250,330,460],
   "at_hp": [0.75, 0.5, 0.25], "tints": [...], "speakers": [...], "swap": 1.6}`.
   - Одно `Enemy` — одна полоска, один `_die`, одно `fight_time`; **решение**: это меньше нового кода,
     чем четыре врага (не надо делить полоску, держать дверь четверыми и учить `boss_hp_changed`
     сумме).
   - Хозяин: при переходе порога — смена (1,6 с: тело тянет к его столбу по цепи, поза `special`;
     урон проходит, но `hp` не опускается ниже следующего порога, пока идёт смена), затем тело —
     у следующего столба (позиция синхронна), якорь и длина цепи — новые, тон — новый, `Fx.flash`
     холодный, звук `boss_ophanim` −6 дБ. Синхронное свойство `phase` (int).
   - **Трое у столбов** — не тела: каждый пир по `phase` кладёт три `Sprite2D` с теми же
     `SpriteFrames` (поза `special` по кругу, тон, `modulate` 0,8) и их цепи (Line2D к своему столбу,
     натянуты). Нет коллайдеров, нет урона.
   - Атаки фаз — `from_hp` / `until_hp` (уже есть). Двор (`practice_yard`): свои `anchors`.
5. **Ближний удар `"behind": true`** (хвост `lion_horse`): `_in_attack_range` — цель **за спиной**;
   `_melee_hit` — прямоугольник удара с обратной стороны; поворота к цели перед ударом нет.
   Валидатор: bool, только у `melee`. Тест — в `tether_test.gd` (или `variants_test.gd`).
6. **Стат `taut_damage`** (дар `loosened_chain`): `Player.BASE_STATS` 0, `STATS` в валидаторе,
   `AbilitySystem.CAPS` [0, 1.0], в `_land_hits`: `if target is Enemy and target.is_taut(): damage *= 1
   + stats.taut_damage`; проверка в `gift_test.gd`.
7. **Правило знамения `tether_length`** (`loosed_river`): `Vials.rules` перемножает; валидатор —
   1,0…2,0; `omen_test.gd`.
8. **Стиль снаряда `incense`** (`data/projectiles.json`): полоса `incense_flight_v3.png` (4 кадра
   96×128, клуб дыма с тлеющей крупицей), `scale` 0,8, `fps` 6, `light` тусклый тёплый `#e8c890`
   radius 22, `trail` дым, `breathe` 0,15, `bob` 3; `burst` — облачко. Валидатор требует анимированный
   `projectile_style` у дальней атаки — он будет.
9. **Звуки**: `chain_strain` (3 дубля), `chain_snap` (3), `chain_unlock` (2), `censer_swing` (3),
   `thunder` (3, если нет), голоса `<id>_hurt` / `_death` новым врагам — `generate_voices.py`; CC0
   дубли — `sfx_manifest.json` → `fetch_sfx.py`. Строки `MIX` в `audio.gd`, кредиты.
10. **`tether_test.gd`** (новый): прикованный не уходит дальше длины (ходок и летун); лунж обрывается
    на конце цепи и тело стоит в натяжении ≥ `strain`; удар по натянутому с `taut_damage` больше; проп
    `chain` без `saul_keys` не отпирается и не теряет вида от удара; с флагом — отпирает, `freed`
    множители легли, `aware`, `chain_opened` стоит; `leaves` — тело ушло, дверь его не ждёт,
    `fettered_freed`; `bound_phases` — на 0,75 / 0,5 / 0,25 якорь и длина сменились, `hp` не
    перескочил порог в смене, трое у столбов есть у клиента; `behind` бьёт за спину и не бьёт вперёд;
    `tether_length` знамения удлиняет цепь.
11. **Сцены**: новых шагов нет (`sound`, `flash`, `camera` к точке, `appear` / `walk` / `vanish`,
    `presence`, `dialogue`, `title`). Если камере у Четверых нужна точка столба по имени — достаточно
    `[x, y]`.

**Общий движок.** Глава **зависит** от E1 (`flags_kept`, `Profile.data.kept` — делает глава III):
`scroll_eaten`, группы свидетелей и ангелов пишутся, `book_read` и группы Малха и кладезя читаются.
Пока E1 нет, тесты кладут флаги руками (`Game.flags[...] = true`). E3 (`after`) — от главы III; до него
работает `after_dawns: 5`. E2 и E4 (глава VII) читают то, что эта глава оставляет; глава не владеет ни
одним из E1–E4.

## 10. Тексты

Ключи `DLG_CH6_*` (диалоги, подписи, записи), прочие — как у глав I–II. ru и en; uk и zh_CN — сессия
сборки.

### Развилки, области, говорящие

| Ключ | ru | en |
|---|---|---|
| `DLG_FORK_EUPHRATES_CLOISTER` | Галерея под открытым небом — или переписная, где тихо? | The open cloister — or the scriptorium, where it is quiet? |
| `DLG_FORK_EUPHRATES_CLOISTER_CLOISTER` | Через галерею. | Through the cloister. |
| `DLG_FORK_EUPHRATES_CLOISTER_SCRIPTORIUM` | Через переписную. | Through the scriptorium. |
| `DLG_FORK_EUPHRATES_DEPTH` | Вниз — туда, где цепи, или туда, где вода? | Down — where the chains are, or where the water is? |
| `DLG_FORK_EUPHRATES_DEPTH_CRYPT` | Туда, где цепи. | Where the chains are. |
| `DLG_FORK_EUPHRATES_DEPTH_CISTERN` | Туда, где вода. | Where the water is. |
| `CHAPTER_VI` | Глава VI — Шестая труба | Chapter VI — The Sixth Trumpet |
| `CHAPTER_VI_END` | Обитель осталась на реке | The abbey stayed on the river |
| `AREA_EUPHRATES_BANK` / `_SUB` | Берег великой реки / Ангел стоит одной ногой на воде | The bank of the great river / An angel stands with one foot on the water |
| `AREA_EUPHRATES_TOWN` / `_SUB` | Город у брода / Сегодня все дарят друг другу подарки | The town at the ford / Tonight everyone gives everyone gifts |
| `AREA_EUPHRATES_ABBEY` / `_SUB` | Обитель / Сорок лет одной молитвы | The abbey / Forty years of one prayer |
| `AREA_EUPHRATES_ALTAR` / `_SUB` | Двор алтаря / Четыре рога из золота | The altar court / Four horns of gold |
| `AREA_EUPHRATES_RIVERBED` / `_SUB` | Русло / Где реку держат молитвой | The riverbed / Where a river is held by prayer |
| `SPEAKER_MIGHTY_ANGEL` | Ангел с книжкой | The angel with the little book |
| `SPEAKER_REVELLER` | Пирующий | Reveller |
| `SPEAKER_SAUL` / `NPC_SAUL` | Авва Саул | Abba Saul |
| `SPEAKER_HORNS` | Голос от рогов | A voice from the horns |
| `SPEAKER_BOUND_HOUR` | Час | The Hour |
| `SPEAKER_BOUND_DAY` | День | The Day |
| `SPEAKER_BOUND_MONTH` | Месяц | The Month |
| `SPEAKER_BOUND_YEAR` | Год | The Year |
| `PROMPT_UNLOCK_CHAIN` | Отомкнуть | Unlock |

### Книжка (`ch6_little_book`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_BOOK_1` | Ты, кого не берёт смерть. Подойди к воде. | You, whom death will not take. Come down to the water. |
| `DLG_CH6_BOOK_2` | Что у тебя в руке? | What is in your hand? |
| `DLG_CH6_BOOK_3` | Книжка. В ней всё, что о тебе сказали. | A little book. Everything that was said about you is in it. |
| `DLG_CH6_BOOK_THUNDER` | (гром — семь раз) Что он сказал? | (thunder — seven times) What did it say? |
| `DLG_CH6_BOOK_SEAL` | Запечатай. Это сказано не тебе. | Seal it up. That was not said to you. |
| `DLG_CH6_BOOK_4` | Возьми её и съешь. | Take it, and eat it. |
| `DLG_CH6_BOOK_EAT` | Съесть. | Eat it. |
| `DLG_CH6_BOOK_ASK` | Что в ней обо мне? | What does it say about me? |
| `DLG_CH6_BOOK_REFUSE` | Я уже читал одну. | I have read one already. |
| `DLG_CH6_BOOK_EAT_1` | Сладко. Здесь всё: что я держал дверь. Что я спросил. Что меня назвали. Всё — сладкое. | Sweet. It is all here: that I held a door. That I asked. That I was named. All of it sweet. |
| `DLG_CH6_BOOK_EAT_2` | Теперь — во чрево. | Now let it go down. |
| `DLG_CH6_BOOK_EAT_3` | …Горько. И последней страницы нет. | …Bitter. And there is no last page. |
| `DLG_CH6_BOOK_EAT_4` | Её не было никогда. | There never was one. |
| `DLG_CH6_BOOK_ASK_1` | Всё, что сказали. И всё правда — пока во рту. | Everything they said. And all of it true — while it is in your mouth. |
| `DLG_CH6_BOOK_ASK_2` | А потом? | And after? |
| `DLG_CH6_BOOK_ASK_3` | Ты спросил, а не съел. Тебе нужен пересказ, а не вкус. Ступай. | You asked instead of eating. You wanted it retold, not tasted. Go. |
| `DLG_CH6_BOOK_REFUSE_READ` | Ту, под алтарём. Красная строка, чужая рука. Эта тоже о тебе — и тоже писана не тобой. | The one under the altar. A red line, another's hand. This one is about you too — and not written by you either. |
| `DLG_CH6_BOOK_REFUSE_READ_2` | Тем более. | All the more reason. |
| `DLG_CH6_BOOK_REFUSE_UNREAD` | Нет. Ты слышал одну — свой приговор. Его читали вслух. | No. You heard one — your sentence. It was read aloud. |
| `DLG_CH6_BOOK_REFUSE_UNREAD_2` | Мне хватило. | That was enough for me. |

### Свидетели (`ch6_witnesses`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_WIT_1` | Эй, мёртвый! Садись к столу. Сегодня всем подарки — у города радость. | Hey, dead man! Sit down at the table. Gifts for everyone tonight — the town is glad. |
| `DLG_CH6_WIT_2` | Чья радость? | Whose gladness? |
| `DLG_CH6_WIT_3` | Наша. Видишь этих двоих? Пророки. Три года с половиной ни капли дождя — и каждый день слово. Теперь лежат. | Ours. See those two? Prophets. Three years and a half without a drop of rain — and a word from them every day. Now they lie there. |
| `DLG_CH6_WIT_4` | Хоронить их не велено. Пусть все видят. | No one is to bury them. Let everyone see. |
| `DLG_CH6_WIT_5` | На шее — след верёвки. Как у меня. | A rope mark on the neck. Like mine. |
| `DLG_CH6_WIT_6` | Ну? Бери подарок, все берут. | Well? Take a gift, everyone does. |
| `DLG_CH6_WIT_COVER` | Укрыть их. | Cover them. |
| `DLG_CH6_WIT_ASK` | Кто их повесил? | Who hanged them? |
| `DLG_CH6_WIT_ROB` | Взять дар с их груди. | Take the gift from their chests. |
| `DLG_CH6_WIT_COVERED_1` | Укрыл. Зачем? Им уже не стыдно. | Covered them. What for? They are past shame. |
| `DLG_CH6_WIT_COVERED_2` | А мне — стыдно. | I am not past it. |
| `DLG_CH6_WIT_ASKED_SCAR` | Человек с рубцом на ухе. Пришёл с бродов, сделал своё и ушёл. Платы не взял. | A man with a scar on his ear. Came up from the fords, did his work and left. Took no pay. |
| `DLG_CH6_WIT_ASKED_OTHER` | Того, кто вешал у бродов, говорят, самого повесили. Нашёлся другой. Верёвка всегда находит руки. | The one who hanged men at the fords was hanged himself, they say. Another turned up. A rope always finds hands. |
| `DLG_CH6_WIT_ROBBED_1` | Вот! Наш человек. Пей за их здоровье. | There! One of us. Drink to their health. |
| `DLG_CH6_WIT_ROBBED_2` | На груди у него лежала фляга. Чужая. Ещё тёплая. | There was a flask on his chest. Someone else's. Still warm. |

### Трапезная и авва Саул (`ch6_refectory`, `npc_saul`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_REFECTORY` | Стол накрыт на сорок. Хлеб не тронут. Под полом звенит цепь. | The table is laid for forty. The bread is untouched. Under the floor a chain rings. |
| `DLG_SAUL_HABIT_GRACE` | Опять ты. Третью ночь приходишь с тем же светом на лице. Я бы позавидовал — да устал. | You again. The third night you come with the same light on your face. I would envy it, if I were not tired. |
| `DLG_SAUL_HABIT_TEMPTATION` | Опять ты. И опять пахнешь чужим — третью ночь. Что ты у них берёшь? | You again. And again you smell of other people's things — the third night. What do you take from them? |
| `DLG_SAUL_HABIT_WILL` | Опять ты — ни с ними, ни с нами. Третью ночь. Внизу тебе завидуют: я слышу по цепям. | You again — with neither them nor us. The third night. Down below they envy you: I can hear it in the chains. |
| `DLG_SAUL_EATEN` | Ты ел из рук ангела. Я сорок лет прошу у него страницу — он не смотрит в мою сторону. | You ate from an angel's hand. Forty years I have asked him for one page — he does not look my way. |
| `DLG_SAUL_ROLL` | Ты читал свиток у ворот. Моё имя — последнее. Под ним осталось место. Для кого — не знаю. | You read the roll at the gate. My name is the last. There is room left under it. Whose, I do not know. |
| `DLG_SAUL_1` | Ешь. Хлеб здесь не горький — горечь мы отдаём реке. | Eat. The bread here is not bitter — we give the bitterness to the river. |
| `DLG_SAUL_2` | Под нами, в русле, четверо. Мой отец держал их молитвой. Его отец. Теперь я. Сорок лет. | Beneath us, in the riverbed, are four. My father held them with prayer. His father. Now I do. Forty years. |
| `DLG_SAUL_3` | Знаешь, каково стеречь тех, кто ближе к Нему, чем ты будешь когда-нибудь? Их хоть держит Он. | Do you know what it is to guard those who are nearer to Him than you will ever be? At least He is the one who holds them. |
| `DLG_SAUL_ASK` | Ты пойдёшь вниз. Что скажешь мне на дорогу? | You will go down. What will you say to me before you go? |
| `DLG_SAUL_OBEY` | Пусть их стерегут и дальше. | Let them go on being guarded. |
| `DLG_SAUL_ENVY` | Чему ты завидуешь — их цепям? | What do you envy — their chains? |
| `DLG_SAUL_KEYS` | Где ключи от цепей? | Where are the keys to the chains? |
| `DLG_SAUL_OBEY_REPLY` | Да. Пусть. Кто-то должен стоять ниже их, чтобы они оставались наверху. | Yes. Let them. Someone has to stand below them, so that they stay above. |
| `DLG_SAUL_ENVY_REPLY` | …Их держит Бог. Меня держу только я. Иди. | …God holds them. Only I hold me. Go. |
| `DLG_SAUL_KEYS_REPLY` | На поясе. Сорок лет на поясе. Бери. Посмотрим, кто из нас первым пожалеет. | On my belt. Forty years on my belt. Take them. We will see which of us is sorry first. |
| `DLG_SAUL_KEYS_REPLY_2` | От тех, что в русле, ключей нет. Эти — от наших. | There are no keys to the ones in the riverbed. These are for ours. |
| `NPC_SAUL_LINE_1` | Хлеб на столе. Цепи под столом. Так и живём. | Bread on the table. Chains under it. That is how we live. |
| `NPC_SAUL_LINE_2` | Внизу не молись вслух. Они слушают. | Don't pray aloud down there. They listen. |

### Голос от рогов (`ch6_horns`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_HORNS_1` | Развяжи четверых, что связаны у великой реки. | Loose the four who are bound at the great river. |
| `DLG_CH6_HORNS_2` | Кто говорит? | Who is speaking? |
| `DLG_CH6_HORNS_3` | От рогов. | From the horns. |
| `DLG_CH6_HORNS_4` | Ты — Он? | Are you Him? |
| `DLG_CH6_HORNS_5` | Ты спрашиваешь у золота, кто в нём говорит. | You are asking gold who speaks in it. |
| `DLG_CH6_HORNS_6` | Их приготовили. Час назначен. Остались только руки. | They were made ready. The hour is set. All that is left is hands. |
| `DLG_CH6_HORNS_7` | Почему не сам? | Why not yourself? |
| `DLG_CH6_HORNS_8` | Голосу всегда нужны руки. Монахи слышат меня сорок лет. Слушаться — не слушаются. | A voice always needs hands. The monks have heard me for forty years. Obey — they do not. |
| `DLG_CH6_HORNS_EATEN` | Тебе горько во чреве. Хорошо. Значит, не будешь спешить. | It is bitter in your belly. Good. Then you will not hurry. |
| `DLG_CH6_HORNS_THUNDERS` | Ты нашёл запечатанное. Не читай. Даже я не читаю. | You found what was sealed. Don't read it. Even I do not. |

### Четверо (`ch6_bound`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_BOUND_HOUR` | Ещё один пришёл посмотреть на связанных. Монахи приходят каждую ночь. Ты — первый, кто умер. | Another one come to look at the bound. The monks come every night. You are the first who has died. |
| `DLG_CH6_BOUND_DAY` | Нас приготовили на час, и день, и месяц, и год. Нам сказали когда. Вам не говорят. Вам можно не знать. | We were made ready for an hour, and a day, and a month, and a year. We were told when. You are not told. You are allowed not to know. |
| `DLG_CH6_BOUND_MONTH` | Вас прощают. Нас — исполняют. | You are forgiven. We are carried out. |
| `DLG_CH6_BOUND_ELIAN_1` | А падший? Тот, первый? | And the fallen one? The first? |
| `DLG_CH6_BOUND_YEAR` | Он единственный из нас, кто выбрал. | He is the only one of us who chose. |
| `DLG_CH6_BOUND_KEY_KEPT` | У тебя на поясе ключ глубже наших цепей. Чего ты ждёшь от нас? | You have a key on your belt that goes deeper than our chains. What do you want from us? |
| `DLG_CH6_BOUND_KEY_THROWN` | Ты бросил ключ от бездны. Мы слышали, как он падал. Отсюда далеко слышно. | You threw away the key to the pit. We heard it fall. Sound carries far down here. |
| `DLG_CH6_BOUND_PIT_LOCKED` | Ты запер кладезь. Значит, и ты умеешь держать. | You locked the pit. So you know how to hold, too. |
| `DLG_CH6_BOUND_CHAIN_OPENED` | Ты отпирал цепи наверху. Отпертые — сильнее. Ты это видел. Запомни. | You unlocked chains up there. The unlocked are stronger. You saw it. Remember. |
| `DLG_CH6_BOUND_FETTERED` | Один из наших ушёл вверх по реке. Не обернулся. Мы бы тоже не обернулись. | One of ours went up the river. He did not look back. Neither would we. |
| `DLG_CH6_BOUND_NOVICE` | Мальчик, что спускался, хотел нашу цепь себе. Её ему не дали. Ему дали чётки. | The boy who came down wanted our chain for himself. They did not give it to him. They gave him a rosary. |
| `DLG_CH6_BOUND_ELIAN_2` | Я не держу вас. | I am not the one holding you. |
| `DLG_CH6_BOUND_YEAR_2` | Никто не держит. Держат молитвы. Их хватает до рассвета. Подойди — узнаешь длину цепи. | No one holds us. Prayers do. They last until dawn. Come closer — you will learn the length of the chain. |
| `BOSS_EPITHET_FOUR_BOUND` | Приготовленные на час, и день, и месяц, и год | Made ready for the hour, and the day, and the month, and the year |
| `DLG_CH6_BOUND_SWAP_DAY` | Мой черёд. | My turn. |
| `DLG_CH6_BOUND_SWAP_MONTH` | Цепь длиннее. Ты заметил? | The chain is longer. Did you notice? |
| `DLG_CH6_BOUND_SWAP_YEAR` | Год — это долго. Для тебя. | A year is a long time. For you. |

(Строки смены — подписи `"blocking": false`, по шагу на фазу; если сессия решит, что в бою они
мешают — убрать, бой от них не зависит.)

### После боя и финал (`ch6_bound_fall`, `ch6_finale_*`)

| Ключ | ru | en |
|---|---|---|
| `DLG_CH6_FALL_1` | Ты нас одолел. Цепи — нет. | You have beaten us. Not the chains. |
| `DLG_CH6_FALL_2` | Что мне с вами делать? | What am I to do with you? |
| `DLG_CH6_FALL_KEEP` | Оставить их связанными. | Leave them bound. |
| `DLG_CH6_FALL_LOOSE` | Отпустить. | Let them go. |
| `DLG_CH6_FALL_MEN` | Пусть решат люди. | Let the people decide. |
| `DLG_CH6_FALL_KEEP_REPLY` | Значит, ещё ночь. Ещё одну мы умеем. | Another night, then. One more we know how to do. |
| `DLG_CH6_FALL_LOOSE_REPLY` | Ты не спросил, на что нас приготовили. | You did not ask what we were made ready for. |
| `DLG_CH6_FALL_MEN_REPLY` | Им? Они сорок лет не могут решить, кому из них стоять у цепи. | Them? For forty years they have not decided which of them stands by the chain. |
| `DLG_CH6_FINALE_KEPT` | Наверху снова запели. Молитва легла на цепи, как вода на камень. Четверо смотрели мне вслед — так монахи смотрят на них. | Up above they began to sing again. The prayer lay on the chains like water on stone. The four watched me go — the way the monks watch them. |
| `DLG_CH6_FINALE_LOOSED` | Цепи ушли в воду без звука. Они пошли вверх по реке — на час, на день, на месяц, на год. Я не знаю, какой из них сегодня. | The chains slid into the water without a sound. They went up the river — for an hour, a day, a month, a year. I don't know which of them is today. |
| `DLG_CH6_FINALE_MEN` | Я поднялся и сказал монахам, где лежат цепи и чем держатся. Утром у входа в русло стояли все. Никто не спускался первым. | I went up and told the monks where the chains lay and what held them. In the morning they all stood at the way down to the riverbed. No one went first. |
| `DLG_CH6_FINALE_WITNESSES` | Через три дня с половиной, говорят, они встали. На улице, при всех. Люди уронили свои подарки. | After three days and a half, they say, the two stood up. In the street, in front of everyone. People dropped their gifts. |
| `DLG_CH6_FINALE_LIKE_YOU` | Они встали. Как ты. | They stood up. Like you. |
| `DLG_CH6_FINALE_WIT_COVERED` | Плащ, которым я их укрыл, нашли на мостовой. Сложенным. | The cloak I covered them with was found on the cobbles. Folded. |
| `DLG_CH6_FINALE_WIT_ASKED` | Я спросил, кто их повесил. Никто не спросил, кто их поднял. | I asked who hanged them. No one asked who raised them. |
| `DLG_CH6_FINALE_WIT_ROBBED` | Фляга с их груди у меня. Они о ней не спросили. Это хуже. | I still have the flask from their chest. They never asked about it. That is worse. |
| `DLG_CH6_FINALE_SAUL_OBEYED` | Авва Саул молился до утра громче всех — чтобы внизу слышали, кто их держит. | Abba Saul prayed until morning, louder than anyone — so they would hear below who was holding them. |
| `DLG_CH6_FINALE_SAUL_ASKED` | Саул больше не спускался к реке. Говорят, он уснул — впервые за сорок лет. | Saul did not go down to the river again. They say he slept — for the first time in forty years. |
| `DLG_CH6_FINALE_SAUL_KEYS` | Пояс аввы пуст. Он смотрит на меня так, как смотрел на них. | The abba's belt is empty. He looks at me the way he looked at them. |
| `DLG_CH6_FINALE_SCROLL` | Во рту до сих пор сладко. Во чреве — горько. Последней страницы так и нет. | My mouth is still sweet. My belly is still bitter. There is still no last page. |
| `DLG_CH6_FINALE_SCROLL_ASKED` | Мне пересказали, что обо мне написано. Вкуса я так и не узнал. | I was told what is written about me. I never learned how it tastes. |
| `DLG_CH6_FINALE_SCROLL_REFUSED` | Книжка осталась у ангела. Пусть читает её сам. | The little book stayed with the angel. Let him read it himself. |
| `DLG_CH6_FINALE_GRACE` | Над рекой рассвело, как светает над теми, кто стоял на страже: медленно и без благодарности. | Dawn came over the river the way it comes for those who kept watch: slowly, and without thanks. |
| `DLG_CH6_FINALE_TEMPTATION` | Вода ушла чуть ниже по берегу. Как будто река тоже кого-то отпустила. | The water drew back a little down the bank. As if the river had let someone go too. |
| `DLG_CH6_FINALE_WILL` | Никто не держал меня этой ночью. Ни цепь, ни молитва. Я шёл сам — и завидовать мне было нечему. | No one held me that night. No chain, no prayer. I walked by myself — and there was nothing in me to envy. |

### Записи (`note_*`)

| Ключ | ru | en |
|---|---|---|
| `NOTE_CHAIN_ROLL` | Свиток стражей цепей | The roll of the chain-keepers |
| `DLG_CH6_NOTE_ROLL_1` | «Брат Иов — сорок лет у цепи. Брат Иофам — тридцать один. Кис — сорок четыре». | "Brother Job — forty years at the chain. Brother Jotham — thirty-one. Kish — forty-four." |
| `DLG_CH6_NOTE_ROLL_2` | «Саул, сын Киса — …» Лет не вписано. | "Saul, son of Kish — …" The years are not filled in. |
| `DLG_CH6_NOTE_ROLL_3` | Под последним именем — пустая строка, разлинованная заранее. | Under the last name, an empty line, ruled in advance. |
| `NOTE_SEVEN_THUNDERS` | Запечатанный лист | The sealed page |
| `DLG_CH6_NOTE_THUNDERS_1` | Лист пергамента, вырезанный из переплёта. Чистый. Посредине — печать, целая. | A leaf of parchment cut from a binding. Blank. In the middle, a seal, unbroken. |
| `DLG_CH6_NOTE_THUNDERS_2` | Края обуглены, будто его держали у молнии. На полях — следы пальцев: кто-то держал его очень долго и не сломал. | The edges are scorched, as if it had been held up to lightning. Fingermarks in the margins: someone held it a very long time, and did not break it. |
| `NOTE_NOVICE_ENVY` | Письмо послушника | A novice's letter |
| `DLG_CH6_NOTE_NOVICE_1` | «Авва, я спускался к ним ночью. Они светятся — холодно, как вода зимой». | "Abba, I went down to them at night. They shine — cold, like water in winter." |
| `DLG_CH6_NOTE_NOVICE_2` | «Я завидую их цепи. Её держит Он. Меня не держит никто, кроме вас». | "I envy their chain. He holds it. No one holds me but you." |
| `DLG_CH6_NOTE_NOVICE_3` | «Если найдёте это — я внизу. Не ищите меня у цепей. Ищите там, где цепь кончается». | "If you find this, I am below. Don't look for me by the chains. Look where the chain ends." |

### Враги, дары, знамения

| Ключ | ru | en |
|---|---|---|
| `ENEMY_FLAGELLANT` / `_LORE` | Бичующийся / Бьёт себя за то, что не ангел. Других — за то же. | Flagellant / He whips himself for not being an angel. Others, for the same. |
| `ENEMY_CENSER_MONK` / `_LORE` | Кадильщик / Курит ладан над цепями, чтобы Он видел дым и не видел лиц. | Censer monk / He burns incense over the chains so that He sees smoke and not faces. |
| `ENEMY_CHAINED_PENITENT` / `_LORE` | Прикованный / Сам попросил цепь — чтобы быть как те, внизу. | Chained penitent / He asked for the chain himself — to be like the ones below. |
| `ENEMY_HORSEMAN` / `_LORE` | Всадник / Один из двухсот миллионов. Ждал часа так долго, что забыл, чей он. | Horseman / One of two hundred million. He waited so long for the hour he forgot whose he is. |
| `ENEMY_RIVER_WRAITH` / `_LORE` | Дух реки / То, что Евфрат унёс и не донёс до моря. | River wraith / What the Euphrates took and never carried to the sea. |
| `ENEMY_FETTERED_ANGEL` / `_LORE` | Скованный / Малый ангел у кольца. Не знает, за что. Ему не сказали — ему не нужно. | Fettered angel / A lesser angel at a ring. He does not know why. He was not told — he does not need to be. |
| `ENEMY_LION_HORSE` / `_LORE` | Конь с львиной головой / Сила его в пасти и в хвосте. Хвост помнит больше, чем голова. | Lion-headed horse / Its power is in its mouth and in its tail. The tail remembers more than the head. |
| `ENEMY_FOUR_BOUND` / `_LORE` | Четверо связанных / Их приготовили к сроку и забыли сказать, что срок можно не ждать. | The Four Bound / They were made ready for a set time, and no one told them a time can go unmet. |
| `ABILITY_KEPT_VIGIL_NAME` / `_DESC` | Отстоянная стража / Окно парирования шире. | Kept Vigil / The parry window is wider. |
| `ABILITY_BREAD_OF_THE_REFECTORY_NAME` / `_DESC` | Хлеб трапезной / Больше здоровья; зачищенная комната немного лечит. | Bread of the Refectory / More health; a cleared room heals a little. |
| `ABILITY_LOOSENED_CHAIN_NAME` / `_DESC` | Ослабленная цепь / Удар по тому, чья цепь натянута, на 60 % тяжелее. | Loosened Chain / Blows on anyone whose chain is taut land 60% harder. |
| `ABILITY_COVET_NAME` / `_DESC` | Зависть / Часть нанесённого урона возвращается здоровьем. | Covet / A share of the damage you deal comes back as health. |
| `ABILITY_UNBOUND_NAME` / `_DESC` | Несвязанный / Быстрее бег, короче откат кувырка. | Unbound / Faster on your feet, and the roll comes back sooner. |
| `ABILITY_SCOURGED_BACK_NAME` / `_DESC` | Иссечённая спина / После раны следующий удар тяжелее. | Scourged Back / After a wound, your next blow lands harder. |
| `OMEN_HOUR_DAY_MONTH_YEAR` / `_DESC` | Час, и день, и месяц, и год / Конница готова к сроку: всадники встают элитой. Пепла больше. | The Hour, the Day, the Month, the Year / The cavalry is ready for its time: horsemen rise as elites. More Ash. |
| `OMEN_SEVEN_THUNDERS` / `_DESC` | Семь громов / В громе никто не слышит: враги видят хуже, но твой навык молчит дольше. Пепла больше. | Seven Thunders / No one hears in the thunder: enemies see less, but your skill stays silent longer. More Ash. |
| `OMEN_LOOSED_RIVER` / `_DESC` | Отпущенная река / Каждая цепь длиннее в полтора раза. Эссенции больше. | The Loosed River / Every chain is half as long again. More essence. |
