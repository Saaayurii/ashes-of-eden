extends SceneTree
## Real player feet on hand-picked painted masonry in the later rooms. The
## early rooms have their own geometry test; these cover the descending half.

const PROBES := {
	"catacombs_2": [[220, 353], [710, 228], [1110, 521], [1490, 481]],
	"catacombs_3": [[250, 205], [710, 242], [1010, 312], [1520, 659]],
	"crypt_skulls": [[120, 254], [328, 300], [440, 285], [610, 581], [1220, 423], [1520, 603]],
	"crypt_lava": [[320, 261], [1170, 200], [740, 315], [780, 610]],
	"hell_gate": [[255, 405], [330, 315], [350, 492], [1020, 482], [1320, 372], [1560, 563]],
	"church": [[120, 290], [195, 338], [600, 380], [995, 338], [1080, 290]],
	"preacher_nave": [[210, 300], [600, 380], [990, 300]],
}

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("LATE_GEOMETRY_FAIL: " + message)


func _run() -> void:
	for key in PROBES:
		var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(room)
		current_scene = room
		if key == "crypt_skulls":
			for index in [1, 2]:
				var hanger: Node2D = room.get_node("Terrain/Platform%dHangers" % index)
				var cornice: Sprite2D = room.get_node("Terrain/Platform%d_1" % index)
				var footing: CollisionShape2D = room.get_node("Ledges/Platform%dShape" % index)
				_check(hanger.position == cornice.position and hanger.position.y == footing.position.y - 5.0,
					"crypt skulls return ledge %d hangs apart from collision" % index)
		if key in ["church", "preacher_nave"]:
			var decor: Parallax2D = room.get_node("DecorBack")
			_check(decor.scroll_scale == Vector2.ONE,
				"%s interior masonry drifts away from its footing" % key)
		if key == "church":
			for index in [3, 4]:
				var footing: CollisionShape2D = room.get_node("Ledges/Platform%dShape" % index)
				var stone: Polygon2D = room.get_node("Interior/BalconySupports/Platform%dShapeStone" % index)
				var top: float = footing.position.y - (footing.shape as RectangleShape2D).size.y * .5
				_check(stone.position.y == top and stone.polygon[1].x == (footing.shape as RectangleShape2D).size.x,
					"church choir step %d art misses collision" % index)
				for piece in room.get_node("Terrain").get_children():
					if str(piece.name).begins_with("Platform%d_" % index):
						_check(not piece.visible, "church outdoor moss still covers step %d" % index)
		if key == "preacher_nave":
			for pair in [["arch_1", "Platform1Shape"], ["arch_3", "Platform2Shape"]]:
				var arch: Sprite2D = room.get_node("DecorBack/%s" % pair[0])
				var platform: CollisionShape2D = room.get_node("Ledges/%s" % pair[1])
				_check(absf(arch.position.x - platform.position.x) < 0.1,
					"preacher nave %s support misses %s" % pair)
				var corbel: Polygon2D = room.get_node("Interior/BalconySupports/%sCorbel" % pair[1])
				_check(corbel != null and corbel.position.x + (platform.shape as RectangleShape2D).size.x * .5 == platform.position.x
					and corbel.texture == room.get_node("Interior/AuthoredMasonry/PreacherPainting").texture,
					"preacher nave painted corbel misses %s" % pair[1])
		var hero = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(hero)
		hero.controls_enabled = false
		hero.camera.enabled = false
		for probe in PROBES[key]:
			var target := Vector2(probe[0], probe[1])
			hero.place_in_room(target - Vector2(0, 15))
			hero.velocity = Vector2.ZERO
			for frame in 16:
				await physics_frame
			_check(hero.is_on_floor() and absf(hero.position.y + 15.0 - target.y) <= 2.0,
				"%s drawn floor %s disagrees with feet %s" % [key, target, hero.position])
		current_scene = null
		room.queue_free()
		for frame in 3:
			await physics_frame
	print("LATE_ROOMS_GEOMETRY_%s" % ("OK" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
