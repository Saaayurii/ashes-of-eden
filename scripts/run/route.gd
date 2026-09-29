class_name Route
## Chapter I's way through its rooms (docs/CHAPTER1.md): ROOMS in order, with
## forks (data/forks) where the player picks one of two rooms and both come
## out at the same next one. Only rooms that carry no story may be options —
## a scene, a person whose flags are read later, a rest point — so the
## chapter's beats and its exit are the same whichever way is taken.


## The Run's ROOMS, for callers without a Run (the HUD, a save's summary).
static func rooms() -> Array:
	return (load("res://scripts/run/run.gd") as GDScript).get_script_constant_map().get("ROOMS", [])


## The fork whose question is asked leaving [param path], or {}.
static func fork_after(path: String) -> Dictionary:
	for fork in Data.forks.values():
		if str(fork.get("after", "")) == path:
			return fork
	return {}


## The fork [param path] is one of the ways through, or {}.
static func fork_holding(path: String) -> Dictionary:
	for fork in Data.forks.values():
		if (fork.get("options", {}) as Dictionary).values().has(path):
			return fork
	return {}


## The room after [param index]: the one picked ([param choice], an option's
## key; the first when nothing was picked) out of a fork's room, the fork's
## "then" out of one of its options, the next in ROOMS otherwise.
static func next_index(room_list: Array, index: int, choice := "") -> int:
	var path := str(room_list[index])
	var ahead := fork_after(path)
	if not ahead.is_empty():
		var options: Dictionary = ahead.options
		return room_list.find(str(options.get(choice, options.values()[0])))
	var held := fork_holding(path)
	if not held.is_empty():
		return room_list.find(str(held.then))
	return index + 1


## How many rooms in [param index] is along whatever way was walked: the
## number the HUD and the saves show, so a skipped room leaves no gap.
static func step(room_list: Array, index: int) -> int:
	var skipped := 0
	for fork in Data.forks.values():
		var at: Array = (fork.get("options", {}) as Dictionary).values().map(func(p) -> int: return room_list.find(str(p)))
		var first: int = at.min()
		if index > at.max():
			skipped += at.size() - 1
		elif at.has(index):
			skipped += index - first
	return index - skipped


## Rooms in a night whichever way is walked.
static func length(room_list: Array) -> int:
	return step(room_list, room_list.size() - 1) + 1
