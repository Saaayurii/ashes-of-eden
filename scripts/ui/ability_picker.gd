extends Control
class_name AbilityPicker
## After each wave: offers one gift per path (Grace / Temptation / Will).
## Pauses the game while open.

signal chosen(ability: Dictionary)

## One icon per path: Grace = sun, Temptation = blood, Will = crossed swords.
const PATH_ICONS := {
	"grace": preload("res://assets/ui/icons/sun.png"),
	"temptation": preload("res://assets/ui/icons/drop.png"),
	"will": preload("res://assets/ui/icons/swords.png"),
}
const PATH_COLORS := {
	"grace": Color(0.95, 0.85, 0.5),
	"temptation": Color(0.85, 0.3, 0.4),
	"will": Color(0.75, 0.8, 0.9),
}

## Legendary cards should be readable as "this one is different" before the
## text is. Applied to the card itself, so the path colour still owns the text.
const RARITY_TINTS := {
	"common": Color(1.0, 1.0, 1.0),
	"rare": Color(0.86, 0.94, 1.1),
	"epic": Color(1.05, 0.9, 1.15),
	"legendary": Color(1.2, 1.0, 0.7),
}

@onready var cards: HBoxContainer = %Cards


func _ready() -> void:
	visible = false


## [param reroll], when given, deals a new hand: the rosary (Relics) lets the
## player ask for one, Game.rerolls times a night. The hand can always be
## turned down (Refuse): the result is then an empty Dictionary, and the run
## gives the body back some breath instead (Player.refuse_gift).
## [param title], when given, replaces the heading for this hand (a blood
## altar names its price there).
func pick(options: Array[Dictionary], reroll := Callable(), title := "") -> Dictionary:
	var heading := get_node_or_null("Center/VBox/Title") as Label
	if heading != null:
		heading.text = title if title != "" else "PICKER_TITLE"
	_deal(options)
	_reroll = reroll
	_show_reroll()
	_show_refuse()
	visible = true
	Net.set_paused(true)
	if cards.get_child_count() > 0:
		cards.get_child(0).grab_focus()
	var result: Dictionary = await chosen
	if _reroll_button != null:
		_reroll_button.visible = false
	if _refuse_button != null:
		_refuse_button.visible = false
	visible = false
	Net.set_paused(false)
	return result


var _reroll := Callable()
var _reroll_button: Button
var _refuse_button: Button


func _deal(options: Array[Dictionary]) -> void:
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	for ability in options:
		cards.add_child(_make_card(ability))


func _show_reroll() -> void:
	if _reroll_button == null:
		_reroll_button = Button.new()
		_reroll_button.name = "Reroll"
		cards.add_sibling(_reroll_button)
		_reroll_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_reroll_button.pressed.connect(_on_reroll)
	_reroll_button.visible = _reroll.is_valid() and Game.rerolls > 0
	_reroll_button.text = tr("PICKER_REROLL") % Game.rerolls


## Under the cards, after the rosary: none of these.
func _show_refuse() -> void:
	if _refuse_button == null:
		_refuse_button = Button.new()
		_refuse_button.name = "Refuse"
		cards.get_parent().add_child(_refuse_button)
		_refuse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_refuse_button.pressed.connect(func() -> void: chosen.emit({}))
	_refuse_button.text = tr("PICKER_REFUSE")
	_refuse_button.tooltip_text = tr("PICKER_REFUSE_HINT")
	_refuse_button.visible = true


func _on_reroll() -> void:
	if not _reroll.is_valid() or Game.rerolls <= 0:
		return
	var options: Array[Dictionary] = []
	options.assign(_reroll.call())
	if options.is_empty():
		return
	Game.rerolls -= 1
	Audio.play(&"ui_click", -4.0)
	_deal(options)
	_show_reroll()
	if cards.get_child_count() > 0:
		cards.get_child(0).grab_focus()


func _make_card(ability: Dictionary) -> Button:
	var button := Button.new()
	var path: String = ability.get("path", "will")
	var rarity: String = ability.get("rarity", "common")
	button.text = "%s\n\n%s\n\n[%s · %s]" % [tr(ability.name), tr(ability.description),
		tr("PATH_" + path.to_upper()), tr("RARITY_" + rarity.to_upper())]
	# What this gift would wake with the ones already taken (data/resonances):
	# the reason to take a lesser card, said on the card.
	for id in Resonances.completes(ability, Game.abilities):
		button.text += "\n◆ " + tr(str(Resonances.spec(id).get("name", id)))
	button.custom_minimum_size = Vector2(170, 120)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_color_override("font_color", PATH_COLORS.get(path, Color.WHITE))
	# The rarer the gift, the warmer the card reads at a glance.
	button.self_modulate = RARITY_TINTS.get(rarity, Color.WHITE)
	# A gift may carry its own icon (data/abilities: "icon"); the path's is the fallback.
	var own: Texture2D = load(ability.icon) if ability.has("icon") else null
	button.icon = own if own != null else PATH_ICONS.get(path)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_constant_override("h_separation", 6)
	button.pressed.connect(func() -> void: chosen.emit(ability))
	return button
