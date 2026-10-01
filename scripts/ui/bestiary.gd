extends Control
class_name Bestiary
## The bestiary: every enemy kind in the data, opened page by page as the
## player meets them (Profile keeps the book). Works from the main menu and
## from the pause menu, like SettingsMenu.
##
## Three states per kind:
##   unknown  never spawned in a room the player was in — "???", no portrait
##   seen     spawned, never killed — silhouette and name
##   known    killed at least once — portrait, stats, lore, kill count
## People (data/npcs, ids "npc:<id>") get the same book after the enemies:
## a silhouette once you have shared a room, the page once you have talked.
## Records from secret caches (data/notes, ids "note:<id>") follow, and the
## deeds (data/achievements, ids "deed:<id>") close the book: each one's name
## from the start, its page saying what it asks and how far along it is.

signal closed

## The main menu's bestiary may send the player to the practice yard to fight
## a kind they have met (docs/PRACTICE.md); the pause menu's may not, since
## that would walk out of the night being played.
@export var allow_practice := false
const RUN_SCENE := "res://scenes/run/run.tscn"
var _practice: Button

const UNKNOWN_NAME := "???"
const DIM := Color(0.55, 0.53, 0.58)
const GOLD := Color(0.95, 0.85, 0.5)
const SILHOUETTE := Color(0.08, 0.06, 0.1)
## Attack types → their localization key; contact damage is listed separately.
const ATTACK_KEYS := {"melee": "BESTIARY_ATK_MELEE", "ranged": "BESTIARY_ATK_RANGED", "lunge": "BESTIARY_ATK_LUNGE", "beam": "BESTIARY_ATK_BEAM", "nova": "BESTIARY_ATK_NOVA"}
const FAMILY_ORDER := ["possessed", "cult", "fallen", "restless", "heaven"]

var _ids: Array[String] = []
var _selected := ""

@onready var progress: Label = %Progress
@onready var list: VBoxContainer = %List
@onready var portrait: Control = %Portrait
@onready var avatar: TextureRect = %Avatar
@onready var sprite: AnimatedSprite2D = %Sprite
@onready var name_label: Label = %Name
@onready var tags_label: Label = %Tags
@onready var stats_box: GridContainer = %Stats
@onready var lore_label: Label = %Lore
@onready var abilities_title: Label = %AbilitiesTitle
@onready var abilities_box: VBoxContainer = %Abilities
@onready var hint_label: Label = %Hint
@onready var back_button: Button = %Back


func _ready() -> void:
	back_button.pressed.connect(close)
	_practice = Button.new()
	_practice.name = "Practice"
	_practice.text = tr("BESTIARY_PRACTICE")
	_practice.visible = false
	_practice.pressed.connect(_go_practise)
	hint_label.add_sibling(_practice)
	portrait.resized.connect(_place_sprite)


func open() -> void:
	_build_list()
	visible = true
	if list.get_child_count() > 0:
		# Come back to the page that was open; the first one otherwise.
		var target: Button = list.get_node_or_null(_selected.replace(":", "_")) if _selected != "" else null
		(target if target else list.get_child(0) as Button).grab_focus()
	else:
		back_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Weakest first, by the essence a kill is worth; bosses land at the end on their own.
func _build_list() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	# a practice dummy is not a creature of the world
	_ids.assign(Data.enemies.keys().filter(func(id: String) -> bool: return Data.enemies[id].get("bestiary", true)))
	_ids.sort_custom(func(a: String, b: String) -> bool:
		var sa: Dictionary = Data.enemies[a]
		var sb: Dictionary = Data.enemies[b]
		var fa := FAMILY_ORDER.find(str(sa.get("family", "restless")))
		var fb := FAMILY_ORDER.find(str(sb.get("family", "restless")))
		fa = fa if fa >= 0 else FAMILY_ORDER.size()
		fb = fb if fb >= 0 else FAMILY_ORDER.size()
		if fa != fb:
			return fa < fb
		var ta := int(sa.get("tier", 1))
		var tb := int(sb.get("tier", 1))
		return ta < tb if ta != tb else float(sa.get("essence", 10)) < float(sb.get("essence", 10)))
	var enemies := _ids.size()
	var people: Array[String] = []
	people.assign(Data.npcs.keys().map(func(id: String) -> String: return "npc:" + id))
	people.sort()
	var notes: Array[String] = []
	notes.assign(Data.notes.keys().map(func(id: String) -> String: return "note:" + id))
	var deeds: Array[String] = []
	deeds.assign(Achievements.ids().map(func(id: String) -> String: return "deed:" + id))
	# the chronicle closes the book: the totals, then the last nights, newest first
	var chronicle: Array[String] = ["chron:total"]
	var history: Array = _history()
	for i in range(history.size() - 1, -1, -1):
		chronicle.append("chron:%d" % i)
	var last_family := ""
	for id in _ids + people + notes + deeds + chronicle:
		if (not people.is_empty() and id == people[0]) or (not notes.is_empty() and id == notes[0]) \
				or (not deeds.is_empty() and id == deeds[0]) or id == chronicle[0]:
			var heading := Label.new()
			heading.text = tr("BESTIARY_PEOPLE" if id.begins_with("npc:") else ("BESTIARY_NOTES" if id.begins_with("note:")
				else ("BESTIARY_DEEDS" if id.begins_with("deed:") else "BESTIARY_CHRONICLE")))
			if id.begins_with("deed:"):
				heading.text += "  %d / %d" % [deeds.filter(func(d: String) -> bool: return Achievements.done(d.trim_prefix("deed:"))).size(), deeds.size()]
			heading.add_theme_color_override("font_color", GOLD)
			heading.add_theme_font_size_override("font_size", 11)
			list.add_child(heading)
		elif not id.begins_with("npc:") and not id.begins_with("note:") and not id.begins_with("deed:") \
				and not id.begins_with("chron:"):
			var family := str(Data.enemies[id].get("family", "restless"))
			if family != last_family:
				last_family = family
				var heading := Label.new()
				heading.text = tr("BESTIARY_FAMILY_" + family.to_upper())
				heading.add_theme_color_override("font_color", GOLD)
				heading.add_theme_font_size_override("font_size", 11)
				list.add_child(heading)
		var entry := Profile.bestiary_entry(id)
		var button := Button.new()
		button.name = id.replace(":", "_")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var branch := ""
		if id.begins_with("deed:"):
			branch = "  ◆ " if Achievements.done(id.trim_prefix("deed:")) else "  ◇ "
		elif id.begins_with("chron:"):
			branch = "  "
		elif not id.begins_with("npc:") and not id.begins_with("note:"):
			branch = "  └ " if int(_spec(id).get("tier", 1)) > 1 else "  ◆ "
		button.text = branch + (tr(_spec(id).get("name", id)) if entry.get("seen", false) or id.begins_with("deed:")
			or id.begins_with("chron:") else UNKNOWN_NAME)
		if not _known(id, entry):
			button.add_theme_color_override("font_color", DIM)
		button.focus_entered.connect(_show.bind(id))
		button.pressed.connect(_show.bind(id))
		list.add_child(button)
	_ids.append_array(people)
	_ids.append_array(notes)
	_ids.append_array(deeds)
	_ids.append_array(chronicle)
	progress.text = tr("BESTIARY_PROGRESS") % [Profile.bestiary_known(), enemies]
	if _ids.is_empty() or not _ids.has(_selected):
		_selected = _ids[0] if not _ids.is_empty() else ""
	if _selected != "":
		_show(_selected)


## The data behind a page: an enemy, or a person for an "npc:" id.
func _spec(id: String) -> Dictionary:
	if id.begins_with("npc:"):
		return Data.npcs.get(id.trim_prefix("npc:"), {})
	if id.begins_with("note:"):
		return Data.notes.get(id.trim_prefix("note:"), {})
	if id.begins_with("deed:"):
		return Achievements.spec(id.trim_prefix("deed:"))
	if id == "chron:total":
		return {"name": tr("CHRONICLE_TOTAL")}
	if id.begins_with("chron:"):
		var night: Dictionary = _history()[int(id.trim_prefix("chron:"))]
		return {"name": tr("CHRONICLE_NIGHT") % [int(night.get("night", 0)),
			tr("CHRONICLE_DAWN") if night.get("won", false) else tr("CHRONICLE_AREA") % int(night.get("area", 0))]}
	return Data.enemies.get(id, {})


## A page is open once the enemy has been slain, or the person spoken to.
func _known(id: String, entry: Dictionary) -> bool:
	if id.begins_with("deed:"):
		return Achievements.done(id.trim_prefix("deed:"))
	if id.begins_with("chron:"):
		return true
	if id.begins_with("npc:") or id.begins_with("note:"):
		return entry.get("met", false)
	return int(entry.get("kills", 0)) > 0


func _show(id: String) -> void:
	_selected = id
	var stats := _spec(id)
	var entry := Profile.bestiary_entry(id)
	var seen: bool = entry.get("seen", false)
	var kills := int(entry.get("kills", 0))
	var known := _known(id, entry)
	for child in stats_box.get_children():
		stats_box.remove_child(child)
		child.queue_free()
	for child in abilities_box.get_children():
		abilities_box.remove_child(child)
		child.queue_free()
	abilities_title.visible = false
	_set_portrait(stats if seen else {}, known)
	name_label.text = tr(stats.get("name", id)) if seen else UNKNOWN_NAME
	tags_label.text = ""
	lore_label.text = ""
	hint_label.text = ""
	_practice.visible = allow_practice and seen and can_practise(id)
	if id.begins_with("deed:"):
		_show_deed(id.trim_prefix("deed:"), stats)
		return
	if id.begins_with("chron:"):
		name_label.text = str(stats.get("name", ""))
		if id == "chron:total":
			_show_totals()
		else:
			_show_night(_history()[int(id.trim_prefix("chron:"))])
		return
	if not seen:
		hint_label.text = tr("BESTIARY_HINT_NOTE" if id.begins_with("note:") else "BESTIARY_HINT_UNKNOWN")
		return
	if id.begins_with("note:"):
		var chapter: Dictionary = Data.chapters.get(str(stats.get("place", "")), {})
		if chapter.has("title"):
			tags_label.text = tr(chapter.title)
		lore_label.text = _note_text(str(stats.get("dialogue", "")))
		return
	if id.begins_with("npc:"):
		if stats.has("role"):
			tags_label.text = tr(stats.role)
		if not known:
			hint_label.text = tr("BESTIARY_HINT_MEET")
			return
		_place_row(stats, entry)
		if not stats.get("lines", []).is_empty():
			_stat("BESTIARY_SAYS", "«%s»" % tr(stats.lines[0]))
		if stats.has("lore"):
			lore_label.text = tr(stats.lore)
		return
	if kills <= 0:
		hint_label.text = tr("BESTIARY_HINT_SEEN")
		# not yet slain, but it has slain you: the book tells you how
		if int(entry.get("felled", 0)) > 0 and stats.has("tip"):
			hint_label.text += "\n\n%s: %s" % [tr("TIP_LABEL"), tr(stats.tip)]
		return
	var tags: Array = stats.get("tags", []).map(func(tag: String) -> String: return tr("TAG_" + tag.to_upper()))
	tags_label.text = " · ".join(tags)
	_stat("BESTIARY_HP", str(int(stats.get("hp", 0))))
	_stat("BESTIARY_SPEED", str(int(stats.get("speed", 0))))
	if float(stats.get("armor", 0.0)) > 0.0:
		_stat("BESTIARY_ARMOR", "%d%%" % int(round(float(stats.armor) * 100.0)))
	var attacks := _attack_summary(stats)
	if attacks != "":
		_stat("BESTIARY_ATTACKS", attacks)
	_stat("BESTIARY_ESSENCE", str(int(stats.get("essence", 0))))
	_place_row(stats, entry)
	_stat("BESTIARY_SLAIN", str(kills))
	if int(entry.get("felled", 0)) > 0:
		_stat("BESTIARY_FELLED", str(int(entry.felled)))
	if stats.has("lore"):
		lore_label.text = tr(stats.lore)
	if stats.has("tip"):
		lore_label.text += ("\n\n" if lore_label.text != "" else "") + "%s: %s" % [tr("TIP_LABEL"), tr(stats.tip)]
	_show_abilities(stats)


## The chronicle (Profile.data.history): the nights the profile remembers.
func _history() -> Array:
	return Profile.data.get("history", []) if Profile.data.get("history") is Array else []


func _clock(seconds: float) -> String:
	var minutes := int(seconds) / 60
	return "%d:%02d:%02d" % [minutes / 60, minutes % 60, int(seconds) % 60] if minutes >= 60 \
		else "%d:%02d" % [minutes, int(seconds) % 60]


func _show_totals() -> void:
	var data: Dictionary = Profile.data
	_stat("CHRONICLE_NIGHTS", str(int(data.get("nights", 0))))
	_stat("CHRONICLE_DAWNS", str(int(data.get("wins", 0))))
	_stat("CHRONICLE_FURTHEST", str(int(data.get("best_wave", 0))))
	_stat("CHRONICLE_TIME", _clock(float(data.get("total_seconds", 0.0))))
	_stat("CHRONICLE_KILLS", str(int(data.get("total_kills", 0))))
	var done := Achievements.ids().filter(func(d: String) -> bool: return Achievements.done(d)).size()
	_stat("BESTIARY_DEEDS", "%d / %d" % [done, Achievements.ids().size()])
	# the path the remembered nights leaned to most — a feeling, never a number
	var leaned := {}
	for night in _history():
		var path := str(night.get("path", ""))
		if path != "":
			leaned[path] = int(leaned.get(path, 0)) + 1
	if not leaned.is_empty():
		var most: String = leaned.keys()[0]
		for path in leaned:
			if leaned[path] > leaned[most]:
				most = path
		_stat("CHRONICLE_LEANING", tr("PATH_" + most.to_upper()))
	var today := Daily.best()
	if not today.is_empty():
		_stat("MENU_DAILY", tr("CHRONICLE_AREA") % int(today.get("area", 0)))


func _show_night(night: Dictionary) -> void:
	tags_label.text = str(night.get("date", ""))
	var path := str(night.get("path", ""))
	_stat("CHRONICLE_LEANED", tr("PATH_" + path.to_upper()) if path != "" else "—")
	if int(night.get("vial", 0)) > 0:
		_stat("SETTINGS_VIAL", tr(str(Vials.spec(int(night.vial)).get("name", ""))))
	if night.get("daily", false):
		_stat("MENU_DAILY", "◆")
	if Data.omens.has(str(night.get("omen", ""))):
		_stat("OMEN_LABEL", tr(str(Omens.spec(str(night.omen)).get("name", ""))))
	_stat("CHRONICLE_TIME", _clock(float(night.get("seconds", 0))))
	_stat("CHRONICLE_KILLS", str(int(night.get("kills", 0))))
	var killer := EndScreen.slain_name(str(night.get("slain_by", "")))
	if killer != "":
		_stat("CHRONICLE_SLAIN_BY", killer)
	var names: Array = []
	for gift in night.get("gifts", []):
		if Data.abilities.has(gift):
			names.append(tr(str(Data.abilities[gift].name)))
	for resonance in night.get("resonances", []):
		if Data.resonances.has(resonance):
			names.append("◆ " + tr(str(Data.resonances[resonance].name)))
	lore_label.text = "%s: %s" % [tr("RUN_GIFTS"), ", ".join(names)] if not names.is_empty() else ""


## A deed's page: what it asks, how far along, and when it was done. Its
## name shows from the start — a deed is a goal, not a secret.
func _show_deed(deed_id: String, stats: Dictionary) -> void:
	name_label.text = tr(str(stats.get("name", deed_id)))
	lore_label.text = tr(str(stats.get("description", "")))
	var progress := Achievements.progress(deed_id)
	if Achievements.done(deed_id):
		var when := int(Profile.data.achievements[deed_id])
		_stat("DEED_ON", Time.get_date_string_from_unix_time(when))
	elif progress[1] > 1:
		_stat("DEED_PROGRESS", "%d / %d" % progress)
	if int(stats.get("ash", 0)) > 0:
		_stat("DEED_REWARD", str(int(stats.ash)))


## Any creature met can be sparred with, bar the ones that are part of
## another's fight (the Ophanim's seals) and the people and records.
static func can_practise(id: String) -> bool:
	if id.begins_with("npc:") or id.begins_with("note:") or id.begins_with("deed:") or not Data.enemies.has(id):
		return false
	return Data.enemies[id].get("behaviour", "walker") != "seal" and not Net.active


func _go_practise() -> void:
	Game.practice = _selected
	Curtain.change_scene(RUN_SCENE)


## A record's page is the caption it was read out as, line after line.
func _note_text(dialogue_id: String) -> String:
	var dialogue: Dictionary = Data.dialogues.get(dialogue_id, {})
	var nodes: Dictionary = dialogue.get("nodes", {})
	var lines: PackedStringArray = []
	var node_id := str(dialogue.get("start", ""))
	while node_id != "" and nodes.has(node_id) and lines.size() < 32:
		lines.append(tr(str(nodes[node_id].get("text", ""))))
		node_id = str(nodes[node_id].get("next", ""))
	return "\n\n".join(lines)


## Where it is at home when the data says so, otherwise where this player first
## laid eyes on one (Profile remembers the chapter, see Game.place).
func _place_row(stats: Dictionary, entry: Dictionary) -> void:
	if stats.has("location"):
		_stat("BESTIARY_PLACE", tr(stats.location))
		return
	var chapter: Dictionary = Data.chapters.get(str(entry.get("place", "")), {})
	if chapter.has("title"):
		_stat("BESTIARY_PLACE", tr(chapter.title))


## "Melee 12 · Ranged 10 · Touch 6": base damage, before difficulty and time scaling.
func _attack_summary(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	var attacks: Array = stats.get("attacks", [])
	if stats.has("attack"):
		attacks = attacks + [stats.attack]
	for attack in attacks:
		var key: String = str(attack.get("name", ATTACK_KEYS.get(attack.get("type", ""), "")))
		if key != "":
			parts.append("%s %d" % [tr(key), int(attack.get("damage", 0))])
	if float(stats.get("damage", 0)) > 0.0:
		parts.append("%s %d" % [tr("BESTIARY_CONTACT"), int(stats.damage)])
	return " · ".join(parts)


func _show_abilities(stats: Dictionary) -> void:
	var abilities: Array = stats.get("attacks", []).duplicate(true)
	abilities.append_array(stats.get("abilities", []))
	abilities_title.visible = not abilities.is_empty()
	for ability in abilities:
		var label := Label.new()
		var description := str(ability.get("description", ""))
		if description == "" and ability.has("type"):
			description = tr("BESTIARY_MOVE_DETAIL") % [int(ability.get("damage", 0)), int(ability.get("range", ability.get("radius", 0))), float(ability.get("windup", 0.0)), float(ability.get("cooldown", 0.0))]
		label.text = "◆ %s\n%s" % [tr(ability.get("name", ATTACK_KEYS.get(ability.get("type", ""), ""))), tr(description)]
		label.add_theme_color_override("font_color", GOLD)
		label.add_theme_font_size_override("font_size", 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = tr(ability.get("description", ""))
		abilities_box.add_child(label)


func _stat(key: String, value: String) -> void:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", DIM)
	label.add_theme_font_size_override("font_size", 11)
	stats_box.add_child(label)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_box.add_child(value_label)


## The idle strip, built the way the enemy builds it. Empty stats = no portrait;
## a kind the player has met but not beaten is a silhouette.
func _set_portrait(stats: Dictionary, known: bool) -> void:
	avatar.visible = false
	avatar.texture = null
	sprite.visible = false
	sprite.sprite_frames = null
	if stats.is_empty():
		return
	if stats.has("avatar") and ResourceLoader.exists(str(stats.avatar)):
		avatar.texture = load(str(stats.avatar))
		avatar.modulate = Color.WHITE if known else SILHOUETTE
		avatar.visible = true
		return
	if not stats.has("sprite"):
		return
	var spec: Dictionary = stats.sprite
	if spec.has("like"):  # another creature's strips (Enemy._setup_sprite)
		var borrowed: Dictionary = Data.enemies.get(str(spec.like), {}).get("sprite", {}).duplicate(true)
		borrowed.merge(spec, true)
		spec = borrowed
	var frames := SpriteFrames.new()
	var cell := Vector2i(int(spec.get("frame_w", 24)), int(spec.get("frame_h", 28)))
	if spec.has("cell"):
		cell = Vector2i(int(spec.cell[0]), int(spec.cell[1]))
	var path: String = spec.animations.get("idle", "") if spec.has("animations") else spec.get("path", "")
	if path == "" or not Fx.add_strip(frames, path, cell, float(spec.get("fps", 6)), "idle", true):
		return
	sprite.sprite_frames = frames
	sprite.set_meta("cell", cell)
	sprite.modulate = Color.WHITE if known else SILHOUETTE
	sprite.self_modulate = Color(str(spec.get("tint", "#ffffff")))
	sprite.visible = true
	sprite.play("idle")
	_place_sprite()


## Centred in the portrait box, 2× when the cell fits, smaller for the big bosses.
func _place_sprite() -> void:
	if sprite.sprite_frames == null:
		return
	var cell: Vector2i = sprite.get_meta("cell", Vector2i(24, 28))
	var room := portrait.size - Vector2(8, 8)
	var fit := minf(2.0, minf(room.x / cell.x, room.y / cell.y))
	sprite.scale = Vector2.ONE * fit
	sprite.position = portrait.size / 2.0
