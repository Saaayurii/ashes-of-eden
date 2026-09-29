extends Control
class_name EndScreen
## Death / victory page. A line from whoever the player leaned towards,
## the night's numbers, the gifts taken, and a retry one tap away.

signal retry
signal to_menu

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


func _ready() -> void:
	visible = false
	%Retry.pressed.connect(retry.emit)
	%Menu.pressed.connect(to_menu.emit)


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
	var names: Array = Game.abilities.map(func(a: Dictionary) -> String: return tr(a.name))
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
