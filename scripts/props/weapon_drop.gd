extends Node2D
class_name WeaponDrop
## A weapon lying on the floor (data/weapons, docs/WEAPONS.md): laid beside the
## night's weapon chest (Prop._pay_out) or on the practice yard's rack. Standing
## at it shows its name; `interact` takes it in hand, and the one held is laid
## down where it lay — a swap, so nothing is ever lost by trying one. Local to
## the peer whose body found it, like an item.

const REACH := 22.0

var weapon := ""
var _prompt: Label
var _icon: Sprite2D
var _age := 0.0


## Lays [param id] on the floor of [param parent] at [param at] (its local position).
static func lay(parent: Node, id: String, at: Vector2) -> WeaponDrop:
	var drop := WeaponDrop.new()
	drop.name = "Weapon_" + id
	drop.weapon = id
	drop.position = at
	parent.add_child(drop)
	return drop


func _ready() -> void:
	add_to_group("interactable")  # the touch pad shows its talk button here
	z_index = 1
	_icon = Sprite2D.new()
	_icon.position = Vector2(0, -12)
	add_child(_icon)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-70, -40)
	_prompt.size = Vector2(140, 14)
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.modulate = Color(1.0, 0.86, 0.55)
	_prompt.z_index = 3
	_prompt.visible = false
	add_child(_prompt)
	Fx.light(self, Vector2(0, -12), Color(1.0, 0.84, 0.55), 26.0, 0.7, 0.0, 0.4)
	_show()


func _show() -> void:
	var path := str(Weapons.spec(weapon).get("icon", ""))
	_icon.texture = load(path) if ResourceLoader.exists(path) else null


func _process(delta: float) -> void:
	_age += delta
	_icon.position.y = -12.0 + sin(_age * 2.4) * 1.5
	var taker := local_taker()
	_prompt.visible = taker != null and not Game.cutscene
	if not _prompt.visible:
		return
	_prompt.text = "%s  %s" % [Settings.key_name("interact"),
		tr("WEAPON_TAKE") % tr(str(Weapons.spec(weapon).get("name", weapon)))]
	if Input.is_action_just_pressed("interact"):
		take(taker)


## Our own body, alive and standing at it.
func local_taker() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority() and not body.is_dead() \
				and absf(body.global_position.x - global_position.x) <= REACH \
				and absf(body.global_position.y - global_position.y) <= 24.0:
			return body
	return null


## [param taker] takes it; what they held lies here instead.
func take(taker: Player) -> void:
	var dropped := taker.equip(weapon)
	if dropped == "":
		return
	Fx.sparkle(global_position + Vector2(0, -12), Color(1.0, 0.86, 0.55), 10, 10.0)
	Audio.play(&"draw", -4.0)
	Fx.popup(global_position + Vector2(0, -34), tr(str(Weapons.spec(weapon).get("name", weapon))),
		Color(1.0, 0.86, 0.55), 9)
	weapon = dropped
	name = "Weapon_" + dropped
	_show()


## Any weapon lying where our own body stands (the yard asks before its
## `interact` changes the drill).
static func any_at_hand(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group("interactable"):
		if node is WeaponDrop and (node as WeaponDrop).local_taker() != null:
			return true
	return false
