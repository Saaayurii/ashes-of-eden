class_name Route
## A night's way through its rooms (docs/CHAPTER1.md): ROOMS in order, with
## forks (data/forks) where the player picks one of two rooms and both come
## out at the same next one. Only rooms that carry no story may be options —
## a scene, a person whose flags are read later, a rest point — so the
## chapter's beats and its exit are the same whichever way is taken.


## The Run's ROOMS, for callers without a Run (the HUD, a save's summary).
static func rooms() -> Array:
	return Data.rooms


## The nights (game.json "nights") this profile may start: the first always,
## a later one once it has seen its "after_dawns" dawns (Profile.data.wins).
## The menu's Play asks which only when there is more than one.
static func open_nights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for night in Data.nights():
		if int(Profile.data.get("wins", 0)) >= int(night.get("after_dawns", 0)):
			out.append(night)
	return out


## What a night is called on the menu: the chapter its first room's place
## belongs to (data/chapters "chapter"), "Chapter II · The Second Trumpet".
static func night_name(night: Dictionary) -> String:
	var rooms: Array = night.get("rooms", [])
	var place: Dictionary = Data.chapter_for(str(rooms[0])) if not rooms.is_empty() else {}
	return TranslationServer.translate(str(place.get("chapter", night.get("id", ""))))


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
		if at.has(-1):
			continue  # another night's fork
		var first: int = at.min()
		if index > at.max():
			skipped += at.size() - 1
		elif at.has(index):
			skipped += index - first
	return index - skipped


## Rooms in a night whichever way is walked.
static func length(room_list: Array) -> int:
	return step(room_list, room_list.size() - 1) + 1
