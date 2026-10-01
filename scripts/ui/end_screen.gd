extends Control
class_name EndScreen
## Death / victory page. A line from whoever the player leaned towards,
## the night's numbers, the gifts taken, and a retry one tap away.

signal retry
signal to_menu
## Into the practice yard against what laid him low (an enemy id).
signal spar(enemy_id: String)

## The page has a painting behind it, not a flat wash: the graveyard for a
## death, the dawn you did not live to see for a win.
const BACKDROP_DEAD := preload("res://assets/backgrounds/graveyard.png")
const BACKDROP_WON := preload("res://assets/backgrounds/village_dawn.png")

## What a finished night says, by the path the run leaned to. None of them is
## the good one (docs/GDD.md): Heaven's word, the Abyss's, and nobody's.
const WIN_LINES := {"grace": "WIN_LINE_GRACE", "temptation": "WIN_LINE_TEMPTATION", "will": "WIN_LINE"}

const LINES := {
	"grace": ["SPEAKER_ANGEL", "DEATH_LINE_GRACE"],
	"temptation": ["SPEAKER_STRANGER", "DEATH_LINE_TEMPTATION"],
	"will": ["SPEAKER_ELIAN", "DEATH_LINE_WILL"],
}

@onready var title: Label = %RunEndTitle
@onready var speaker: Label = %RunEndSpeaker
@onready var line: Label = %RunEndBody
@onready var stats: Label = %RunEndStats
@onready var best: Label = %RunEndBest
@onready var gifts: Label = %RunEndGifts
@onready var vignette: ColorRect = %Vignette
@onready var content: Control = %Content
@onready var backdrop: TextureRect = %Backdrop
@onready var glow: TextureRect = %Glow
## "Spar with it", between Again and the menu: shown after a death to
## something the yard can stand up (Bestiary.can_practise), solo only.
var spar_button: Button


func _ready() -> void:
	visible = false
	%Retry.pressed.connect(retry.emit)
	%Menu.pressed.connect(to_menu.emit)
	# the yard and the menu share a row: a long night's gifts already fill the page
	var menu: Button = %Menu
	var exits := HBoxContainer.new()
	exits.name = "Exits"
	exits.alignment = BoxContainer.ALIGNMENT_CENTER
	exits.add_theme_constant_override("separation", 32)
	menu.add_sibling(exits)
	spar_button = Button.new()
	spar_button.name = "Spar"
	spar_button.flat = true
	spar_button.visible = false
	spar_button.pressed.connect(func() -> void: spar.emit(Game.slain_by))
	exits.add_child(spar_button)
	menu.reparent(exits, false)


## Online it is the host who starts another night; a guest only gets the door out.
func allow_retry(allowed: bool) -> void:
	%Retry.visible = allowed


## [param place] is the localization key of the chapter the night ended in
## (data/chapters); empty for a room no chapter claims, and then the line
## falls back to the area's number.
func show_result(won: bool, area: int, kills: int, seconds: float, place := "") -> void:
	title.text = "RUN_WIN_TITLE" if won else "RUN_DEAD_TITLE"
	if won:
		speaker.text = ""
		line.text = WIN_LINES.get(Game.dominant_path(), "WIN_LINE")
	else:
		var who: Array = LINES[Game.dominant_path()]
		speaker.text = who[0]
		line.text = who[1]
	var clock := "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	stats.text = tr("RUN_STATS_PLACE") % [Profile.data.nights, tr(place), kills, clock] if place != "" \
		else tr("RUN_STATS") % [Profile.data.nights, area, kills, clock]
	best.text = "%s   ·   %s" % [tr("RUN_BEST") % Profile.data.best_wave, tr("RUN_ASH") % [Game.ash_earned, Profile.data.ash]]
	if Game.unscathed > 0:
		best.text += "   ·   " + tr("RUN_UNSCATHED") % Game.unscathed
	# the vial this night was played under, and the one a dawn opens (data/vials)
	if Game.vial > 0:
		stats.text += "   ·   " + tr(str(Vials.spec(Game.vial).get("name", "")))
	# and the omen it was drawn under (data/omens)
	if Game.omen != "":
		stats.text += "   ·   " + tr(str(Omens.spec(Game.omen).get("name", "")))
	# what laid him low, above the numbers (Player.slain_by)
	var killer := slain_name(Game.slain_by) if not won else ""
	if killer != "":
		stats.text = tr("RUN_SLAIN_BY") % killer + "\n" + stats.text
	var blows := last_blows_line(Game.last_blows) if not won else ""
	if blows != "":
		stats.text += "\n" + blows
	stats.text += "\n" + numbers_line()
	# the night of the day: where it stands against the day's best (Daily)
	if Game.daily != "":
		var day := Daily.best(Game.daily)
		best.text += "\n" + (tr("DAILY_NEW_BEST") if Game.daily_best else tr("DAILY_BEST") % int(day.get("area", 0)))
	if won and Game.daily == "" and Game.vial < Vials.TIERS and Vials.opened() == Game.vial + 1:
		best.text += "\n" + tr("VIAL_OPENED") % tr(str(Vials.spec(Game.vial + 1).get("name", "")))
	# and the yard is one step away, with that very enemy in it
	spar_button.visible = not won and Game.practice == "" and Bestiary.can_practise(Game.slain_by)
	if spar_button.visible:
		spar_button.text = tr("RUN_SPAR") % slain_name(Game.slain_by)
	# a night lost to something with advice: how to meet it next time
	var tip := slain_tip(Game.slain_by) if not won else ""
	if tip != "":
		best.text += "\n" + tr(tip)
	# a night lost with moves still unknown: the yard is where they are learnt
	elif not won and not (Profile.data.moves_done.has("lunge") and Profile.data.moves_done.has("cleave")
			and Profile.data.moves_done.has("sweep")):
		best.text += "\n" + tr("RUN_PRACTICE_TIP")
	var names: Array = Game.abilities.map(func(a: Dictionary) -> String: return tr(a.name))
	for id in Game.resonances:
		names.append("◆ " + tr(str(Resonances.spec(id).get("name", id))))
	gifts.text = "%s: %s" % [tr("RUN_GIFTS"), ", ".join(names)] if not names.is_empty() else ""
	Audio.music("end")
	Audio.play(&"victory" if won else &"defeat", -2.0, 0.0)
	backdrop.texture = BACKDROP_WON if won else BACKDROP_DEAD
	vignette.color = Color(0.55, 0.45, 0.2, 0.32) if won else Color(0.45, 0.02, 0.05, 0.38)
	glow.modulate = Color(1.0, 0.85, 0.5) if won else Color(0.8, 0.25, 0.25)
	visible = true
	modulate.a = 0.0
	content.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	tween.tween_property(content, "modulate:a", 1.0, 0.6)
	if %Retry.visible:
		%Retry.grab_focus()
	else:
		%Menu.grab_focus()


## The night's numbers: dealt, the heaviest blow, taken, parries (Game).
static func numbers_line() -> String:
	return TranslationServer.translate("RUN_NUMBERS") % [roundi(Game.dealt), roundi(Game.heaviest),
		roundi(Game.taken), Game.parries]


## The last blows taken, oldest first: "Last blows: Zealot 12 · Lava 20". "" for none.
static func last_blows_line(blows: Array) -> String:
	var parts: Array[String] = []
	for blow in blows:
		var who := slain_name(str(blow.get("by", "")))
		if who != "":  # a blow from nowhere names nobody
			parts.append("%s %d" % [who, int(blow.get("amount", 0))])
	return TranslationServer.translate("RUN_LAST_BLOWS") % " · ".join(parts) if not parts.is_empty() else ""


## What laid him low, by name: an enemy's, the lava, the drop. "" for nothing known.
static func slain_name(id: String) -> String:
	match id:
		"":
			return ""
		"lava":
			return TranslationServer.translate("SLAIN_LAVA")
		"fall":
			return TranslationServer.translate("SLAIN_FALL")
	if Data.enemies.has(id):
		return TranslationServer.translate(str(Data.enemies[id].get("name", id)))
	return ""


## The advice for what laid him low (an enemy's "tip", the lava's, the drop's), as a key.
static func slain_tip(id: String) -> String:
	match id:
		"lava":
			return "TIP_LAVA"
		"fall":
			return "TIP_FALL"
	return str(Data.enemies[id].get("tip", "")) if Data.enemies.has(id) else ""
