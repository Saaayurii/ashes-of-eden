extends Node
class_name Darkness
## Bought light (docs/CHAPTER4.md §2, §9): a room with "dark" in its table gets
## this node from the generator. It sinks the room's night (`Ambient`) toward
## black by that share, and what is left to see is what is lit — the lamps
## (`Lamp`), the painting's own fires, bolts, bodies with a light of their own
## and the hero's lantern, which every body carries here.
##
## The wind-up is sacred: every enemy's wind-up lights itself (`telegraph`,
## called from Enemy._telegraph), never shorter than in the light, and every
## body outside the light still shows two pixels of eyes. Cosmetic and local
## on every peer, like BackdropLife; what play reads (`lit_at`, `dark`) does not
## depend on the "Lighting" setting, only what is drawn does.

## The lantern every body carries in a dark room, in pixels of radius.
const HERO_LANTERN := 64.0
## What Zacchaeus's light (`zacchaeus_sold`) adds to it for the night.
const BOUGHT_LANTERN := 48.0
## What the night sinks to at dark 1.
const NIGHT := Color(0.03, 0.03, 0.05)
const MAX_DARK := 0.95
## A wind-up's own light: never smaller, ramping from 0.3 to 1.0.
const WINDUP_RADIUS := 56.0
const WINDUP_COLOR := "#ffe6a0"
## Along a beam's line, a light every this many pixels while it winds up.
const BEAM_STEP := 110.0
## From this nominal darkness on, `dark_adapted` bodies are at home.
const ADAPTED_FROM := 0.5
## A light this dim no longer counts as light (a dying flash).
const LIT_ENERGY := 0.2
## Within this share of a light's radius a body counts as lit.
const LIT_SHARE := 0.6

## The room's nominal darkness, 0..0.95 (the table's "dark").
@export var dark := 0.0
## After the Prince douses the room: what a lamp costs to light again, × its price.
var relight_price := 1.0
var doused := false

var _ambient: CanvasModulate
var _base := Color.WHITE
var _shown := 0.0


## The room's darkness, or null in a lit room.
static func of(tree: SceneTree) -> Darkness:
	if tree == null:
		return null
	return tree.get_first_node_in_group("darkness") as Darkness


## The room's nominal darkness after the night's rules (an omen's "dark"):
## what play reads, whatever the screen shows.
static func depth(tree: SceneTree) -> float:
	var node := of(tree)
	if node == null or Game.practice != "":
		return 0.0
	return clampf(node.dark * float(Vials.rules().get("dark", 1.0)), 0.0, MAX_DARK)


## Whether a `dark_adapted` body is at home in this room (nominal ≥ 0.5).
static func adapted_room(tree: SceneTree) -> bool:
	return depth(tree) >= ADAPTED_FROM


func _ready() -> void:
	add_to_group("darkness")
	_ambient = get_parent().get_node_or_null("Ambient") as CanvasModulate
	if _ambient != null:
		_base = _ambient.color
	_shown = _target()
	_apply()


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target(), delta * 0.8)
	_apply()
	for node in get_tree().get_nodes_in_group("player"):
		_lantern(node as Node2D)
	for node in get_tree().get_nodes_in_group("enemies"):
		_eyes(node as Node2D)


## How dark it looks to us: the nominal depth, less our own body's dark_sight;
## none at all with the lights off (the dark would hide everything, not only
## the unlit) or in the yard.
func _target() -> float:
	if not Settings.lighting or Game.practice != "":
		return 0.0
	var sight := 0.0
	var own := _own_body()
	if own != null:
		sight = float(own.stats.get("dark_sight", 0.0))
	return clampf(depth(get_tree()) - sight, 0.0, MAX_DARK)


## What is shown now (eased toward the target, so a douse falls, not snaps).
func shown() -> float:
	return _shown


func _apply() -> void:
	if _ambient != null:
		_ambient.color = _base.lerp(NIGHT, _shown)


func _own_body() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority():
			return body
	return null


## The lantern's reach for [param body]: ours from our stats, a partner's
## from its replicated `lantern`.
static func lantern_radius(body: Node) -> float:
	var extra := 0.0
	if body is Player:
		var player := body as Player
		extra = float(player.stats.get("lantern", 0.0)) if player.is_multiplayer_authority() else player.lantern
	if Game.flags.has("zacchaeus_sold"):
		extra += BOUGHT_LANTERN
	return HERO_LANTERN + extra


func _lantern(body: Node2D) -> void:
	if body == null:
		return
	var player := body as Player
	if player != null and player.is_multiplayer_authority():
		player.lantern = float(player.stats.get("lantern", 0.0))
	var light := body.get_node_or_null("DarkLantern") as GlowLight
	if light == null:
		light = Fx.light(body, Vector2(0, -14), Color("#ffd89a"), HERO_LANTERN, 0.9, 0.12, 0.05)
		light.name = "DarkLantern"
		light.add_to_group("lanterns")
	light.radius = lantern_radius(body)
	light.visible = player == null or not player.is_dead()


## Two pixels of eyes on a body outside the light (rule 5): a tiny light of
## their own lifts them out of the black, so nobody is ever invisible.
func _eyes(body: Node2D) -> void:
	var enemy := body as Enemy
	if enemy == null:
		return
	var eyes := enemy.get_node_or_null("DarkEyes") as Node2D
	if eyes == null:
		eyes = _make_eyes(enemy)
	var head := eyes_at(enemy)
	eyes.position = Vector2(head.x * enemy.facing, head.y)
	eyes.visible = not enemy.is_dead() and _shown > 0.2 and not lit_at(get_tree(), enemy.global_position, enemy)


## Where a body's eyes sit, from its sprite ("eyes": [dx, dy]) or its size.
static func eyes_at(enemy: Enemy) -> Vector2:
	var spec: Dictionary = enemy.stats.get("sprite", {})
	if spec.get("eyes") is Array and (spec.eyes as Array).size() == 2:
		return Vector2(float(spec.eyes[0]), float(spec.eyes[1]))
	var size := float(enemy.stats.get("size", 12))
	return Vector2(size * 0.2, -size * 1.4)


func _make_eyes(enemy: Enemy) -> Node2D:
	var eyes := Node2D.new()
	eyes.name = "DarkEyes"
	eyes.z_index = 4
	var tint := Color(enemy.stats.get("eyes_color", "#fff2c8"))
	for dx in [0.0, 3.0]:
		var dot := Sprite2D.new()
		dot.texture = _pixel_texture()  # 1:1, like Fx.PIXELS
		dot.centered = false
		dot.position = Vector2(dx, 0)
		dot.modulate = tint
		eyes.add_child(dot)
	# a light only as wide as the eyes: it lifts them, not the body
	var glint := GlowLight.new()
	glint.name = "Glint"
	glint.radius = 4.0
	glint.color = tint
	glint.energy = 3.0
	glint.position = Vector2(2, 0.5)
	glint.add_to_group("eyes_light")
	eyes.add_child(glint)
	enemy.add_child(eyes)
	return eyes


static var _dot: Texture2D
static func _pixel_texture() -> Texture2D:
	if _dot == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_dot = ImageTexture.create_from_image(image)
	return _dot


## Whether [param at] stands in light: within LIT_SHARE of the radius of any
## light that is on (lamps, the painting's fires, lanterns, a body's own
## light, a wind-up). Geometric, so play reads it the same with the lights
## off. [param lamps_only] counts only bought lamps (what `dark_adapted` fears).
## A body's eyes never count as light, nor its own lantern for [param self_body].
static func lit_at(tree: SceneTree, at: Vector2, self_body: Node = null, lamps_only := false) -> bool:
	if tree == null:
		return true
	for node in tree.get_nodes_in_group("lamp_light" if lamps_only else "lights"):
		var light := node as GlowLight
		if light == null or not light.is_inside_tree() or not light.visible:
			continue
		if light.is_in_group("eyes_light"):
			continue
		if self_body != null and light.is_in_group("lanterns") and self_body.is_ancestor_of(light):
			continue
		if light.energy < LIT_ENERGY:
			continue
		if light.global_position.distance_to(at) <= light.radius * LIT_SHARE:
			return true
	return false


## The wind-up lights itself (rule 1): a light on the body, ≥ 48 px, from 0.3
## to 1.0 over the wind-up, gone with the blow; along a beam, lights on its
## line. Called from Enemy._telegraph on every peer; nothing in a lit room.
static func telegraph(enemy: Node2D, duration: float, color := "", beam := false, length := 0.0) -> void:
	if enemy == null or of(enemy.get_tree()) == null:
		return
	clear_telegraph(enemy)
	var tint := Color(color if color != "" else WINDUP_COLOR)
	var lights: Array[GlowLight] = [Fx.light(enemy, Vector2(0, -10), tint, WINDUP_RADIUS, 0.3)]
	lights[0].name = "WindupLight"
	if beam:
		var steps := int(length / BEAM_STEP)
		for i in range(1, steps + 1):
			for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
				var along := Fx.light(enemy, axis * BEAM_STEP * i, tint, WINDUP_RADIUS, 0.3)
				along.name = "WindupBeam"
				lights.append(along)
	for light in lights:
		light.add_to_group("windup_light")
		var tween := light.create_tween()
		tween.tween_method(light.set_base_energy, 0.3, 1.0, maxf(0.05, duration))
		tween.tween_interval(0.12)
		tween.tween_method(light.set_base_energy, 1.0, 0.0, 0.15)
		tween.tween_callback(light.queue_free)


## The blow landed or was broken: the wind-up's light goes with it.
static func clear_telegraph(enemy: Node) -> void:
	if enemy == null:
		return
	for child in enemy.get_children():
		if child is GlowLight and (child as GlowLight).is_in_group("windup_light"):
			(child as GlowLight).remove_from_group("windup_light")
			child.remove_from_group("lights")
			child.queue_free()


## The Prince takes back what he sold (docs/CHAPTER4.md §6): every lamp goes
## out, bought ones too, the painting's fires with them, and the room sinks to
## [param new_dark]. A lamp that had a price can be bought again at
## [param price] × it. Local on every peer (the host sends `_net_douse`).
func douse_all(new_dark: float, price: float) -> void:
	doused = true
	dark = clampf(new_dark, 0.0, MAX_DARK)
	relight_price = price
	for node in get_tree().get_nodes_in_group("lamps"):
		if node.has_method("douse"):
			node.douse(price)
	# the painted fires and fixtures of the room go out with them (not a body's own)
	var room := get_parent()
	for node in get_tree().get_nodes_in_group("lights"):
		var light := node as GlowLight
		if light == null or not room.is_ancestor_of(light) or light.is_in_group("lamp_light"):
			continue
		if _carried(light):
			continue
		light.create_tween().tween_method(light.set_base_energy, light.energy, 0.0, 0.6)
		light.remove_from_group("lights")


## A light that belongs to a body (an enemy's crown, a lantern, a bolt) stays.
static func _carried(light: Node) -> bool:
	var at := light.get_parent()
	while at != null:
		if at is Enemy or at is Player or at.is_in_group("projectiles"):
			return true
		at = at.get_parent()
	return false


## Whether [param body] stands outside every light in a dark room (Usurer's
## Edge): never in a lit room.
static func unlit(body: Node2D) -> bool:
	if body == null or depth(body.get_tree()) <= 0.0:
		return false
	return not lit_at(body.get_tree(), body.global_position, body)


## Honest Scales: a parry lights FLARE_RADIUS around [param body] for
## [param seconds] — in any room, but it counts only where it is dark.
const FLARE_RADIUS := 110.0
static func flare(body: Node2D, seconds: float) -> void:
	var old := body.get_node_or_null("ParryFlare")
	if old != null:
		old.remove_from_group("lights")
		old.queue_free()
	var light := Fx.light(body, Vector2(0, -12), Color("#fff2c8"), FLARE_RADIUS, 1.0, 0.05)
	light.name = "ParryFlare"
	var tween := light.create_tween()
	tween.tween_interval(maxf(0.0, seconds - 0.4))
	tween.tween_method(light.set_base_energy, 1.0, 0.0, 0.4)
	tween.tween_callback(light.queue_free)
