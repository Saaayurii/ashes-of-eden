@tool
extends TextureProgressBar
class_name OrnateBar
## The game's own meter: an ornate frame cut from the UI pack (assets/ui/bars),
## a dark trough and a tinted fill, nine-patch stretched so one drawing serves
## every width from a cooldown pip to the boss bar. Same Range API as
## ProgressBar, so callers only set value / max_value.

const FRAME := preload("res://assets/ui/bars/bar_under.png")
const FILLS := {
	"red": preload("res://assets/ui/bars/bar_fill_red.png"),
	"blue": preload("res://assets/ui/bars/bar_fill_blue.png"),
	"gold": preload("res://assets/ui/bars/bar_fill_gold.png"),
	"green": preload("res://assets/ui/bars/bar_fill_green.png"),
	"violet": preload("res://assets/ui/bars/bar_fill_violet.png"),
	"white": preload("res://assets/ui/bars/bar_fill_white.png"),
}
## Left cap (the diamond) and right cap (the point) must never stretch.
const CAP_LEFT := 26
const CAP_RIGHT := 12
const CAP_VERTICAL := 6

@export_enum("red", "blue", "gold", "green", "violet", "white") var tint: String = "red":
	set(value):
		tint = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	texture_under = FRAME
	texture_progress = FILLS.get(tint, FILLS.red)
	nine_patch_stretch = true
	stretch_margin_left = CAP_LEFT
	stretch_margin_right = CAP_RIGHT
	stretch_margin_top = CAP_VERTICAL
	stretch_margin_bottom = CAP_VERTICAL
	fill_mode = FILL_LEFT_TO_RIGHT
