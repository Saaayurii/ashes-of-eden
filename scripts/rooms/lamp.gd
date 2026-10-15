extends Node2D
class_name Lamp
## A lamp of Tyre (docs/CHAPTER4.md §2, §9): a prop with "kind": "lamp" gets
## this child. Bought with essence on `interact` it burns, radius `radius`,
## until the night ends in this room (`Game.lamps_lit`, saved with the
## checkpoint: a load restarts the room, so what was bought after it is dark
## again). Keys of the prop:
##   price    essence, × the night's `lamp_price`; 0 = free on `interact`
##   radius   its light (150), color (#ffcf70)
##   lit      burns from the start (somebody already paid)
##   free_if  a flag: burns from the start, for nothing, when the story set it
## Who pays is the buyer: `lamp_blood` pays in blood (Player.pay_blood),
## `mite` lights it with all the essence there is when that is not enough.
## Online the essence is the host's, so a guest asks (`_net_buy`) and the host
## lights it for everyone (`_net_light`).

const RADIUS := 150.0
const COLOR := "#ffcf70"
## Over the lamp, while our body stands at it.
const REACH := 26.0

var price := 0
var lit := false
## After the Prince's douse: a lamp that had a price sells again at this × it.
var relight := 1.0
var _prop: Node2D
var _light: GlowLight
var _prompt: Label
var _spec: Dictionary = {}


## Hangs a lamp on [param prop] (Prop._ready, kind "lamp").
static func attach(prop: Node2D, spec: Dictionary) -> Lamp:
	var lamp := Lamp.new()
	lamp.name = "Lamp"
	lamp._prop = prop
	lamp._spec = spec
	prop.add_child(lamp)
	return lamp


func _ready() -> void:
	add_to_group("lamps")
	price = int(_spec.get("price", 20))
	_prop.add_to_group("interactable")
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-60, -float(_spec.get("prompt_height", 56)))
	_prompt.size = Vector2(120, 14)
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.z_index = 3
	_prompt.visible = false
	add_child(_prompt)
	var burning: bool = _spec.get("lit", false) or Game.lamps_lit.has(key())
	if _spec.has("free_if") and Game.flags.has(str(_spec.free_if)):
		burning = true
	if burning:
		_light_up(false)
	else:
		_show_frame(false)


## What names this lamp in `Game.lamps_lit`: the room's scene and the prop's node.
func key() -> String:
	var room := _prop.get_parent()
	while room != null and not (room is Room):
		room = room.get_parent()
	var scene := room.scene_file_path if room != null else ""
	return "%s:%s" % [scene.get_file().get_basename(), _prop.name]


## What it costs now: its price, the night's `lamp_price`, after a douse ×relight.
func cost() -> int:
	return int(round(price * float(Vials.rules().get("lamp_price", 1.0)) * relight))


## Can be bought: not burning, and a price or a relight to sell it by.
func for_sale() -> bool:
	return not lit and (price > 0 or relight == 1.0)


func _process(_delta: float) -> void:
	var taker := _local_taker()
	_prompt.visible = taker != null and not lit and for_sale() and not Game.cutscene
	if not _prompt.visible:
		return
	var how := payment(taker)
	if how == "":
		_prompt.text = tr("PROMPT_LAMP_POOR")
		_prompt.modulate = Color(0.6, 0.6, 0.62)
		return
	var shown := tr("PROMPT_LAMP").format({"price": cost()})
	_prompt.text = "%s  %s" % [Settings.key_name("interact"), shown]
	_prompt.modulate = Color(1.0, 0.86, 0.55)
	if Input.is_action_just_pressed("interact"):
		buy(taker)


## How [param taker] would pay: "free", "blood", "essence", "mite", or "" (cannot).
func payment(taker: Node) -> String:
	var amount := cost()
	if amount <= 0:
		return "free"
	var body_stats: Dictionary = taker.stats if taker is Player else {}
	if float(body_stats.get("lamp_blood", 0.0)) > 0.0:
		return "blood"
	if Game.essence >= amount:
		return "essence"
	if float(body_stats.get("mite", 0.0)) > 0.0:
		return "mite"
	return ""


## [param taker] (our own body) buys the light. Returns whether it was lit.
func buy(taker: Node) -> bool:
	if lit or not for_sale():
		return false
	var how := payment(taker)
	if how == "":
		return false
	if how == "blood":
		(taker as Player).pay_blood(float(taker.stats.get("lamp_blood", 0.0)))
	if Net.active and not multiplayer.is_server():
		_net_buy.rpc_id(1, how)
		_light_up(true)
		return true
	_settle(how)
	_light_up(true)
	if Net.active:
		_net_light.rpc()
	return true


## The essence is the host's to take (the bar is shared).
func _settle(how: String) -> void:
	var amount := cost()
	match how:
		"essence":
			Game.set_essence(maxf(0.0, Game.essence - amount), Game.level)
		"mite":
			Game.set_essence(0.0, Game.level)
	EventBus.lamp_lit.emit(amount, how)


@rpc("any_peer", "call_remote", "reliable")
func _net_buy(how: String) -> void:
	if not multiplayer.is_server() or lit:
		return
	_settle(how)
	_light_up(true)
	_net_light.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _net_light() -> void:
	if not lit:
		_light_up(true)


func _light_up(bought: bool) -> void:
	lit = true
	_prop.remove_from_group("interactable")
	if bought and Game.practice == "":
		Game.lamps_lit[key()] = true
	_show_frame(true)
	if _light == null:
		_light = Fx.light(_prop, Vector2(0, -float(_spec.get("flame_height", 30))),
			Color(str(_spec.get("color", COLOR))), float(_spec.get("radius", RADIUS)), 0.0, 0.18)
		_light.name = "LampLight"
		_light.add_to_group("lamp_light")
	_light.add_to_group("lights")
	_light.create_tween().tween_method(_light.set_base_energy, 0.0, 1.0, 0.4 if bought else 0.01)
	if bought:
		Fx.flash(_light.global_position, Color(str(_spec.get("color", COLOR))), 40.0, 0.4, 1.0)
		Fx.sparkle(_light.global_position, Color(str(_spec.get("color", COLOR))), 8, 6.0)
		Audio.play_at(&"lamp_light", global_position)


## The Prince takes it back (Darkness.douse_all): out, and on sale again at
## [param again] × its price if it had one.
func douse(again: float) -> void:
	lit = false
	relight = again if price > 0 else 0.0
	Game.lamps_lit.erase(key())
	_show_frame(false)
	if for_sale():
		_prop.add_to_group("interactable")
	if _light != null:
		_light.remove_from_group("lamp_light")
		_light.remove_from_group("lights")
		var dying := _light
		_light = null
		var tween := dying.create_tween()
		tween.tween_method(dying.set_base_energy, dying.energy, 0.0, 0.5)
		tween.tween_callback(dying.queue_free)


## Frame 0 unlit, the rest lit (the strip's flame).
func _show_frame(burning: bool) -> void:
	var sprite := _prop.get_node_or_null("Sprite") as Sprite2D
	if sprite != null and sprite.hframes > 1:
		sprite.frame = 1 if burning else 0


func _local_taker() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority() and not body.is_dead() \
				and absf(body.global_position.x - global_position.x) <= REACH \
				and absf(body.global_position.y - global_position.y) <= 30.0:
			return body
	return null
