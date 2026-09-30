extends SceneTree
## Real player feet on hand-picked painted masonry in the later rooms. The
## early rooms have their own geometry test; these cover the descending half.

const PROBES := {
	"catacombs_2": [[220, 353], [710, 228], [1110, 521], [1490, 481]],
	"catacombs_3": [[250, 205], [710, 242], [1010, 312], [1520, 659]],
	"crypt_skulls": [[120, 254], [610, 581], [1220, 423], [1520, 603]],
	"crypt_lava": [[320, 261], [1170, 200], [740, 315], [780, 610]],
	"hell_gate": [[255, 405], [330, 315], [350, 492], [1020, 482], [1320, 372], [1560, 563]],
	"church": [[120, 290], [195, 338], [600, 380], [995, 338], [1080, 290]],
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
