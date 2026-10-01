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
	_extend_streak(date)
	Profile.save()
	Profile.check_achievements()
	return better


## Days in a row a night of the day was played: {"last", "days", "best"}
## (Profile.data.daily_streak). A second try on the same day changes nothing;
## the day after the last one adds a day; any gap starts again at one. The
## best is also the counter a deed reads (deeds.daily_streak).
static func streak() -> Dictionary:
	var kept = Profile.data.get("daily_streak", {})
	return kept if kept is Dictionary else {}


## The streak as it stands today: the days, or 0 once a day has been missed.
static func streak_days(today_date := "") -> int:
	if today_date == "":
		today_date = today()
	var kept := streak()
	var last := str(kept.get("last", ""))
	return int(kept.get("days", 0)) if last == today_date or last == day_before(today_date) else 0


static func day_before(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
	return Time.get_date_string_from_unix_time(unix - 86400)


static func _extend_streak(date: String) -> void:
	var kept := streak()
	var last := str(kept.get("last", ""))
	if last == date:
		return
	var days := int(kept.get("days", 0)) + 1 if last == day_before(date) else 1
	var best_days := maxi(int(kept.get("best", 0)), days)
	Profile.data.daily_streak = {"last": date, "days": days, "best": best_days}
	if not (Profile.data.get("deeds") is Dictionary):
		Profile.data.deeds = {}
	Profile.data.deeds["daily_streak"] = maxi(int(Profile.data.deeds.get("daily_streak", 0)), best_days)
