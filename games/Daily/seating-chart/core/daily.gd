extends RefCounted
## Daily seed logic: which puzzle a date gets, its number, and its difficulty tier.
## Uses the player's local calendar date, like the other GameTests daily games.

const EPOCH := "2026-10-16"          # puzzle #1
const GAME := "seating-chart"


static func valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	var y := int(d.substr(0, 4))
	var mo := int(d.substr(5, 2))
	var dd := int(d.substr(8, 2))
	var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	var days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if mo < 1 or mo > 12 or dd < 1 or dd > days[mo - 1]:
		return false
	var u := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return Time.get_date_string_from_unix_time(u) == d


static func today_local() -> String:
	return Time.get_date_string_from_system(false)


static func day_number(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(EPOCH + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0)) + 1


static func add_days(d: String, k: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + k * 86400)


## 0 = Sunday ... 6 = Saturday
static func weekday(d: String) -> int:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	return int(t.weekday)


## Monday easy, Tue-Wed medium, Thu-Fri tricky, weekend hard.
static func tier_for(d: String) -> int:
	match weekday(d):
		1: return 0
		2, 3: return 1
		4, 5: return 2
	return 3


## Seed for a date's puzzle (attempt > 0 re-rolls deterministically).
static func seed_for(d: String, attempt: int = 0) -> int:
	return ("%s:%s:%d" % [GAME, d, attempt]).hash()


static func short_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t.weekday)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t.month) - 1]
	return "%s %s %d" % [wd, mo, int(t.day)]
