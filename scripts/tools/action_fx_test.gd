extends SceneTree
## Particles on actions (data/action_fx.json, scripts/fx/action_fx.gd): an
## animation's start, its frames (once each, every lap), a timer while it plays,
## and the events the game names. Untyped: -s scripts compile before autoloads.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _run() -> void:
	await process_frame
	var action_fx = load("res://scripts/fx/action_fx.gd")
	# the game's own table first: Elian's footfall is data now, with what the code drew
	var elian: Dictionary = action_fx.rules("elian")
	_check(elian.has("step") and elian.has("land") and elian.has("roll"), "Elian's dust lives in data/action_fx.json")
	action_fx.use({"t": {
		"run": [{"fx": "dust", "when": "start"}, {"fx": "sparkle", "when": "frames", "frames": [0, 2]}],
		"idle": [{"fx": "puff", "when": "every", "every": 0.1}],
		"step": [{"fx": "dust"}, {"fx": "debris", "chance": 0.0}],
	}})
	var owner := Node2D.new()
	root.add_child(owner)
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	for anim in ["run", "idle"]:
		frames.add_animation(anim)
		for i in 4:
			frames.add_frame(anim, PlaceholderTexture2D.new())
		frames.set_animation_speed(anim, 10.0)
	sprite.sprite_frames = frames
	owner.add_child(sprite)
	action_fx.attach(owner, sprite, "t")
	await process_frame
	var before: int = action_fx.emitted
	sprite.play("run")
	await process_frame
	_check(action_fx.emitted - before == 2, "run starts: its start emitter and frame 0 (%d)" % (action_fx.emitted - before))
	before = action_fx.emitted
	for i in 4:
		sprite.frame = i
	sprite.frame = 0
	_check(action_fx.emitted - before == 2, "frames 2 and 0 again on the next lap, each once (%d)" % (action_fx.emitted - before))
	before = action_fx.emitted
	sprite.play("idle")
	await create_timer(0.35).timeout
	_check(action_fx.emitted - before >= 3, "every 0.1 s while idle plays (%d)" % (action_fx.emitted - before))
	before = action_fx.emitted
	action_fx.event(owner, "step")
	_check(action_fx.emitted - before == 1, "an event fires its emitters; chance 0 never does")
	owner.queue_free()
	await process_frame
	print("ACTION FX TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
