extends Area2D
class_name RestPoint
## A place to rest (data/rest_points: a room and a point on its floor, set at an
## altar or a statue the painting already has — nothing is drawn but its light).
## Standing there with no enemy on your heels, `interact` rests: the body is
## whole again and every flask full, the autosave says so — and the room's
## common dead get up again where they first stood. Elites and bosses stay
## dead. Once a night per rest point (docs/BALANCE.md).

const REACH := 26.0
## An awake enemy this close and there is no resting.
const SAFE_RADIUS := 220.0

var room_path := ""
var _marker: Label
var _light: GlowLight


## Every room that has one gets it here, the same node on every peer.
static func attach(room: Node2D) -> void:
	var key := room.scene_file_path.get_file().get_basename()
	var spec: Dictionary = Data.rest_points.get(key, {})
	if spec.is_empty():
		return
	var point := RestPoint.new()
	point.name = "RestPoint"
	point.room_path = room.scene_file_path
	var at: Array = spec.get("at", [0, 0])
	point.position = Vector2(float(at[0]), float(at[1]))
	room.add_child(point)


func _ready() -> void:
	add_to_group("interactable")  # the touch pad shows its talk button here
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = REACH
	shape.shape = circle
	shape.position = Vector2(0, -12)
	add_child(shape)
	_light = Fx.light(self, Vector2(0, -22), Color(1.0, 0.78, 0.45), 70.0, 0.25 if spent() else 0.75, 0.25)
	_marker = Label.new()
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.position = Vector2(-40, -58)
	_marker.size = Vector2(80, 14)
	_marker.add_theme_font_size_override("font_size", 8)
	_marker.modulate = Color(1.0, 0.9, 0.7)
	_marker.z_index = 3
	_marker.visible = false
	add_child(_marker)


func spent() -> bool:
	return Game.rested.has(room_path)


func _process(_delta: float) -> void:
	var body := _local_body()
	_marker.visible = body != null and not Game.cutscene
	if not _marker.visible:
		return
	_marker.text = "%s  %s" % [Settings.key_name("interact"), tr("REST_PROMPT")]
	_marker.modulate.a = 0.45 if spent() else 1.0
	if Input.is_action_just_pressed("interact") and body.is_on_floor():
		rest(body)


## Our own body, standing here and alive.
func _local_body() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority() and not body.is_dead() \
				and body.global_position.distance_to(global_position) <= REACH:
			return body
	return null


func rest(body: Player) -> bool:
	if spent():
		Fx.popup(global_position + Vector2(0, -44), tr("REST_SPENT"), Color(0.8, 0.78, 0.85), 8)
		return false
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null and not enemy.is_dead() and enemy.aware \
				and enemy.global_position.distance_to(global_position) <= SAFE_RADIUS:
			Fx.popup(global_position + Vector2(0, -44), tr("REST_ENEMIES"), Color(1.0, 0.6, 0.5), 8)
			return false
	Game.rested[room_path] = true
	body.rest()
	Audio.play(&"bell", -9.0)
	Fx.flash(global_position + Vector2(0, -20), Color(1.0, 0.85, 0.6), 120.0, 1.0, 1.3)
	Fx.sparkle(global_position + Vector2(0, -10), Color(1.0, 0.85, 0.6), 18, 16.0)
	Fx.popup(global_position + Vector2(0, -44), tr("REST_DONE"), Color(1.0, 0.9, 0.7), 8)
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.75, 0.25, 1.2)
	EventBus.player_rested.emit(room_path)
	return true
