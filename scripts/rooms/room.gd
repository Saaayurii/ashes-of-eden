extends Node2D
class_name Room
## One hand-made side-view area. Spawns its enemies, counts them, opens the
## door when the last one dies. The Run scene chains rooms together.

signal cleared
signal exited

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

@export var width := 1280
## Rooms can be taller than one screen: the camera scrolls down to here.
@export var height := 360
## Caption dialogue to play when the room starts (e.g. the boss speaking). Empty = none.
@export var intro_dialogue := ""
## Cutscenes (data/cutscenes) at the start of the room and once it is cleared. Empty = none.
@export var intro_cutscene := ""
@export var outro_cutscene := ""
## File name in assets/audio/music, no extension. Empty = keep whatever is playing,
## which is what a room that shares its neighbour's bed wants.
@export var music := ""
## Original PNG path for a painted room. If its imported texture cache becomes
## invalid, load the image directly instead of showing only fog and props.
@export var painting_source := ""

var alive := 0
## The run hands us a spawner when it has one (a session replicates its enemies
## instead of each peer making its own). Empty = we spawn them ourselves, which
## is what happens when a room is played straight from the editor.
var spawn_hook := Callable()
## False on a peer that only watches: the host decides when the door opens.
var authoritative := true

var _map_rects: Array[Rect2] = []

@onready var door: Door = $Door
@onready var player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	add_to_group("room")
	_ensure_painting()
	if music != "":
		Audio.music(music)
	# The living details of the place (ravens, wisps, fog, lightning): data/ambience.json.
	Ambience.attach(self, scene_file_path.get_file().get_basename(), float(width), float(height))
	door.entered.connect(exited.emit)
	EventBus.enemy_died.connect(_on_enemy_died)


func _ensure_painting() -> void:
	var painting := get_node_or_null("Painting") as Sprite2D
	if painting == null or painting_source.is_empty():
		return
	if painting.texture != null and painting.texture.get_width() >= width:
		return
	var image := Image.new()
	var raw := FileAccess.get_file_as_bytes(painting_source)
	if not raw.is_empty() and image.load_png_from_buffer(raw) == OK:
		painting.texture = ImageTexture.create_from_image(image)
		push_warning("[Room] Recovered painting from source: %s" % painting_source)
		return
	var original := painting_source.replace("_wide.png", ".png")
	var fallback := load(original) as Texture2D
	if fallback != null:
		painting.texture = fallback
		painting.scale.x = float(width) / fallback.get_width()
		push_warning("[Room] Using original painting: %s" % original)


## Every rectangle the room is built from, in room coordinates: the minimap
## draws these. Ground and ledges alike; the walls outside 0..width are skipped.
func map_rects() -> Array[Rect2]:
	if not _map_rects.is_empty():
		return _map_rects
	for holder in [get_node_or_null("Geometry"), get_node_or_null("Ledges")]:
		if holder == null:
			continue
		for child in holder.get_children():
			var shape := child as CollisionShape2D
			if shape == null or not (shape.shape is RectangleShape2D):
				continue
			var size: Vector2 = (shape.shape as RectangleShape2D).size
			var rect := Rect2(shape.position - size / 2.0, size)
			if rect.end.x <= 0.0 or rect.position.x >= width or rect.end.y <= 0.0:
				continue
			_map_rects.append(rect)
	return _map_rects


func populate() -> void:
	for spawn in $Spawns.get_children():
		if spawn is EnemySpawn:
			spawn_enemy(spawn.enemy_id, spawn.global_position)
	if alive == 0:
		door.open = true


## Also used by bosses that summon: everything spawned here must die before the door opens.
## [param aware] skips the patrol: reinforcements arrive already fighting.
func spawn_enemy(enemy_id: String, at: Vector2, aware := false) -> Enemy:
	alive += 1
	if spawn_hook.is_valid():
		return spawn_hook.call(enemy_id, at, aware)
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.enemy_id = enemy_id
	enemy.start_aware = aware
	enemy.global_position = at
	add_child(enemy)
	return enemy


func _on_enemy_died(_id: StringName, _position: Vector2) -> void:
	if not authoritative:
		return
	alive -= 1
	if alive == 0 and not door.open:
		door.open = true
		cleared.emit()
