class_name Campaign
## What one night leaves the next (docs/CAMPAIGN.md §5–§6, engine E1 and E3).
##
## E1 — flags that outlive their night. data/game.json "flags_kept" lists them:
## a string is a fact learnt once ("version_man"), an array a group of answers
## to one choice (["sided_host", "sided_legion", "sided_none"]) of which the
## last one given is remembered. Set in a night, such a flag is written into
## Profile.data.kept as {flag: the night's id} (a group's answer wipes the
## others of its group); the next night starts with every kept flag in
## Game.flags — except those the same night wrote, so a second Marah does not
## begin with last night's side before the parley. A choice skipped leaves the
## old answer alone. Never online, in the night of the day, in the yard, from a
## tool script (unless a test asks, [member allow_in_tools]) or under --ending=.
##
## E3 — each night's dawn is recorded: Profile.data.dawns[<night id>] is the
## path that led by 2 at that dawn, or "level". A night with "after" is offered
## only once that night has had its dawn (and its "after_dawns" are met). The
## first night is recorded under the game's own id (game.json "id").

const LEVEL := "level"

## A test may let a tool script remember (and must put the profile back).
static var allow_in_tools := false


## The id a night is remembered under: its own, or the game's for the first.
static func night_key(night: String) -> String:
	if night != "":
		return night
	return str(Data.game.get("id", "first"))


## Whether this night may write to, or start from, what other nights left.
static func remembers() -> bool:
	if Net.active or Net.dedicated or Game.daily != "" or Game.practice != "":
		return false
	for arg in OS.get_cmdline_args():
		if arg.begins_with(Endings.ARG):
			return false
		if (arg == "-s" or arg == "--script") and not allow_in_tools:
			return false
	return true


## game.json "flags_kept", every root merged (DataDoc): strings and groups.
static func kept_list() -> Array:
	var out: Array = []
	for entry in Data.game.get("flags_kept", []):
		if entry is String or entry is Array:
			out.append(entry)
	return out


## The group [param flag] belongs to (itself alone for a single fact), or []
## when it is a flag of its night only.
static func group_of(flag: String) -> Array:
	for entry in kept_list():
		if entry is String and entry == flag:
			return [flag]
		if entry is Array and (entry as Array).has(flag):
			return entry
	return []


static func _kept() -> Dictionary:
	if not Profile.data.get("kept") is Dictionary:
		Profile.data.kept = {}
	return Profile.data.kept


## A flag was set tonight (Game.apply_effect, or code through Game.set_flag):
## if it is one that outlives the night, the profile remembers it.
static func keep(flag: String) -> void:
	var group := group_of(flag)
	if group.is_empty() or not remembers():
		return
	var kept := _kept()
	for other in group:
		kept.erase(str(other))
	kept[flag] = night_key(Game.night)
	Profile.save()


## Lays what other nights left into [param flags] (Game.flags) at the start of
## a night. A flag the starting night itself wrote stays out.
static func lay(flags: Dictionary) -> void:
	if not remembers():
		return
	var here := night_key(Game.night)
	for flag in _kept():
		if str(_kept()[flag]) != here and not group_of(str(flag)).is_empty():
			flags[str(flag)] = true


## Takes back what [method lay] put in (before any choice of the night), so a
## night switched at its start — `room=` of another night — lays its own.
static func relay(flags: Dictionary) -> void:
	for flag in _kept():
		flags.erase(str(flag))
	lay(flags)


## The night just dawned (Profile.record_run, won): remember how it leaned.
static func record_dawn() -> void:
	if not remembers():
		return
	if not Profile.data.get("dawns") is Dictionary:
		Profile.data.dawns = {}
	Profile.data.dawns[night_key(Game.night)] = Game.dominant_path() if Game.lead() >= 2 else LEVEL


## Whether this profile may start [param night] (a DataDoc.nights entry): its
## dawns, and the dawn of the night it comes "after", if it names one.
static func night_open(night: Dictionary) -> bool:
	if int(Profile.data.get("wins", 0)) < int(night.get("after_dawns", 0)):
		return false
	var after := str(night.get("after", ""))
	if after == "":
		return true
	var dawns = Profile.data.get("dawns", {})
	return dawns is Dictionary and (dawns as Dictionary).has(after)
