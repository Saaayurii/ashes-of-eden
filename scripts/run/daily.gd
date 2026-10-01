extends RefCounted
class_name Daily
## The night of the day (docs/DAILY.md): one night a calendar day, the same
## for everyone who plays it — the gift cards dealt from the day's seed, one
## vial of wrath chosen by the day whether or not this profile has opened it,
## and nothing the profile carries that another player's would not: no relics,
## every gift in the pool, no saves to try a room twice. The best of the day
## is kept (Profile.data.daily). Game.daily holds the date while one is played.

## Which vials a day may pour: a taste of the ladder, never the top of it.
const VIALS := [1, 2, 3]


## Today in UTC, "YYYY-MM-DD": the same day for every player at once.
static func today() -> String:
	var t := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [t.year, t.month, t.day]


static func seed_of(date: String) -> int:
	return hash("ashes-of-eden:" + date)


static func vial_of(date: String) -> int:
	return VIALS[absi(seed_of(date)) % VIALS.size()]


## The day's best: {"date", "area", "seconds", "won", "tries"}, {} before the first try today.
static func best(date := "") -> Dictionary:
	if date == "":
		date = today()
	var kept: Dictionary = Profile.data.get("daily", {}) if Profile.data.get("daily") is Dictionary else {}
	return kept if str(kept.get("date", "")) == date else {}


## Records a finished daily night; returns whether it is the day's new best.
## Further is better; as far, a dawn beats a death; as both, sooner is better.
static func record(date: String, area: int, seconds: float, won: bool) -> bool:
	var kept := best(date)
	var tries := int(kept.get("tries", 0)) + 1
	var better := kept.is_empty() or area > int(kept.area) \
		or (area == int(kept.area) and won and not bool(kept.won)) \
		or (area == int(kept.area) and won == bool(kept.won) and seconds < float(kept.seconds))
	if better:
		kept = {"date": date, "area": area, "seconds": seconds, "won": won}
	kept["tries"] = tries
	Profile.data.daily = kept
	Profile.save()
	return better
