extends AnimatedSprite2D
## One painted soul shard: a four-frame dissolve with its own ballistic path.

var velocity := Vector2.ZERO
var gravity := 0.0
var spin := 0.0
var drag := 20.0
var lifetime := 1.0
var _age := 0.0
var _initial_scale := 1.0


func configure(initial_velocity: Vector2, pull: float, turn: float,
		duration: float, size: float) -> void:
	velocity = initial_velocity
	gravity = pull
	spin = turn
	lifetime = duration
	_initial_scale = size
	scale = Vector2.ONE * size
	rotation = randf_range(-0.8, 0.8)
	# Four painted frames at four base FPS make one full dissolve per lifetime.
	speed_scale = 1.0 / duration


func _ready() -> void:
	play("dissolve")


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	position += velocity * delta
	velocity.y += gravity * delta
	velocity *= exp(-drag * delta)
	rotation += spin * delta
	var progress := _age / lifetime
	modulate.a = clampf((1.0 - progress) * 2.0, 0.0, 1.0)
	scale = Vector2.ONE * _initial_scale * lerpf(1.0, 0.62, progress)
