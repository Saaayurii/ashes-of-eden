extends Node2D
class_name LastFall
## Where he fell last night (Profile.data.last_fall): the body lies there, grey,
## the next night he comes this way. Walking over it says what laid him low
## and gives back a little of the essence that was lost. Once a night
## (Game.flags "last_fall_found"), solo only, never in the practice yard or
## the night of the day (a thing one profile has and another does not).

## Essence the old body gives back.
const ESSENCE := 25.0
const REACH := 18.0
## A room comes up while the body is still where the last room left it, and is
## placed at the spawn a moment later: nothing counts until this has passed.
const SETTLE := 0.4
const DEATH_FRAMES := preload("res://assets/sprites/elian_frames.tres")

var killer := ""
var _taken := false
var _age := 0.0
var _light: GlowLight


## Lays last night's body in [param room] if it fell there; returns it or null.
static func attach(room: Node2D, room_path: String) -> LastFall:
	if Net.active or Game.practice != "" or Game.daily != "" or Game.flags.has("last_fall_found"):
		return null
	var fall: Dictionary = Profile.data.get("last_fall", {}) if Profile.data.get("last_fall") is Dictionary else {}
	if str(fall.get("room", "")) != room_path:
		return null
	var body := LastFall.new()
	body.name = "LastFall"
	body.killer = str(fall.get("by", ""))
	body.position = Vector2(float(fall.get("x", 0.0)), float(fall.get("y", 0.0)))
	room.add_child(body)
	return body


## What tonight's death leaves for tomorrow: the room and the spot, if the
## body lies anywhere one can walk to (not the lava, not the drop).
static func remember(room_path: String, at: Vector2, killer_id: String) -> void:
	if Net.active or Game.practice != "" or Game.daily != "" or killer_id in ["", "lava", "fall"]:
		return
	Profile.data.last_fall = {"room": room_path, "x": snappedf(at.x, 1.0), "y": snappedf(at.y, 1.0), "by": killer_id}


func _ready() -> void:
	var corpse := AnimatedSprite2D.new()
	corpse.name = "Corpse"
	corpse.sprite_frames = DEATH_FRAMES
	corpse.animation = &"death"
	corpse.frame = DEATH_FRAMES.get_frame_count(&"death") - 1
	corpse.position = Vector2(0, -15)  # where the hero's own Body sits (player.tscn)
	corpse.modulate = Color(0.7, 0.7, 0.76, 0.9)
	add_child(corpse)
	_light = Fx.light(self, Vector2(0, -8), Color(0.75, 0.8, 0.95), 40.0, 0.35, 0.15)


## Our own living body within reach, once the room has settled.
func _physics_process(delta: float) -> void:
	if _age == 0.0:
		_settle_on_floor()
	_age += delta
	if _taken or _age < SETTLE:
		return
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority() and not body.is_dead() \
				and body.global_position.distance_to(global_position) <= REACH:
			_take()
			return


## A body killed in the air does not hang there: down to the first floor or
## ledge below where it fell (world 1, ledges 5).
func _settle_on_floor() -> void:
	var query := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -6), global_position + Vector2(0, 600), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit.position as Vector2).y


func _take() -> void:
	_taken = true
	Game.flags["last_fall_found"] = true
	Profile.data.last_fall = {}  # found: it does not lie there another night
	Profile.save()
	Game.add_essence(ESSENCE)
	var line := tr("LAST_FALL") if killer == "" or not Data.enemies.has(killer) \
		else tr("LAST_FALL_BY") % tr(str(Data.enemies[killer].get("name", killer)))
	Fx.popup(global_position + Vector2(0, -40), line, Color(0.85, 0.85, 0.95), 8)
	# and Elian says a word over it, in the voice of the path he leans to
	var run := get_tree().current_scene
	if run != null and run.get("dialogue") != null:
		run.dialogue.play("ch1_last_fall")
	Fx.ash(global_position + Vector2(0, -10), Color(0.8, 0.8, 0.9, 0.7), 14, 30.0, 8.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.2)
	if _light != null:
		tween.parallel().tween_method(_light.set_base_energy, 0.35, 0.0, 1.2)
	tween.tween_callback(queue_free)
