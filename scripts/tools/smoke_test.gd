extends SceneTree
## Headless end-to-end run:
##   godot --headless -s scripts/tools/smoke_test.gd
## For every room: kill every enemy, expect the door to open, walk the player
## into it, answer the stranger, pick the first gift. Expects the win screen
## and a recorded profile.
## Deliberately untyped: -s scripts compile before autoloads exist, so naming
## game classes here would compile them too early and fail on Data/Game.
##
## It runs the game faster than real time. Fifteen rooms fought at 1x took the
## best part of an hour, which is too slow to put in front of every pull
## request. Engine.time_scale speeds the world up; the test's own waits are
## made with ignore_time_scale, so polling stays at the same real-world rate
## and the timeouts keep their meaning in wall-clock seconds while the fights
## they are waiting on finish sooner.
##
## Four is where it stopped paying off here: the physics step is unchanged, so
## past that the bodies start passing through each other and the failures are
## the harness's, not the game's. Override for a slow machine:
##   godot --headless -s scripts/tools/smoke_test.gd -- 2
const TIME_SCALE := 4.0

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	Engine.time_scale = float(args[0]) if args.size() > 0 and args[0].is_valid_float() else TIME_SCALE
	print("time scale: %.1fx" % Engine.time_scale)
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var nights_before: int = profile.data.nights
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle()
	var run := current_scene
	_assert(run != null and run.get("player") != null, "run scene loaded")
	var dialogue = run.get_node("UI/DialogueBox")
	var picker = run.get_node("UI/AbilityPicker")
	var run_end = run.get_node("UI/RunEnd")
	var cut = run.get_node("UI/Cutscene")
	# the night follows the chapter's way (scripts/run/route.gd): at a fork the
	# question is skipped below, so it takes the first way, and one room of
	# each fork is never walked
	var route = load("res://scripts/run/route.gd")
	var total_rooms: int = route.length(run.ROOMS)
	var expected_kills := 0
	var index := 0
	var walked := 0

	while index < run.ROOMS.size():
		await _dismiss_ui(dialogue, picker, cut)
		# a quiet room (the church) has nobody to fight: its door is open from the start
		await _wait_until(func(): return run.room_index == index and run.room != null and (run.room.alive > 0 or run.room.get_node("Spawns").get_child_count() == 0), "room %d started with enemies" % (index + 1))
		if index == 0:
			_assert(dialogue.get_node("%Caption").visible, "intro plays as captions over room 1")
		var room = run.room
		var quiet: bool = room.get_node("Spawns").get_child_count() == 0
		_assert(quiet or not room.door.open, "door starts locked")
		for attempt in 10:  # bosses summon reinforcements mid-fight: keep killing
			# The run parents spawned enemies under Entities (the session replicates
			# them from there); a room played straight from the editor keeps its own.
			for enemy in run.entities.get_children() + room.get_children():
				if enemy.has_method("take_damage"):
					enemy.take_damage(9999.0, run.player)
			await _settle(0.5)
			if room.alive == 0:
				break
		expected_kills = run.kills  # summons count too
		_assert(room.alive == 0 and room.door.open, "room %d cleared, door open" % (index + 1))
		await _dismiss_ui(dialogue, picker, cut)  # level-up gifts earned while clearing
		# A gift waits where a place ends, not behind every door (Run._door_grants_gift);
		# ask before we walk through, while this room is still the current one.
		var ends_place: bool = run._door_grants_gift()
		# Walk through the door: teleport the body into it.
		run.player.global_position = room.door.global_position
		await _settle(0.5)
		var saw_picker := await _dismiss_ui(dialogue, picker, cut)
		# no picker once every gift in the pool has been taken (long runs)
		var pool_dry: bool = game.abilities.size() >= root.get_node("Data").abilities.size()
		if ends_place:
			_assert(saw_picker or pool_dry, "gift picker after door %d, where the place ends" % (index + 1))
		walked += 1
		if index + 1 >= run.ROOMS.size():
			break
		# whichever way the answers above took: follow the Run, and check it
		# is one the route allows (the next room, or a way of the fork)
		var was := index
		await _wait_until(func(): return run.room_index != was, "walked out of room %d" % (was + 1))
		index = run.room_index
		var fork: Dictionary = route.fork_after(run.ROOMS[was])
		var allowed: Array = fork.options.values().map(func(p): return run.ROOMS.find(p)) if not fork.is_empty() \
			else [route.next_index(run.ROOMS, was)]
		_assert(allowed.has(index), "room %d leads where the route says" % (was + 1))

	_assert(walked == total_rooms, "the night walked %d rooms, one way through each fork" % walked)

	await _settle()
	_assert(run_end.visible, "run end screen shown")
	_assert(run.player.hp > 0.0, "player alive")
	_assert(run.kills == expected_kills, "all %d enemies counted (%d)" % [expected_kills, run.kills])
	# one gift per door and per level-up, until the pool of gifts runs dry
	var gifts_possible: int = mini(total_rooms, root.get_node("Data").abilities.size())
	_assert(game.abilities.size() >= gifts_possible, "at least one gift per room (%d)" % game.abilities.size())
	_assert(game.level >= 2, "essence levelled up (level %d)" % game.level)
	_assert(game.alignment["will"] >= 1, "stranger choice applied: %s" % game.alignment)
	_assert(game.flags.has("stranger_refused"), "story flag set")
	_assert(profile.data.nights == nights_before + 1, "profile recorded the night")
	_assert(run_end.get_node("%RunEndStats").text.contains(str(run.kills)), "run stats shown")
	await _check_transition(run, root.get_node("Data"))
	print("SMOKE TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)


## The curtain and the chapter card (scripts/autoload/curtain.gd). The run
## above played with them switched off — a tool script does — so they are
## driven once here, by hand, on the run scene that is still standing.
func _check_transition(run, data) -> void:
	var transition = run.transition
	transition.instant = false
	var chapter: Dictionary = data.chapter_for(run.ROOMS[0])
	_assert(not chapter.is_empty(), "room 1 belongs to a chapter (%s)" % chapter.get("id", "-"))
	await transition.cover(chapter, true)
	_assert(transition.visible and transition._progress() > 0.99, "the curtain covers the screen")
	await transition.reveal(chapter, true)
	_assert(transition.get_node("%Title").text != "" and transition.get_node("%Chapter").text != "",
		"the card names the chapter and the place (%s / %s)"
		% [transition.get_node("%Chapter").text, transition.get_node("%Title").text])
	_assert(not transition.get_node("%PassageArt").visible,
		"graveyard card does not reuse the swamp threshold")
	_assert(transition._progress() < 0.01 and not transition.visible, "the curtain opens again")
	_assert(not transition.active, "the controls come back")
	var swamp: Dictionary = data.chapter_for("res://scenes/rooms/swamp_moon.tscn")
	await transition.cover(swamp, true)
	await transition.reveal(swamp, true)
	_assert(transition.get_node("%PassageArt").visible and transition.get_node("%PassageArt").texture != null,
		"swamp card has its own painted threshold")
	var catacombs: Dictionary = data.chapter_for("res://scenes/rooms/catacombs_1.tscn")
	await transition.cover(catacombs, true)
	await transition.reveal(catacombs, true)
	_assert(transition.get_node("%PassageArt").visible and transition.get_node("%PassageArt").texture != null,
		"catacombs card has its own painted threshold")
	var crypts: Dictionary = data.chapter_for("res://scenes/rooms/crypt_skulls.tscn")
	await transition.cover(crypts, true)
	await transition.reveal(crypts, true)
	_assert(transition.get_node("%PassageArt").visible and transition.get_node("%PassageArt").texture != null,
		"crypts card has its own painted threshold")
	transition.instant = true


## Answers dialogues (third choice, i.e. "leave") and takes the first gift
## until no UI is open. Returns whether a gift picker was seen.
func _dismiss_ui(dialogue, picker, cut) -> bool:
	var saw_picker := false
	for step in 20:
		if dialogue.get_node("%Panel").is_visible_in_tree():
			var choices = dialogue.get_node("%Choices")
			if choices.get_child_count() > 0:
				# the stranger's third answer is the one the test expects; shorter lists take their last
				choices.get_child(mini(2, choices.get_child_count() - 1)).pressed.emit()
			else:
				dialogue.get_node("%Continue").pressed.emit()
		elif picker.visible:
			saw_picker = true
			picker.get_node("%Cards").get_child(0).pressed.emit()
		elif cut.playing.begins_with("ch1_prologue"):
			# The one scene worth skipping the way a player does: half a minute
			# of monologue before the first room, with no choice in it. Waiting
			# it out would spend this loop's whole budget on the opening.
			# Either length of it — which one plays depends on the profile the
			# test happens to run against.
			cut._skip()
			await _settle(0.3)
		elif cut.playing != "":
			# A scene is still running: its question has not been asked yet.
			# (The Stranger's choice comes a couple of seconds into the scene,
			# and the curtain between rooms delays it further.)
			await _settle(0.3)
		else:
			await _settle(0.3)
			if not dialogue.get_node("%Panel").is_visible_in_tree() and not picker.visible \
					and cut.playing == "":
				return saw_picker
		await _settle()
	return saw_picker


func _wait_until(condition: Callable, label: String) -> void:
	for attempt in 40:
		if condition.call():
			_assert(true, label)
			return
		await _settle(0.25)
	_assert(false, label + " (timeout)")


func _settle(seconds := 0.2) -> void:
	await create_timer(seconds, true, false, true).timeout
	await process_frame


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failed = true
