extends Node2D
class_name Room
## One hand-made side-view area. Spawns its enemies, counts them, opens the
## door when the last one dies. The Run scene chains rooms together.

signal cleared
signal exited

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const DEPTH_LAYERS := preload("res://scripts/rooms/depth_layers.gd")
const INTERIOR_ARCHITECTURE := preload("res://scripts/rooms/interior_architecture.gd")
const HELL_DEPTH := preload("res://scripts/rooms/hell_depth.gd")
const ROOM_LAYERS := preload("res://scripts/rooms/room_layers.gd")

@export var width := 1280
## Rooms can be taller than one screen: the camera scrolls down to here.
@export var height := 360
## Optional earlier death line for rooms whose lower painting is only scenery.
@export var void_kill_y := -1.0
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
## Pixel offset of the inpainted far plate per pixel of horizontal camera travel.
@export var depth_parallax := 0.0

var alive := 0
## The run hands us a spawner when it has one (a session replicates its enemies
## instead of each peer making its own). Empty = we spawn them ourselves, which
## is what happens when a room is played straight from the editor.
var spawn_hook := Callable()
## False on a peer that only watches: the host decides when the door opens.
var authoritative := true

var _map_rects: Array[Rect2] = []
var _depth_window_materials: Dictionary = {}
var _depth_window_factors: Dictionary = {}

@onready var door: Door = $Door
@onready var player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	add_to_group("room")
	_ensure_painting()
	_configure_depth_windows()
	HELL_DEPTH.attach(self)
	INTERIOR_ARCHITECTURE.attach(self)
	DEPTH_LAYERS.attach(self)
	if music != "":
		Audio.music(music)
	# The living details of the place (ravens, wisps, fog, lightning): data/ambience.json.
	Ambience.attach(self, scene_file_path.get_file().get_basename(), float(width), float(height))
	# far, middle and front kept apart: after the clouds exist (Ambience)
	ROOM_LAYERS.arrange(self)
	door.entered.connect(exited.emit)
	EventBus.enemy_died.connect(_on_enemy_died)


func _process(_delta: float) -> void:
	if depth_parallax <= 0.0:
		return
	var windows := get_node_or_null("DepthWindows")
	if windows == null or windows.get_child_count() == 0:
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var half_view := camera.get_viewport_rect().size.x / maxf(camera.zoom.x, 0.001) * 0.5
	var camera_left := camera.get_screen_center_position().x - half_view - global_position.x
	var travel := maxf(0.0, camera_left) * depth_parallax
	for group: String in _depth_window_materials:
		var material: ShaderMaterial = _depth_window_materials[group]
		# Keep the sampled inpainting within its hand-cut opening. Large shifts
		# make a painted wall look like a loose decal at the room's far edge.
		material.set_shader_parameter("shift_px", minf(travel * _depth_window_factors[group], 16.0))


func _configure_depth_windows() -> void:
	var windows := get_node_or_null("DepthWindows")
	if windows == null:
		return
	for child in windows.get_children():
		var polygon := child as Polygon2D
		if polygon == null:
			continue
		var source := polygon.material as ShaderMaterial
		if source == null:
			continue
		# All feather triangles of one opening must sample the same plate offset;
		# neighbouring openings can sit at a different apparent depth.
		var group := polygon.name.get_slice("Feather", 0)
		if not _depth_window_materials.has(group):
			_depth_window_materials[group] = source.duplicate() as ShaderMaterial
			var index := maxi(1, int(group.trim_prefix("Window")))
			_depth_window_factors[group] = ROOM_LAYERS.window_factor(self, index,
				clampf(0.68 + 0.16 * (index - 1), 0.68, 1.16))
		polygon.material = _depth_window_materials[group]


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
