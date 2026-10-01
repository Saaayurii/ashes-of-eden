extends SceneTree
## The deeds mirrored to a store (StoreBridge, docs/STEAM.md), against a
## stand-in for GodotSteam's singleton:
##   - with no store in the build nothing happens and nothing breaks;
##   - a store that will not start (Steam not running) is not used;
##   - on start every deed already done is mirrored, once, with one storeStats;
##   - a deed done afterwards reaches the store the moment it is done;
##   - one the store already has is not set again.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/store_test.gd

var failures := 0


class FakeSteam extends Object:
	var status := 0
	var achieved := {}
	var set_calls: Array[String] = []
	var stores := 0
	var polls := 0

	func steamInitEx() -> Dictionary:
		return {"status": status, "verbal": "fake"}

	func setAchievement(name: String) -> bool:
		set_calls.append(name)
		achieved[name] = true
		return true

	func getAchievement(name: String) -> Dictionary:
		return {"ret": true, "achieved": achieved.get(name, false)}

	func storeStats() -> bool:
		stores += 1
		return true

	func run_callbacks() -> void:
		polls += 1


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var profile = root.get_node("Profile")
	var bridge = load("res://scripts/meta/store_bridge.gd")
	var saved: Dictionary = profile.data.duplicate(true)

	_check(not Engine.has_singleton("Steam") and not bridge.start() and bridge.steam() == null,
		"a build without GodotSteam has no store")
	_check(bridge.mirror(["first_night"]) == 0, "  and mirroring is a no-op")

	var fake := FakeSteam.new()
	Engine.register_singleton("Steam", fake)
	fake.status = 2  # Steam not running
	_check(not bridge.start() and bridge.steam() == null, "a Steam that does not start is not used")

	fake.status = 0
	profile.data.achievements = {"first_night": 1, "dawn": 2}
	fake.achieved = {"dawn": true}  # done on another machine, already on the store
	_check(bridge.start() and bridge.steam() == fake, "a running Steam is taken")
	_check(fake.set_calls == ["first_night"] and fake.stores == 1,
		"  every deed already done is mirrored, the store's own left alone (%s, %d)" % [fake.set_calls, fake.stores])
	_check(bridge.sync() == 0 and fake.stores == 1, "  and a second sync tells it nothing")

	# a deed done now reaches the store at once
	profile.data.deeds = {"refusals": 10}
	var fresh: Array = profile.check_achievements()
	_check(fresh.has("ascetic") and fake.set_calls.has("ascetic") and fake.stores == 2,
		"a deed done now reaches the store the moment it is done (%s)" % [fake.set_calls])
	bridge.poll()
	_check(fake.polls == 1, "the store's callbacks are pumped")

	Engine.unregister_singleton("Steam")
	bridge.start()  # back to no store
	fake.free()
	profile.data = saved
	profile.save()
	await process_frame
	print("STORE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
