extends SceneTree
## The hand-painted passages have a single authored, walkable horizon.
## Keep their floor colliders on the visible stone edge, not a few pixels above
## it (hovering) or below it (sunken feet). Art rows were reviewed in Godot's
## 1600x720 room captures; the edge is remeasured from each PNG here.

const ART_FLOOR_Y := {
	"swamp_threshold": 363,
	"catacombs_threshold": 415,
	"crypt_threshold": 498,
	"ashes_threshold": 392,
	"gate_threshold": 339,
}
const PROBES := [100, 300, 500, 700, 900, 1100, 1300, 1500]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("PASSAGE_ART_FLOOR_FAIL: ", message)


func _run() -> void:
	_check_grounded_animation_feet()
	for name in ART_FLOOR_Y:
		var path := "res://scenes/rooms/%s.tscn" % name
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		await physics_frame
		await physics_frame
		var art_y: int = ART_FLOOR_Y[name]
		var texture := load(room.painting_source) as Texture2D
		_check(texture != null, "%s painting cannot be opened" % name)
		if texture != null:
			var image: Image = texture.get_image()
			image.resize(room.width, room.height, Image.INTERPOLATE_CUBIC)
			var strongest_y := -1
			var strongest_score := -1.0
			for y in range(art_y - 12, art_y + 13):
				var score := 0.0
				for x in PROBES:
					var above: Color = image.get_pixel(x, y)
					var below: Color = image.get_pixel(x, y + 1)
					score += absf(above.r - below.r) + absf(above.g - below.g) + absf(above.b - below.b)
				if score > strongest_score:
					strongest_score = score
					strongest_y = y
			_check(absi(strongest_y - art_y) <= 4,
				"%s painting's continuous stone edge moved from %d to %d" % [name, art_y, strongest_y])
		var floor: CollisionShape2D = room.get_node("Geometry/Floor")
		var shape: RectangleShape2D = floor.shape
		var top: float = floor.position.y - shape.size.y * 0.5
		_check(absf(top - art_y) <= 3.0,
			"%s collider top %.1f differs from the painted edge %d" % [name, top, art_y])
		_check(absf(floor.position.x - room.width * 0.5) < 0.1 and absf(shape.size.x - room.width) < 0.1,
			"%s floor does not span the whole painted walkway" % name)
		for x in PROBES:
			var ray := PhysicsRayQueryParameters2D.create(Vector2(x, art_y - 20), Vector2(x, art_y + 20), 17)
			var hit: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(ray)
			_check(not hit.is_empty() and absf(float(hit.get("position", Vector2.ZERO).y) - art_y) <= 3.0,
				"%s has no physical walkway under x=%d" % [name, x])
		# A ray proves the stone exists, not that the playable body's feet meet it.
		# Keep the same baseline the later-room geometry test uses for the hero.
		var hero = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(hero)
		hero.controls_enabled = false
		hero.camera.enabled = false
		for x in [100, 800, 1500]:
			hero.place_in_room(Vector2(x, art_y - 15))
			hero.velocity = Vector2.ZERO
			for frame in 16:
				await physics_frame
			_check(hero.is_on_floor() and absf(hero.position.y + 15.0 - art_y) <= 2.0,
				"%s hero hovers or sinks at x=%d (feet %.1f, painting %d)" % [name, x, hero.position.y + 15.0, art_y])
		print("  ok   %s: painted edge %d, collider %.1f, eight probes and three hero landings" % [name, art_y, top])
		current_scene = null
		room.queue_free()
		await physics_frame
	print("PASSAGE_ART_FLOOR_%s" % ("OK" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)


func _check_grounded_animation_feet() -> void:
	# The physics body can be perfectly grounded while an animation's opaque
	# boots end several pixels early. Sprite cells are 64 px high and Body sits
	# at -15; a used bottom of 62-64 places the boots on the +15 collider foot.
	var frames := load("res://assets/sprites/elian_frames.tres") as SpriteFrames
	for animation in [&"idle", &"walk", &"run", &"land"]:
		for index in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation, index)
			var image := texture.get_image()
			var used := image.get_used_rect()
			_check(used.end.y >= 62 and used.end.y <= 64,
				"hero %s frame %d visible boots end at row %d, not the collider foot" % [animation, index, used.end.y])
