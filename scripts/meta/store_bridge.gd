extends RefCounted
class_name StoreBridge
## The deeds mirrored to a store (docs/STEAM.md). The game keeps its own
## achievements (Profile.data.achievements, docs/ACHIEVEMENTS.md); a store only
## hears about them. Steam is reached through the GodotSteam GDExtension, by
## name (Engine.get_singleton), so a build without it — every build today,
## the Web, Android, a tool script — compiles the same and does nothing here.
##
## The deed's id is the store's API name: the same string in data/achievements
## and in the Steamworks partner site.

## Steam's singleton, once started and only if it started (start()).
static var _steam: Object = null


## The store in hand, or null.
static func steam() -> Object:
	return _steam


## Starts Steam if this build carries GodotSteam and Steam is running, then
## mirrors every deed already done (a profile older than the store page, or a
## deed done offline, catches up here). Returns whether a store is in hand.
static func start() -> bool:
	_steam = null
	if not Engine.has_singleton("Steam"):
		return false
	var steam_api: Object = Engine.get_singleton("Steam")
	if steam_api.has_method("steamInitEx"):
		var result = steam_api.call("steamInitEx")
		# {status: 0, verbal: "..."} on success; anything else is a Steam not running
		if result is Dictionary and int(result.get("status", 1)) != 0:
			push_warning("Steam did not start: %s" % result.get("verbal", result))
			return false
	_steam = steam_api
	sync()
	return true


## Pumps Steam's callbacks; the Profile calls it every frame while a store is in hand.
static func poll() -> void:
	if _steam != null and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")


## Tells the store about [param ids] it does not have yet; returns how many it
## was told. One storeStats for the lot: Steam shows its own toast on it.
static func mirror(ids: Array) -> int:
	if _steam == null or ids.is_empty():
		return 0
	var told := 0
	for id in ids:
		var name := str(id)
		if _has(name):
			continue
		if _steam.call("setAchievement", name):
			told += 1
	if told > 0:
		_steam.call("storeStats")
	return told


## Every deed this profile has done, mirrored.
static func sync() -> int:
	var done = Profile.data.get("achievements", {})
	return mirror(done.keys() if done is Dictionary else [])


static func _has(name: String) -> bool:
	if not _steam.has_method("getAchievement"):
		return false
	var got = _steam.call("getAchievement", name)
	return got is Dictionary and bool(got.get("achieved", false))
