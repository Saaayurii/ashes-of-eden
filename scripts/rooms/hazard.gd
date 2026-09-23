extends Area2D
class_name Hazard
## Lava (and anything else that burns): touching it hurts, then the body is
## put back on the last floor it stood on (Player.burn). Walkers that blunder
## in are gone; flyers pass over. The painting already shows the lava — this
## adds the heat: embers rising off the surface and a glow along it.
##
## Placed by the room generator from "hazards": [(x, y, w, h)] in
## tools/rooms/painted_rooms.py.

@export var size := Vector2(100, 30)
@export var damage := 20.0
@export var tint := Color(1.0, 0.45, 0.15)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4  # players, enemies
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size / 2.0
	add_child(shape)
	_dress()


## Every frame, not on entry: a body that stays in the lava keeps burning
## (Player.burn spaces the hits out itself).
func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		_touch(body)


## The lava in world space, a little wider: no safe footing is ever inside it.
func danger_rect() -> Rect2:
	return Rect2(global_position, size).grow(24.0)


func _touch(body: Node) -> void:
	if body is Player:
		(body as Player).burn(damage, danger_rect())
	elif body is Enemy and not (body as Enemy).is_dead() and not body.call("_is_flying"):
		# enemies live on the host: only it decides one has burned
		if not Net.active or Net.is_server():
			body.take_damage(9999.0, self)


## Embers off the whole surface and a light every ~90 px along it.
func _dress() -> void:
	var embers := CPUParticles2D.new()
	embers.position = Vector2(size.x / 2.0, 4.0)
	embers.amount = maxi(6, int(size.x / 8.0))
	embers.lifetime = 1.6
	embers.preprocess = 1.6
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(size.x / 2.0, 2.0)
	embers.direction = Vector2.UP
	embers.spread = 20.0
	embers.gravity = Vector2(0, -20)
	embers.initial_velocity_min = 15.0
	embers.initial_velocity_max = 45.0
	embers.scale_amount_min = 0.8
	embers.scale_amount_max = 1.8
	embers.color = Color(tint.r * 1.4, tint.g * 1.2, tint.b, 0.9)
	embers.z_index = 2
	add_child(embers)
	var lights := maxi(1, int(size.x / 90.0))
	for i in lights:
		var x := size.x * (i + 0.5) / lights
		Fx.light(self, Vector2(x, 4.0), tint, 70.0, 0.9, 0.25)
