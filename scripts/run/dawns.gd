class_name Dawns
## The scales of dawns (docs/CAMPAIGN.md §6, docs/CHAPTER7.md §2 and §9, engine E2).
##
## Every night's last dawn is written down by Campaign.record_dawn as the path
## that led by 2 then, or "level". A night with "seed": "dawns" in game.json
## (the Heavenly Hall) does not start from nothing: on a *new* start, every
## other night of the game whose dawn leaned to a path puts +1 on that path,
## and one flag says how the pans hang — weighed_<path> for the heaviest,
## weighed_level for a tie or dawns that were all level, weighed_none when
## there are no dawns at all. The elders read it aloud (ch7_elders).
##
## A loaded save does not weigh again: the counters are in its checkpoint.

const SEED := "dawns"
const FLAGS: Array[String] = ["weighed_grace", "weighed_temptation", "weighed_will", "weighed_level", "weighed_none"]


## How tonight leans, the way a dawn is written down: the path ahead by 2, or "level".
static func lean() -> String:
	return Game.dominant_path() if Game.lead() >= 2 else Campaign.LEVEL


## Whether [param night] (a night id, "" the first) starts on the scales.
static func seeds(night: String) -> bool:
	return str(Data.night_spec(night).get("seed", "")) == SEED


## What the other nights' dawns put on the pans: {grace, temptation, will}
## and the flag that names the result. Pure, for the test.
static func weigh(dawns: Dictionary, night: String) -> Dictionary:
	var weight := {Game.PATH_GRACE: 0, Game.PATH_TEMPTATION: 0, Game.PATH_WILL: 0}
	var counted := 0
	var here := Campaign.night_key(night)
	for key in dawns:
		if str(key) == here:
			continue
		counted += 1
		var path := str(dawns[key])
		if weight.has(path):
			weight[path] += 1
	var flag := "weighed_none"
	if counted > 0:
		flag = "weighed_level"
		var best := 0
		for path in weight:
			if weight[path] > best:
				best = weight[path]
				flag = "weighed_" + path
			elif weight[path] == best and best > 0:
				flag = "weighed_level"
	return {"weight": weight, "flag": flag}


## A new night begins (Run._ready, after the kept flags are laid, before the
## first scene): if it is a night on the scales, lay its weight and its flag.
## Returns the flag set, or "" when this night is not weighed.
static func seed_night() -> String:
	if not seeds(Game.night):
		return ""
	var dawns: Dictionary = {}
	if Campaign.remembers() and Profile.data.get("dawns") is Dictionary:
		dawns = Profile.data.dawns
	var result := weigh(dawns, Game.night)
	for path in result.weight:
		Game.alignment[path] += int(result.weight[path])
	Game.flags[str(result.flag)] = true
	EventBus.alignment_changed.emit(Game.alignment.duplicate())
	return str(result.flag)
