class_name PTDaily
extends RefCounted
## Dates, puzzle numbers, seeds and the weekly difficulty cadence. All dates are UTC
## "YYYY-MM-DD" strings so every player gets the same puzzle on the same day.

const GAME := "plans-tonight"
const EPOCH := "2026-10-16"   # puzzle #1
const DAY := 86400

const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

const EASY_TYPES := ["max_price", "setting", "wants_food", "max_travel", "min_start", "max_end",
	"no_food_type", "no_activity"]
const MEDIUM_TYPES := EASY_TYPES + ["max_start", "not_loud", "not_quiet", "min_end"]
const HARD_TYPES := MEDIUM_TYPES + ["max_duration", "min_duration"]

## Mon easy → Fri/Sat hard, Sunday medium. Saturday is the "funny" day (birthday theme).
## max_elim caps how many plans one clue may rule out (as a share of the wrong plans).
const CADENCE := {
	1: {"label": "Easy", "plans": 4, "friends": 3, "types": "easy", "max_elim": 0.67, "small": false, "theme": "night"},
	2: {"label": "Easy", "plans": 5, "friends": 4, "types": "easy", "max_elim": 0.5, "small": false, "theme": "night"},
	3: {"label": "Medium", "plans": 5, "friends": 4, "types": "medium", "max_elim": 0.5, "small": true, "theme": "night"},
	4: {"label": "Medium", "plans": 6, "friends": 4, "types": "medium", "max_elim": 0.4, "small": true, "theme": "night"},
	5: {"label": "Hard", "plans": 7, "friends": 5, "types": "hard", "max_elim": 0.34, "small": true, "theme": "night"},
	6: {"label": "Hard", "plans": 8, "friends": 5, "types": "hard", "max_elim": 0.34, "small": true, "theme": "birthday"},
	0: {"label": "Medium", "plans": 6, "friends": 4, "types": "medium", "max_elim": 0.4, "small": true, "theme": "night"},
}


static func is_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	# Round-trip to reject things like 2026-02-31.
	return date_for_unix(unix(d)) == d


static func unix(d: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))


static func date_for_unix(t: int) -> String:
	return Time.get_date_string_from_unix_time(t)


static func today() -> String:
	return Time.get_date_string_from_system(true)


static func date_add(d: String, days: int) -> String:
	return date_for_unix(unix(d) + days * DAY)


static func day_number(d: String) -> int:
	return int(round(float(unix(d) - unix(EPOCH)) / DAY)) + 1


static func weekday(d: String) -> int:
	return int(Time.get_datetime_dict_from_unix_time(unix(d)).weekday)


static func seed_key(d: String) -> String:
	return "%s|%s" % [GAME, d]


static func seed_for(d: String) -> int:
	return hash(seed_key(d))


## "Fri, Oct 16"
static func pretty(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix(d))
	return "%s, %s %d" % [WEEKDAYS[int(t.weekday)].substr(0, 3), MONTHS[int(t.month) - 1], int(t.day)]


## Generator settings for a date.
static func config(d: String) -> Dictionary:
	var c: Dictionary = CADENCE[weekday(d)].duplicate(true)
	match String(c.types):
		"easy": c.types = EASY_TYPES.duplicate()
		"medium": c.types = MEDIUM_TYPES.duplicate()
		_: c.types = HARD_TYPES.duplicate()
	return c
