extends Control
class_name DuelHud
## Duel furniture: your bar on the left, your opponent's on the right, the score
## between them, and one big line in the middle for the beat that just happened.

signal rematch
signal to_menu

@onready var my_name: Label = %MyName
@onready var my_hp: ProgressBar = %MyHp
@onready var my_charges: Label = %MyCharges
@onready var foe_name: Label = %FoeName
@onready var foe_hp: ProgressBar = %FoeHp
@onready var score: Label = %Score
@onready var banner_label: Label = %Banner
@onready var result: Control = %Result
@onready var result_title: Label = %ResultTitle
@onready var rematch_button: Button = %Rematch
@onready var menu_button: Button = %Menu

var _foe: Player
var _banner_left := 0.0


func _ready() -> void:
	result.visible = false
	banner_label.text = ""
	foe_name.text = ""
	foe_hp.visible = false
	EventBus.player_hp_changed.connect(_on_my_hp)
	EventBus.heal_charges_changed.connect(_on_my_charges)
	rematch_button.pressed.connect(rematch.emit)
	menu_button.pressed.connect(to_menu.emit)


func _process(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		if _banner_left <= 0.0:
			banner_label.text = ""
	if _foe != null and is_instance_valid(_foe):
		foe_hp.max_value = _foe.stats.max_hp
		foe_hp.value = _foe.hp


func name_yourself(text: String) -> void:
	my_name.text = text


## The other body to draw a bar for. Null while we wait for them to arrive.
func track(foe: Player, text: String) -> void:
	_foe = foe
	foe_name.text = text
	foe_hp.visible = foe != null


func set_score(mine: int, theirs: int) -> void:
	score.text = "%d   –   %d" % [mine, theirs]


## One line, held for a beat. Empty text clears it at once.
func banner(text: String, seconds := 1.6) -> void:
	banner_label.text = text
	_banner_left = seconds if text != "" else 0.0


func show_result(won: bool, mine: int, theirs: int, can_rematch: bool) -> void:
	banner("")
	set_score(mine, theirs)
	result_title.text = "DUEL_VICTORY" if won else "DUEL_DEFEAT"
	result_title.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.5) if won else Color(0.85, 0.4, 0.42))
	rematch_button.visible = can_rematch
	result.visible = true
	if can_rematch:
		rematch_button.grab_focus()
	else:
		menu_button.grab_focus()


func _on_my_hp(hp: float, max_hp: float) -> void:
	my_hp.max_value = max_hp
	my_hp.value = hp


func _on_my_charges(current: int, maximum: int) -> void:
	my_charges.text = "✚ ".repeat(current).strip_edges() + " " + "· ".repeat(maxi(0, maximum - current)).strip_edges()
