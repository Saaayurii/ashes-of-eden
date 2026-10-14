extends RefCounted
class_name Endings
## How the campaign ends (data/endings, docs/GDD.md §9, docs/STORY_BIBLE.md):
## four endings, none of them the true one. Each names a cutscene that plays
## after the finale (data/game.json "finale"), a line for the night's end and
## a "when" read from the hidden counters and the story flags:
##   path      the night leans this way (Game.dominant_path)
##   lead      ...by at least this much (Game.lead; the aura shows from 2)
##   balanced  the lead is at most this: no side has the night
##   flags     every one of these was set (Game.flags)
##   unless    none of these was
## They are tried in "order"; the one marked "fallback" ends a night none of
## them claims. The fourth is the only one that asks for balance — it is not
## a reward for leaning, it is what is left when nobody wins.
##
## Chapter I is not the end of the campaign: the finale names the room and the
## scene after which it would end, and "ends_campaign" stays false until the
## last region exists. Until then a debug build can ask for an ending on the
## command line (`-- --ending=fourth`, ARG) and endings_test.gd plays each one.

const ARG := "--ending="


static func spec(id: String) -> Dictionary:
	return Data.endings.get(id, {})


## Every ending, in the order they are tried.
static func ids() -> Array:
	var all: Array = Data.endings.keys()
	all.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(spec(a).get("order", 99))
		var ob := int(spec(b).get("order", 99))
		return oa < ob if oa != ob else a < b)
	return all


## Whether this night meets [param id]'s "when" (Game's counters and flags now).
static func holds(id: String) -> bool:
	var when: Dictionary = spec(id).get("when", {})
	if when.is_empty():
		return false
	if when.has("path") and Game.dominant_path() != str(when.path):
		return false
	if when.has("lead") and Game.lead() < int(when.lead):
		return false
	if when.has("balanced") and Game.lead() > int(when.balanced):
		return false
	for flag in when.get("flags", []):
		if not Game.flags.has(str(flag)):
			return false
	for flag in when.get("unless", []):
		if Game.flags.has(str(flag)):
			return false
	return true


## The ending this night has earned: the first in order whose "when" holds,
## else the fallback. "" only for a game with no endings at all.
static func choose() -> String:
	var fallback := ""
	for id in ids():
		if holds(id):
			return id
		if spec(id).get("fallback", false) and fallback == "":
			fallback = id
	return fallback


## data/game.json "finale": {room, cutscene, ends_campaign}. {} for a game without one.
static func finale() -> Dictionary:
	var found = Data.game.get("finale", {})
	return found if found is Dictionary else {}


## Whether walking out of [param room_path] ends the campaign: the finale's room,
## and only once the game says the campaign ends there — or a debug build asked
## for an ending ([param forced]).
static func closes_campaign(room_path: String, forced := "") -> bool:
	var at := finale()
	if at.is_empty() or Data.endings.is_empty() or room_path != str(at.get("room", "")):
		return false
	return forced != "" or bool(at.get("ends_campaign", false))


## Lays counters and flags on Game that [param id]'s "when" accepts, so that
## choose() picks it on its own: what `--ending=` does before it plays one, and
## how endings_test.gd checks the chooser against every ending.
static func seed(id: String) -> void:
	var when: Dictionary = spec(id).get("when", {})
	for path in Game.PATHS:
		Game.alignment[path] = 1 if when.has("balanced") else 0
	if when.has("path"):
		Game.alignment[str(when.path)] = maxi(1, int(when.get("lead", 1)))
	for flag in when.get("flags", []):
		Game.flags[str(flag)] = true
	for flag in when.get("unless", []):
		Game.flags.erase(str(flag))


## Which ending a command line asks for (`--ending=<id>`), or "".
static func from_args(args: PackedStringArray) -> String:
	for arg in args:
		if not arg.begins_with(ARG):
			continue
		var want := arg.substr(ARG.length()).strip_edges()
		if Data.endings.has(want):
			return want
		push_warning("endings: no ending called '%s'. Try one of: %s" % [want, ", ".join(ids())])
	return ""
