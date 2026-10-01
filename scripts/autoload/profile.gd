extends Node
## Persistent player profile across runs (user://profile.json).
## Versioned so the schema can change without losing players' progress:
## bump VERSION and add a step to _migrate().

const PATH := "user://profile.json"
const VERSION := 2
## Nights in a row on one path before the world starts to notice (habit()).
const HABIT_NIGHTS := 3
## Nights the chronicle keeps (Profile.data.history).
const HISTORY := 10

var data: Dictionary = _defaults()


static func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"nights": 0,        # runs finished (won or died)
		"best_wave": 0,
		"total_kills": 0,
		"total_seconds": 0.0,
		"ash": 0,           # permanent currency (docs/BALANCE.md)
		"bestiary": {},     # enemy id -> {"seen": bool, "kills": int}; people as "npc:<id>" with "met" (scripts/ui/bestiary.gd)
		"menu_character": "elian",  # the figure shown on the main menu
		# Elian's opening monologue plays in full once. Every night after that
		# he says the first line and the last one and gets up (run.gd _begin).
		# An older profile without the key reads false and hears it once more.
		"prologue_seen": false,
		# The special moves (docs/TECHNIQUES.md) this player has pulled off at
		# least once, and the in-night hints already given (MoveHints): a hint
		# comes once, and never for a move already known. Learning in the
		# practice yard counts here — knowing a move is not a reward.
		"moves_done": {},
		"hints_shown": {},
		# Nights that ended at dawn rather than in a death.
		"wins": 0,
		# The highest vial of wrath a dawn has opened (scripts/run/vials.gd).
		"vials_opened": 0,
		# Relics bought with Ash (data/relics, scripts/meta/relics.gd): id -> true.
		"relics": {},
		# The night of the day's best (scripts/run/daily.gd): {date, area, seconds, won, tries}.
		"daily": {},
		# The chronicle (bestiary): the last HISTORY nights, newest last.
		"history": [],
		# Counters the deeds read (Achievements.COUNTERS): parries, backstabs…
		"deeds": {},
		# Deeds done (data/achievements): id -> the unix time it happened.
		"achievements": {},
		# The world notices (docs/CORE_LOOP.md): the path the last nights leaned
		# to, and how many in a row. HABIT_NIGHTS of them and it is a habit.
		"habit": {"path": "", "nights": 0},
		# Where the last night ended in a death (LastFall): {room, x, y, by}.
		"last_fall": {},
	}


func _ready() -> void:
	load_profile()
	EventBus.enemy_died.connect(func(enemy_id: StringName, _pos: Vector2) -> void: record_kill(String(enemy_id)))
	EventBus.technique_performed.connect(record_move)
	EventBus.technique_performed.connect(func(id: String) -> void:
		if id in ["backstab", "riposte"]:
			count(id + "s"))
	EventBus.player_parried.connect(count.bind("parries"))
	EventBus.player_unscathed.connect(func(_index: int) -> void: count("unscathed"))
	EventBus.player_rested.connect(func(_room: String) -> void: count("rests"))
	# a store, if this build carries one and it is running (docs/STEAM.md)
	set_process(StoreBridge.start())


func _process(_delta: float) -> void:
	StoreBridge.poll()


func load_profile() -> void:
	data = _defaults()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data.merge(parsed, true)
		_migrate()


func record_run(wave: int, kills: int, seconds: float, ash := 0, won := false) -> void:
	data.nights += 1
	data.best_wave = maxi(data.best_wave, wave)
	data.total_kills += kills
	data.total_seconds += seconds
	data.ash += ash
	_note_lean()
	_chronicle(wave, kills, seconds, won)
	# every gift carried and resonance woken is a page in the codex (bestiary
	# "gift:<id>", "res:<id>"): named from then on, its nights counted
	for ability in Game.abilities:
		_codex("gift:" + str(ability.get("id", "")))
	for id in Game.resonances:
		_codex("res:" + str(id))
	# an omen drawn is a page in the book (bestiary "omen:<id>"): its nights, its dawns
	if Game.omen != "":
		var drawn: Dictionary = data.bestiary.get("omen:" + Game.omen, {"seen": true, "met": true, "kills": 0})
		drawn["nights"] = int(drawn.get("nights", 0)) + 1
		drawn["dawns"] = int(drawn.get("dawns", 0)) + (1 if won else 0)
		data.bestiary["omen:" + Game.omen] = drawn
	# the bestiary remembers who laid this player low, and how often
	if not won and Data.enemies.has(Game.slain_by):
		var entry: Dictionary = data.bestiary.get(Game.slain_by, {})
		entry["seen"] = true
		entry["kills"] = int(entry.get("kills", 0))
		entry["felled"] = int(entry.get("felled", 0)) + 1
		data.bestiary[Game.slain_by] = entry
	if won:
		data.wins = int(data.get("wins", 0)) + 1
		_bump("wins_" + Game.dominant_path())
		if Settings.difficulty == "judgment":
			_bump("wins_judgment")
		# a dawn under an omen (data/omens); the night of the day's counts too
		if Game.omen != "":
			_bump("wins_omen")
		# a dawn opens the next vial of wrath (scripts/run/vials.gd)
		# the night of the day pours a vial the profile may not have opened: it
		# opens nothing and counts for no vial deed
		if Game.daily == "":
			data.vials_opened = mini(maxi(int(data.get("vials_opened", 0)), Game.vial + 1), Vials.TIERS)
			if Game.vial > 0:
				_bump("wins_vial_%d" % Game.vial)
	save()
	check_achievements()


## One line of the chronicle per night: where it ended, how it leaned, what it
## carried. Gift and resonance ids, so a renamed gift reads in the new name and
## a removed one is simply left out (Chronicle in the bestiary).
func _chronicle(area: int, kills: int, seconds: float, won: bool) -> void:
	if not (data.get("history") is Array):
		data.history = []
	data.history.append({
		"night": int(data.nights),
		"date": Time.get_date_string_from_system(),
		"area": area,
		"won": won,
		"path": Game.dominant_path() if Game.lead() >= 2 else "",
		"seconds": int(seconds),
		"kills": kills,
		"vial": Game.vial,
		"omen": Game.omen,
		"daily": Game.daily != "",
		"gifts": Game.abilities.map(func(a: Dictionary) -> String: return str(a.get("id", ""))),
		"resonances": Game.resonances.duplicate(),
		"slain_by": "" if won else Game.slain_by,
	})
	while data.history.size() > HISTORY:
		data.history.pop_front()


func _codex(key: String) -> void:
	if key.ends_with(":"):
		return
	var page: Dictionary = data.bestiary.get(key, {"seen": true, "met": true, "kills": 0})
	page["nights"] = int(page.get("nights", 0)) + 1
	data.bestiary[key] = page


## A night that leaned clearly one way (the lead the aura shows at) extends
## the run of nights on that path; a level night or another path starts over.
func _note_lean() -> void:
	var path := Game.dominant_path() if Game.lead() >= 2 else ""
	var habit: Dictionary = data.get("habit", {}) if data.get("habit") is Dictionary else {}
	if path != "" and str(habit.get("path", "")) == path:
		habit.nights = int(habit.get("nights", 0)) + 1
	else:
		habit = {"path": path, "nights": 1 if path != "" else 0}
	data.habit = habit


## The path this player has leaned to for the last HABIT_NIGHTS nights and
## more, or "" — what Elian, the angel and the body remember of it.
func habit() -> String:
	var habit: Dictionary = data.get("habit", {}) if data.get("habit") is Dictionary else {}
	return str(habit.get("path", "")) if int(habit.get("nights", 0)) >= HABIT_NIGHTS else ""


## One more of something a deed counts (Achievements.COUNTERS). Nothing counts
## in the practice yard, and a referee has no profile to count into.
func count(counter: String, amount := 1) -> void:
	if Net.dedicated or Game.practice != "":
		return
	_bump(counter, amount)
	save()
	check_achievements()


func _bump(counter: String, amount := 1) -> void:
	if not (data.get("deeds") is Dictionary):
		data.deeds = {}
	data.deeds[counter] = int(data.deeds.get(counter, 0)) + amount


## Marks every deed whose conditions now hold, pays its Ash once, and tells the
## run (the toast, the playtest log). Returns the ids newly done.
func check_achievements() -> Array:
	var fresh := []
	if Net.dedicated or Game.practice != "":
		return fresh
	if not (data.get("achievements") is Dictionary):
		data.achievements = {}
	for id in Achievements.ids():
		if data.achievements.has(id) or not Achievements.met(id):
			continue
		data.achievements[id] = int(Time.get_unix_time_from_system())
		data.ash += int(Achievements.spec(id).get("ash", 0))
		fresh.append(id)
	if not fresh.is_empty():
		save()
		for id in fresh:
			EventBus.achievement_unlocked.emit(id)
		StoreBridge.mirror(fresh)
	return fresh


## The bestiary fills in as the player meets things: a kind is "seen" the moment
## one spawns in the room they are in, "known" once one has died. Both happen on
## every peer of a session (spawns and deaths are replicated), so a guest keeps
## their own book. A dedicated referee has no book to keep.
func record_seen(enemy_id: String) -> void:
	if Net.dedicated or enemy_id == "" or Game.practice != "":
		return
	var entry: Dictionary = data.bestiary.get(enemy_id, {})
	if entry.get("seen", false):
		return
	entry["seen"] = true
	entry["kills"] = int(entry.get("kills", 0))
	if Game.place != "":
		entry["place"] = Game.place  # where this one was first laid eyes on
	data.bestiary[enemy_id] = entry
	save()  # an unlock should survive a crash later in the night


func record_move(technique_id: String) -> void:
	if Net.dedicated or technique_id == "" or data.moves_done.has(technique_id):
		return
	data.moves_done[technique_id] = true
	save()
	check_achievements()


func mark_hint(technique_id: String) -> void:
	if Net.dedicated or data.hints_shown.has(technique_id):
		return
	data.hints_shown[technique_id] = true
	save()


func record_kill(enemy_id: String) -> void:
	# a practice kill fills no book and unlocks no cloak (skins count kills)
	if Net.dedicated or enemy_id == "" or Game.practice != "":
		return
	var entry: Dictionary = data.bestiary.get(enemy_id, {})
	entry["seen"] = true
	entry["kills"] = int(entry.get("kills", 0)) + 1
	data.bestiary[enemy_id] = entry
	if entry.kills == 1:
		save()
		EventBus.bestiary_unlocked.emit(enemy_id)
	check_achievements()


## A boss laid low in [param seconds] (Enemy.fight_time): its page keeps the
## best. Never in the yard; returns whether it was a new best.
func record_boss_time(enemy_id: String, seconds: float) -> bool:
	if Net.dedicated or enemy_id == "" or Game.practice != "" or seconds <= 0.0:
		return false
	var entry: Dictionary = data.bestiary.get(enemy_id, {})
	var best := float(entry.get("best_time", 0.0))
	if best > 0.0 and best <= seconds:
		return false
	entry["best_time"] = snappedf(seconds, 0.1)
	data.bestiary[enemy_id] = entry
	save()
	check_achievements()  # Swift Judgment reads the best fights
	return true


## Talked to a person: their bestiary page opens. Ids are "npc:<id>".
func record_met(npc_id: String) -> void:
	if Net.dedicated or npc_id == "":
		return
	var entry: Dictionary = data.bestiary.get(npc_id, {})
	if entry.get("met", false):
		return
	entry["seen"] = true
	entry["met"] = true
	entry["kills"] = int(entry.get("kills", 0))
	data.bestiary[npc_id] = entry
	save()
	EventBus.bestiary_unlocked.emit(npc_id)


## A record from a secret cache: its page opens in the bestiary as "note:<id>".
## Returns true the first time, which is when the cache pays its Ash.
func record_note(note_id: String) -> bool:
	if Net.dedicated or note_id == "":
		return false
	var key := "note:" + note_id
	if data.bestiary.get(key, {}).get("met", false):
		return false
	data.bestiary[key] = {"seen": true, "met": true, "kills": 0}
	save()
	EventBus.bestiary_unlocked.emit(key)
	check_achievements()
	return true


func bestiary_entry(enemy_id: String) -> Dictionary:
	return data.bestiary.get(enemy_id, {})


## Kinds the player has slain at least once.
func bestiary_known() -> int:
	var known := 0
	for id in data.bestiary:
		# only kinds that still exist: renamed or removed enemies must not inflate the count,
		# …and not the straw man, which the book does not list (bestiary: false)
		if Data.enemies.has(id) and Data.enemies[id].get("bestiary", true) \
				and int(data.bestiary[id].get("kills", 0)) > 0:
			known += 1
	return known


func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _migrate() -> void:
	var from := int(data.get("version", 0))
	if from < 2 and not (data.get("bestiary") is Dictionary):
		data.bestiary = {}  # v2: the bestiary
	if from != VERSION:
		print("[Profile] migrated %d -> %d" % [from, VERSION])
	data.version = VERSION
