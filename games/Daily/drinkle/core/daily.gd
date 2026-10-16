extends RefCounted
## Which mystery drink a date gets. One global drink per (local) calendar day, the same for
## everyone, reproducible forever.
##
## data/schedule.json pins the answer for every date it lists (written by tools/schedule.gd), so
## adding drinks later never changes a past puzzle. Dates beyond it fall back to the same
## deterministic rule the tool uses:
##   weekday -> tier (Mon-Tue Easy, Wed-Fri Medium, Sat-Sun Hard); the k-th day of a tier since
##   puzzle #1 takes item k of that tier's pool, shuffled per cycle with a date-free seed, so no
##   answer repeats until its tier pool has been used up.

const DB = preload("res://core/db.gd")
const Analysis = preload("res://core/analysis.gd")

const EPOCH := "2026-10-16"          # puzzle #1
const GAME := "mystery-drink"     # seed salt; kept from the original name so answers never change
const SCHEDULE_PATH := "res://data/schedule.json"

static var _schedule: Dictionary = {}
static var _schedule_loaded := false
static var _pools: Array = []


static func valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	var mo := int(d.substr(5, 2))
	var dd := int(d.substr(8, 2))
	if mo < 1 or mo > 12 or dd < 1 or dd > 31:
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
	return int(Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00")).weekday)


static func tier_for(d: String) -> int:
	match weekday(d):
		1, 2: return 0
		3, 4, 5: return 1
	return 2


static func short_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t.weekday)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t.month) - 1]
	return "%s %s %d" % [wd, mo, int(t.day)]


static func seed_for(text: String) -> int:
	return ("%s:%s" % [GAME, text]).hash()


static var _file: Dictionary = {}


static func _load_file() -> void:
	if _schedule_loaded:
		return
	_schedule_loaded = true
	if FileAccess.file_exists(SCHEDULE_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SCHEDULE_PATH))
		if data is Dictionary:
			_file = data
			if data.get("days") is Dictionary:
				_schedule = data.days


static func schedule() -> Dictionary:
	_load_file()
	return _schedule


## Tier pools as pinned in schedule.json (so a phone never runs the analyser), or freshly
## computed when the file has none or the database has changed since it was written.
static func pools() -> Array:
	if _pools.is_empty():
		_load_file()
		var p = _file.get("pools")
		if p is Array and p.size() == 3 and int(_file.get("fingerprint", -1)) == DB.fingerprint():
			for tier in p:
				var ids: Array = []
				for id in tier:
					if DB.has(String(id)):
						ids.append(String(id))
				_pools.append(ids)
		else:
			_pools = Analysis.tier_pools()
	return _pools


## Score/tier recorded for a drink in schedule.json, or computed.
static func difficulty_of(id: String) -> Dictionary:
	_load_file()
	var d = _file.get("difficulty", {}).get(id)
	if d is Dictionary:
		return {"score": int(d.score), "tier": int(d.tier)}
	var a := Analysis.difficulty(DB.get_drink(id))
	return {"score": int(a.score), "tier": int(a.tier)}


## Forget cached files (tests and tools).
static func reset_cache() -> void:
	_schedule = {}
	_schedule_loaded = false
	_file = {}
	_pools = []
	_orders = {}


## How many earlier days since puzzle #1 share this date's tier (0 for the first one; negative
## before puzzle #1, so even those dates are deterministic).
static func tier_index(d: String) -> int:
	var t := tier_for(d)
	var weeks := floori((day_number(d) - 1) / 7.0)
	var count := weeks * _tier_days_per_week(t)
	var x := add_days(EPOCH, weeks * 7)
	while x < d:
		if tier_for(x) == t:
			count += 1
		x = add_days(x, 1)
	return count


static func _tier_days_per_week(t: int) -> int:
	return [2, 3, 2][t]


static func shuffled_pool(tier: int, cycle: int) -> Array:
	var pool: Array = pools()[tier].duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for("tier%d:cycle%d" % [tier, cycle])
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool


static var _orders: Dictionary = {}


## A tier's answers in the order cycle `cycle` uses them: a seeded shuffle, then the drinks used
## at the end of the previous cycle are pushed out of the first few slots so an answer never
## comes back within a few days of itself.
static func cycle_order(tier: int, cycle: int) -> Array:
	var key := "%d:%d" % [tier, cycle]
	if _orders.has(key):
		return _orders[key]
	var perm := shuffled_pool(tier, cycle)
	if cycle > 0 and perm.size() > 3:
		var w := mini(perm.size() / 3, 5)
		var prev := cycle_order(tier, cycle - 1)
		var tail := prev.slice(prev.size() - w)
		var fresh: Array = perm.filter(func(x): return not tail.has(x))
		var head := fresh.slice(0, w)
		var rest: Array = perm.filter(func(x): return not head.has(x))
		perm = head + rest
	_orders[key] = perm
	return perm


## The rule-based answer for a date (ignores the pinned schedule).
static func computed_target(d: String) -> String:
	var t := tier_for(d)
	var size: int = pools()[t].size()
	if size == 0:
		return ""
	var k := tier_index(d)
	return cycle_order(t, floori(float(k) / size))[posmod(k, size)]


## The answer id for a date: pinned schedule first, rule-based otherwise.
static func target_id(d: String) -> String:
	var s := schedule()
	if s.has(d) and DB.has(String(s[d])):
		return String(s[d])
	return computed_target(d)


static func target(d: String) -> Dictionary:
	return DB.get_drink(target_id(d))
