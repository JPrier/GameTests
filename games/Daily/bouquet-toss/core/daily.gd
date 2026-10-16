extends RefCounted
## Daily-seed logic: which level a date gets, its number and its venue for the weekday.
## Uses the player's local calendar date, like the other GameTests daily games, so the puzzle
## changes at local midnight. All date maths goes through unix days at UTC noon-free midnight,
## which has no daylight-saving gaps.

const Rng = preload("res://core/rng.gd")

const EPOCH := "2026-10-16"          # puzzle #1
const GAME := "bouquet-toss"

## Weekday -> venue archetype. Easy at the start of the week, trickiest on Sunday.
const ARCHETYPES := ["bank", "open", "chandelier", "cake", "arch", "balcony", "garden"]


static func valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	var y := int(d.substr(0, 4))
	var mo := int(d.substr(5, 2))
	var dd := int(d.substr(8, 2))
	if y < 2000 or y > 2200:
		return false
	var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	var days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return mo >= 1 and mo <= 12 and dd >= 1 and dd <= days[mo - 1]


static func unix_of(d: String) -> int:
	return Time.get_unix_time_from_datetime_string(d + "T00:00:00")


static func today_local() -> String:
	return Time.get_date_string_from_system(false)


## The calendar date for a moment, given the player's UTC offset in minutes (e.g. -240 for
## New York in summer). This is what decides "today", so it is the time-zone-sensitive part.
static func date_at(unix_seconds: int, utc_offset_minutes: int) -> String:
	return Time.get_date_string_from_unix_time(unix_seconds + utc_offset_minutes * 60)


static func day_number(d: String) -> int:
	return int((unix_of(d) - unix_of(EPOCH)) / 86400) + 1


static func date_for_number(n: int) -> String:
	return Time.get_date_string_from_unix_time(unix_of(EPOCH) + (n - 1) * 86400)


static func add_days(d: String, k: int) -> String:
	return Time.get_date_string_from_unix_time(unix_of(d) + k * 86400)


## 0 = Sunday ... 6 = Saturday
static func weekday(d: String) -> int:
	# 1970-01-01 was a Thursday (4).
	return posmod(int(unix_of(d) / 86400) + 4, 7)


static func archetype_for(d: String) -> String:
	return ARCHETYPES[weekday(d)]


## Seed for a date's level (attempt > 0 re-rolls deterministically).
static func seed_for(d: String, attempt: int = 0) -> int:
	return Rng.hash_str("%s:%s:%d" % [GAME, d, attempt])


static func short_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix_of(d))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday(d)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t.month) - 1]
	return "%s %s %d" % [wd, mo, int(t.day)]
